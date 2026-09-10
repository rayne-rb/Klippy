using System.Net;
using System.Net.Sockets;
using System.Text;
using Klippy.Shared;
using Klippy.Shared.Audio;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// The media transport: one UDP socket carrying encoded frames out to every listener.
///
/// UDP rather than TCP because a retransmit stalls the stream to deliver data that is
/// already too late to play — you pay latency for a correction you cannot use, where a
/// lost frame can simply be concealed and stepped past.
///
/// Listeners are never configured, only learned. A listener proves itself with the
/// ephemeral key from its offer, and the address it is sent to is whatever address that
/// hello arrived from, which is what makes a phone changing networks a non-event.
/// </summary>
public sealed class AudioCastUdpServer(
    AudioCastSessions sessions,
    ILogger<AudioCastUdpServer> logger) : BackgroundService
{
    /// <summary>The bound port, told to each listener in its offer. Zero until started.</summary>
    public int Port { get; private set; }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var socket = Bind();

        logger.LogInformation("Audio cast UDP socket listening on port {Port}", Port);

        try
        {
            await Task.WhenAll(
                ReceiveLoopAsync(socket, stoppingToken),
                SweepLoopAsync(stoppingToken));
        }
        catch (OperationCanceledException)
        {
            // Normal shutdown.
        }
        finally
        {
            await sessions.StopAllAsync();
        }
    }

    /// <summary>
    /// Takes the well-known port when it can, an ephemeral one when it cannot. The port
    /// travels in every offer, so falling back costs a firewall rule and nothing else.
    /// </summary>
    private Socket Bind()
    {
        var socket = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);

        try
        {
            socket.Bind(new IPEndPoint(IPAddress.Any, AudioCastTransport.DefaultUdpPort));
        }
        catch (SocketException ex)
        {
            logger.LogWarning(ex,
                "Port {Port} is unavailable; taking an ephemeral port instead",
                AudioCastTransport.DefaultUdpPort);
            socket.Bind(new IPEndPoint(IPAddress.Any, 0));
        }

        Port = ((IPEndPoint)socket.LocalEndPoint!).Port;
        return socket;
    }

    /// <summary>
    /// Reads hellos. This socket carries nothing else inbound, so anything that is not
    /// a hello with a key we minted is simply dropped — it is an unauthenticated port on
    /// a home network and unsolicited traffic is expected, not exceptional.
    /// </summary>
    private async Task ReceiveLoopAsync(Socket socket, CancellationToken cancellationToken)
    {
        // A hello is a few dozen bytes; this is generous.
        var buffer = new byte[1024];
        var from = new IPEndPoint(IPAddress.Any, 0);

        while (!cancellationToken.IsCancellationRequested)
        {
            SocketReceiveFromResult received;

            try
            {
                received = await socket.ReceiveFromAsync(buffer, SocketFlags.None, from, cancellationToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (SocketException ex)
            {
                // On Windows a rejected send can surface as a receive error. Not fatal.
                logger.LogDebug(ex, "Audio cast receive failed; continuing");
                continue;
            }

            if (received.RemoteEndPoint is not IPEndPoint endpoint)
            {
                continue;
            }

            var hello = TryReadHello(buffer.AsSpan(0, received.ReceivedBytes));
            if (hello is null)
            {
                logger.LogDebug("Ignoring {Bytes} bytes from {Endpoint}: not a hello",
                    received.ReceivedBytes, endpoint);
                continue;
            }

            var session = sessions.Claim(hello.StreamKey, endpoint);
            if (session is null)
            {
                logger.LogDebug("Ignoring a hello from {Endpoint}: unknown stream key", endpoint);
                continue;
            }

            StartSending(socket, session, cancellationToken);
        }
    }

    private static AudioCastHello? TryReadHello(ReadOnlySpan<byte> datagram)
    {
        try
        {
            var hello = KlippyJson.Deserialize<AudioCastHello>(Encoding.UTF8.GetString(datagram));
            return string.IsNullOrWhiteSpace(hello?.StreamKey) ? null : hello;
        }
        catch (Exception ex) when (ex is System.Text.Json.JsonException or DecoderFallbackException or ArgumentException)
        {
            return null;
        }
    }

    /// <summary>Starts a listener's send loop, once, on its first hello.</summary>
    private void StartSending(Socket socket, AudioCastSession session, CancellationToken cancellationToken)
    {
        if (session.Sender is not null)
        {
            return;
        }

        var sender = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        session.Sender = sender;

        _ = Task.Run(() => SendLoopAsync(socket, session, sender.Token), CancellationToken.None);
    }

    /// <summary>
    /// Drains one listener's queue onto the socket.
    ///
    /// Every listener sends from the same bound port on purpose. The phone opened the
    /// conversation, so its own firewall and any NAT in between only expect replies
    /// from the address and port it sent to; answering from a fresh socket per listener
    /// would be silently dropped on the way back.
    /// </summary>
    private async Task SendLoopAsync(Socket socket, AudioCastSession session, CancellationToken cancellationToken)
    {
        var datagram = new byte[AudioCastPacket.MaxDatagramBytes];
        long sent = 0, oversized = 0;

        try
        {
            await foreach (var frame in session.Subscription.ReadAllAsync(cancellationToken))
            {
                if (session.Endpoint is not { } endpoint)
                {
                    continue;
                }

                if (frame.Payload.Length > AudioCastPacket.MaxPayloadBytes)
                {
                    // Would fragment, and a fragmented frame loses everything if either
                    // half goes missing. Dropping one 5 ms frame is the cheaper failure.
                    oversized++;
                    continue;
                }

                var length = AudioCastPacket.Write(datagram, frame.Header, frame.Payload.Span);

                try
                {
                    await socket.SendToAsync(
                        datagram.AsMemory(0, length), SocketFlags.None, endpoint, cancellationToken);
                    sent++;
                }
                catch (SocketException ex)
                {
                    // A phone that has gone away produces these until the sweep notices.
                    logger.LogDebug(ex, "Send to {Endpoint} failed", endpoint);
                }
            }
        }
        catch (OperationCanceledException)
        {
            // Cast ended.
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Send loop for '{Device}' failed", session.DeviceName);
        }
        finally
        {
            logger.LogInformation(
                "Sent {Sent} frames to '{Device}'{Oversized}",
                sent, session.DeviceName,
                oversized > 0 ? $", dropped {oversized} that would have fragmented" : string.Empty);
        }
    }

    /// <summary>
    /// Expires listeners that stopped saying hello. A phone that walks out of range
    /// never says goodbye, so this is the only thing that stops its capture.
    /// </summary>
    private async Task SweepLoopAsync(CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(AudioCastTransport.HelloInterval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            await sessions.SweepAsync();
        }
    }
}
