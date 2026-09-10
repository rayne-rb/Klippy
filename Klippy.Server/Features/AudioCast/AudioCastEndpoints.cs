using System.Net.WebSockets;
using System.Text;
using Klippy.Server.Features.Pairing;
using Klippy.Shared;
using Klippy.Shared.Audio;

namespace Klippy.Server.Features.AudioCast;

public static class AudioCastEndpoints
{
    public static IEndpointRouteBuilder MapAudioCastEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/audio").WithTags("Audio");

        // What this machine can capture, for the picker in the UI and on the phone.
        group.MapGet("/devices", async (IAudioSourceCatalog catalog, CancellationToken ct) =>
            Results.Ok(await catalog.ListAsync(ct)));

        // Who is casting, without needing to be on the Link to have heard the last
        // audio.cast.state.
        group.MapGet("/state", (AudioCastSessions sessions) => Results.Ok(sessions.Snapshot()));

        group.MapGet("/codec", (OpusEncoderPool encoders) => Results.Ok(encoders.Diagnostics));

        group.Map("/stream", StreamAsync);

        return routes;
    }

    /// <summary>
    /// The WebSocket fallback, carrying the identical packet format.
    ///
    /// Kept for two reasons: a network that deprioritises or blocks UDP, and debugging,
    /// where being able to point a desktop client at a reliable ordered stream removes
    /// the transport from the list of suspects. It is deliberately not the primary path
    /// — a retransmit here stalls the stream to deliver audio that is already too late
    /// to play.
    ///
    /// Unlike the UDP path this needs no stream key: the socket is authenticated by the
    /// same pairing token as the Link. It also does not register a session, so a
    /// fallback listener does not appear in audio.cast.state.
    /// </summary>
    private static async Task StreamAsync(
        HttpContext context,
        PairingService pairing,
        AudioBroadcaster broadcaster,
        ILoggerFactory loggerFactory)
    {
        if (!context.WebSockets.IsWebSocketRequest)
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("Expected a WebSocket upgrade.");
            return;
        }

        var device = await pairing.AuthenticateAsync(ReadToken(context), context.RequestAborted);
        if (device is null)
        {
            // Refused before the upgrade so the client gets a real status code.
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        var channels = int.TryParse(context.Request.Query["channels"], out var requested) ? requested : 2;
        if (!AudioCastFormat.IsSupportedChannelCount(channels))
        {
            context.Response.StatusCode = StatusCodes.Status400BadRequest;
            await context.Response.WriteAsync("channels must be 1 or 2.");
            return;
        }

        var deviceId = context.Request.Query["device"].FirstOrDefault();
        var logger = loggerFactory.CreateLogger($"Klippy.AudioCast.{device.DeviceName}");

        IAudioSubscription subscription;
        try
        {
            subscription = await broadcaster.SubscribeAsync(deviceId, channels, context.RequestAborted);
        }
        catch (Exception ex) when (ex is InvalidOperationException or PlatformNotSupportedException
                                       or ArgumentOutOfRangeException)
        {
            // Said before the upgrade, where it can still be a status code and a reason.
            context.Response.StatusCode = StatusCodes.Status503ServiceUnavailable;
            await context.Response.WriteAsync(ex.Message);
            return;
        }

        using var socket = await context.WebSockets.AcceptWebSocketAsync();

        await using (subscription)
        {
            long sent = 0;

            try
            {
                // Negotiation leads, as text. On this transport framing is free, so
                // unlike UDP there is no risk of the listener missing it.
                await socket.SendAsync(
                    Encoding.UTF8.GetBytes(KlippyJson.Serialize(subscription.Format)),
                    WebSocketMessageType.Text,
                    endOfMessage: true,
                    context.RequestAborted);

                var datagram = new byte[AudioCastPacket.MaxDatagramBytes];

                await foreach (var frame in subscription.ReadAllAsync(context.RequestAborted))
                {
                    if (frame.Payload.Length > AudioCastPacket.MaxPayloadBytes)
                    {
                        continue;
                    }

                    var length = AudioCastPacket.Write(datagram, frame.Header, frame.Payload.Span);

                    await socket.SendAsync(
                        datagram.AsMemory(0, length),
                        WebSocketMessageType.Binary,
                        endOfMessage: true,
                        context.RequestAborted);

                    sent++;
                }
            }
            catch (OperationCanceledException)
            {
                // Listener went away.
            }
            catch (WebSocketException ex)
            {
                logger.LogDebug(ex, "Audio fallback stream ended");
            }
            finally
            {
                logger.LogInformation(
                    "Audio fallback sent {Sent} frames, dropped {Dropped}", sent, subscription.FramesDropped);
            }
        }
    }

    /// <summary>Token from the Authorization header, or the query string for clients that cannot set headers on an upgrade.</summary>
    private static string? ReadToken(HttpContext context)
    {
        var header = context.Request.Headers.Authorization.ToString();
        if (header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return header["Bearer ".Length..].Trim();
        }

        return context.Request.Query["token"].FirstOrDefault();
    }
}
