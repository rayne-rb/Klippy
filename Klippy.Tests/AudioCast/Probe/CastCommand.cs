using System.Diagnostics;
using System.Net;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using Concentus;
using Klippy.Shared;
using Klippy.Shared.Audio;
using Klippy.Shared.Link;
using Klippy.Shared.Pairing;
using Microsoft.Extensions.Logging;

namespace Klippy.Tests.AudioCast.Probe;

/// <summary>
/// Step 4 end to end against a running server: pair, ask over the Link, prove the
/// ephemeral key over UDP, then decode what comes back.
///
/// This is the first thing in the pipeline that exercises the real control path and the
/// real transport together, which is exactly what a phone will do. Anything it finds is
/// a bug the phone would otherwise have found for us, on a device with no debugger
/// attached.
/// </summary>
internal static class CastCommand
{
    public static async Task<int> RunAsync(
        string[] args,
        ILoggerFactory loggerFactory,
        CancellationToken cancellationToken)
    {
        var baseUrl = (ProbeArgs.Value(args, "--server") ?? "http://localhost:5068").TrimEnd('/');
        var seconds = ProbeArgs.Seconds(args, 5.0);
        var channels = ProbeArgs.Channels(args);
        var output = ProbeArgs.Value(args, "--out") ?? "/tmp/klippy-cast.wav";

        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            Console.Error.WriteLine("--channels must be 1 or 2.");
            return 1;
        }

        using var http = new HttpClient { BaseAddress = new Uri(baseUrl), Timeout = TimeSpan.FromSeconds(10) };

        var token = await PairAsync(http, cancellationToken);
        if (token is null)
        {
            return 1;
        }

        var wsUrl = baseUrl.Replace("http://", "ws://").Replace("https://", "wss://");
        using var link = new ClientWebSocket();
        await link.ConnectAsync(new Uri($"{wsUrl}/api/link/ws?token={Uri.EscapeDataString(token)}"), cancellationToken);
        Console.WriteLine("Link connected.");

        var offer = await RequestCastAsync(link, channels, cancellationToken);
        if (offer is null)
        {
            return 1;
        }

        Console.WriteLine($"Offer: UDP {offer.UdpPort}, {offer.Format.Codec} {offer.Format.SampleRate} Hz " +
                          $"{offer.Format.Channels} ch from '{offer.Format.SourceName}'");
        Console.WriteLine($"       key {offer.StreamKey[..8]}... ({offer.StreamKey.Length} chars)\n");

        var result = await ReceiveAsync(
            new Uri(baseUrl).Host, offer, seconds, output, cancellationToken);

        await SendAsync(link, LinkEnvelope.Create(KlippyEvents.AudioCastStop), cancellationToken);

        try
        {
            await link.CloseAsync(WebSocketCloseStatus.NormalClosure, "done", CancellationToken.None);
        }
        catch (WebSocketException ex)
        {
            // The server tears the socket down without returning a close frame:
            // LinkConnection.DisposeAsync only closes while the state is still Open, and
            // by the time it runs the state is CloseReceived. Harmless, but it means no
            // client can rely on a clean handshake.
            Console.WriteLine($"(link closed without a handshake: {ex.WebSocketErrorCode})");
        }

        if (result == 0 && ProbeArgs.Flag(args, "--play"))
        {
            await ProbeArgs.PlayAsync(output);
        }

        return result;
    }

    /// <summary>
    /// Pairs and self-approves. Approval is loopback-only on the server, which is what
    /// makes this safe to automate and only from this machine.
    /// </summary>
    private static async Task<string?> PairAsync(HttpClient http, CancellationToken cancellationToken)
    {
        var created = await http.PostAsJsonAsync("/api/pairing/requests", new PairingRequestInput
        {
            DeviceKind = DeviceKind.Mobile,
            DeviceName = $"AudioProbe {Environment.MachineName}",
            Platform = $"{Environment.OSVersion.Platform} probe",
        }, KlippyJson.Options, cancellationToken);

        if (!created.IsSuccessStatusCode)
        {
            Console.Error.WriteLine($"Pairing request failed: {created.StatusCode}. Is the server running?");
            return null;
        }

        var request = await created.Content.ReadFromJsonAsync<PairingRequestCreated>(
            KlippyJson.Options, cancellationToken);

        if (request is null)
        {
            Console.Error.WriteLine("Pairing request returned nothing usable.");
            return null;
        }

        Console.WriteLine($"Pairing code {request.Code}, self-approving over loopback...");

        var approved = await http.PostAsync(
            $"/api/pairing/admin/requests/{request.RequestId}/approve", null, cancellationToken);

        if (!approved.IsSuccessStatusCode)
        {
            Console.Error.WriteLine($"Approve failed: {approved.StatusCode}");
            return null;
        }

        var state = await http.GetFromJsonAsync<PairingRequestState>(
            $"/api/pairing/requests/{request.RequestId}", KlippyJson.Options, cancellationToken);

        if (state?.Token is null)
        {
            Console.Error.WriteLine($"No token after approval (status {state?.Status}).");
            return null;
        }

        Console.WriteLine($"Paired as {state.DeviceId}.");
        return state.Token;
    }

    /// <summary>Asks to cast and waits for the targeted offer that carries the key.</summary>
    private static async Task<AudioCastOfferPayload?> RequestCastAsync(
        ClientWebSocket link,
        int channels,
        CancellationToken cancellationToken)
    {
        await SendAsync(link, LinkEnvelope.Create(
            KlippyEvents.AudioCastStart, new AudioCastStartPayload { Channels = channels }), cancellationToken);

        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(10));

        var buffer = new byte[64 * 1024];

        try
        {
            while (true)
            {
                var received = await link.ReceiveAsync(buffer, deadline.Token);
                if (received.MessageType == WebSocketMessageType.Close)
                {
                    Console.Error.WriteLine("Link closed while waiting for the offer.");
                    return null;
                }

                var envelope = LinkEnvelope.TryParse(Encoding.UTF8.GetString(buffer, 0, received.Count));
                if (envelope?.Type == KlippyEvents.AudioCastOffer)
                {
                    return envelope.PayloadAs<AudioCastOfferPayload>();
                }
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            // The server logs why on its side; a capture that cannot open never answers.
            Console.Error.WriteLine("No offer within 10s. Check the server log for a capture error.");
            return null;
        }
    }

    /// <summary>
    /// Proves the key over UDP, then decodes the stream. The hello repeats as a
    /// keepalive: it is also what would move the stream to a new address if this were a
    /// phone changing networks.
    /// </summary>
    private static async Task<int> ReceiveAsync(
        string host,
        AudioCastOfferPayload offer,
        double seconds,
        string output,
        CancellationToken cancellationToken)
    {
        var addresses = await Dns.GetHostAddressesAsync(host, cancellationToken);
        var server = new IPEndPoint(
            addresses.First(a => a.AddressFamily == AddressFamily.InterNetwork), offer.UdpPort);

        using var udp = new UdpClient(new IPEndPoint(IPAddress.Any, 0));
        var hello = Encoding.UTF8.GetBytes(KlippyJson.Serialize(new AudioCastHello { StreamKey = offer.StreamKey }));

        await udp.SendAsync(hello, server, cancellationToken);
        Console.WriteLine($"Hello sent to {server} from local port " +
                          $"{((IPEndPoint)udp.Client.LocalEndPoint!).Port}.");

        using var stopping = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var keepalive = KeepAliveAsync(udp, server, hello, stopping.Token);

        var channels = offer.Format.Channels;
        using var decoder = OpusCodecFactory.CreateDecoder(offer.Format.SampleRate, channels);
        await using var wav = await WavWriter.CreateAsync(output, channels, offer.Format.SampleRate);

        var pcm = new float[AudioCastFormat.SamplesPerChannel * channels];
        var gaps = new List<double>();
        var worstGap = 0.0;
        long worstGapAt = 0;
        var expectedFrames = (long)Math.Round(seconds * 1000 / AudioCastFormat.FrameMilliseconds);

        long datagrams = 0, sequenceGaps = 0, lostFrames = 0, malformed = 0, nonSilent = 0;
        uint? previousSequence = null;
        uint firstTimestamp = 0;
        var peak = 0f;
        var clock = Stopwatch.StartNew();
        var previousArrival = 0.0;

        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(seconds + 15));

        try
        {
            while (datagrams < expectedFrames)
            {
                var received = await udp.ReceiveAsync(deadline.Token);

                if (!AudioCastPacket.TryRead(received.Buffer, out var header, out var payload))
                {
                    malformed++;
                    continue;
                }

                var now = clock.Elapsed.TotalMilliseconds;
                if (datagrams > 0)
                {
                    var gap = now - previousArrival;
                    gaps.Add(gap);

                    if (gap > worstGap)
                    {
                        worstGap = gap;
                        worstGapAt = datagrams;
                    }
                }
                else
                {
                    firstTimestamp = header.TimestampMs;
                }

                previousArrival = now;

                if (previousSequence is { } previous)
                {
                    var advance = header.Sequence - previous;
                    if (advance != 1)
                    {
                        sequenceGaps++;
                        lostFrames += advance > 1 ? advance - 1 : 0;
                    }
                }

                previousSequence = header.Sequence;
                datagrams++;

                var produced = decoder.Decode(payload, pcm, AudioCastFormat.SamplesPerChannel, decode_fec: false);
                if (produced != AudioCastFormat.SamplesPerChannel)
                {
                    Console.Error.WriteLine($"Decode returned {produced} on sequence {header.Sequence}.");
                    return 1;
                }

                var hasSignal = false;
                foreach (var sample in pcm)
                {
                    var magnitude = Math.Abs(sample);
                    if (magnitude > peak)
                    {
                        peak = magnitude;
                    }

                    if (magnitude > 1e-6f)
                    {
                        hasSignal = true;
                    }
                }

                if (hasSignal)
                {
                    nonSilent++;
                }

                wav.Write(pcm);
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            Console.Error.WriteLine($"Timed out after {datagrams} datagram(s).");
        }
        finally
        {
            await stopping.CancelAsync();
            try
            {
                await keepalive;
            }
            catch (OperationCanceledException)
            {
                // Expected.
            }
        }

        clock.Stop();

        if (datagrams == 0)
        {
            Console.Error.WriteLine("No audio arrived. The key was refused, or nothing is being captured.");
            return 1;
        }

        var lastTimestamp = firstTimestamp + ((datagrams - 1 + lostFrames) * AudioCastFormat.FrameMilliseconds);
        gaps.Sort();

        Console.WriteLine($"datagrams     {datagrams}  ({datagrams * AudioCastFormat.FrameMilliseconds} ms of audio " +
                          $"in {clock.Elapsed.TotalMilliseconds:F0} ms wall)");
        Console.WriteLine($"arrival gap   mean {gaps.Average():F2}  p50 {gaps[gaps.Count / 2]:F2}  " +
                          $"p99 {gaps[(int)(gaps.Count * 0.99)]:F2}  max {gaps[^1]:F2} ms");
        Console.WriteLine($"worst gap     {worstGap:F2} ms at frame {worstGapAt} of {datagrams}" +
                          $"{(worstGapAt <= 2 ? " (start-up, not steady state)" : string.Empty)}");
        Console.WriteLine($"sequence      {sequenceGaps} gap(s), {lostFrames} frame(s) lost");
        Console.WriteLine($"timestamps    {firstTimestamp} -> {lastTimestamp} ms (5 ms per frame, from the capture clock)");
        Console.WriteLine($"malformed     {malformed}");
        Console.WriteLine($"decoded pcm   {wav.DataBytes} B");
        Console.WriteLine($"signal        peak {peak:F4}, {nonSilent} of {datagrams} frames non-silent");
        Console.WriteLine($"\nWrote {output}");

        return 0;
    }

    private static async Task KeepAliveAsync(
        UdpClient udp,
        IPEndPoint server,
        byte[] hello,
        CancellationToken cancellationToken)
    {
        using var timer = new PeriodicTimer(AudioCastTransport.HelloInterval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            await udp.SendAsync(hello, server, cancellationToken);
        }
    }

    private static Task SendAsync(ClientWebSocket socket, LinkEnvelope envelope, CancellationToken cancellationToken) =>
        socket.SendAsync(
            Encoding.UTF8.GetBytes(envelope.ToJson()),
            WebSocketMessageType.Text,
            endOfMessage: true,
            cancellationToken);
}
