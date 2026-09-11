using System.Net.WebSockets;
using System.Text;
using Klippy.Server.Common;
using Klippy.Server.Features.Pairing;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;

namespace Klippy.Server.Features.Link;

public static class LinkEndpoints
{
    /// <summary>Anything larger than this is not a Klippy event, so refuse it rather than buffer it.</summary>
    private const int MaxMessageBytes = 64 * 1024;

    public static IEndpointRouteBuilder MapLinkEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/link").WithTags("Link");

        group.Map("/ws", HandleSocketAsync);

        // Lets a device confirm a discovered address really is a Klippy server, and
        // that its stored token still works, before opening a socket.
        group.MapGet("/hello", async (
            HttpContext context,
            PairingService pairing,
            ServerIdentity identity,
            CancellationToken ct) =>
        {
            var device = await pairing.AuthenticateAsync(ReadToken(context), ct);
            return device is null
                ? Results.Unauthorized()
                : Results.Ok(new
                {
                    serverId = identity.ServerId,
                    serverName = identity.Name,
                    deviceId = device.DeviceId,
                    deviceName = device.DeviceName,
                });
        });

        return routes;
    }

    private static async Task HandleSocketAsync(
        HttpContext context,
        PairingService pairing,
        LinkRegistry registry,
        EventDispatcher dispatcher,
        ServerIdentity identity,
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
            // Refuse before the upgrade so the client gets a real status code.
            context.Response.StatusCode = StatusCodes.Status401Unauthorized;
            return;
        }

        var logger = loggerFactory.CreateLogger($"Klippy.Link.{device.DeviceName}");
        using var socket = await context.WebSockets.AcceptWebSocketAsync();

        var connection = new LinkConnection(
            device.DeviceId, device.DeviceKind, device.DeviceName, socket, logger);

        await registry.AddAsync(connection);

        var presence = new DevicePresencePayload
        {
            DeviceId = device.DeviceId.ToString(),
            DeviceKind = device.DeviceKind,
            DeviceName = device.DeviceName,
        };

        try
        {
            // Tell the newcomer who it is and who else is here, before any events flow.
            connection.Enqueue(LinkEnvelope.Create(KlippyEvents.LinkWelcome, new WelcomePayload
            {
                DeviceId = device.DeviceId.ToString(),
                ServerId = identity.ServerId,
                ServerName = identity.Name,
                Peers = registry.PeersOf(device.DeviceId),
            }));

            // Sourced to the arriving device so the broadcast skips it: it already knows
            // it connected, and its welcome message listed everyone else.
            await dispatcher.DispatchAsync(
                LinkEnvelope.Create(KlippyEvents.DeviceConnected, presence, source: device.DeviceId.ToString()),
                context.RequestAborted);

            var sending = connection.RunSendLoopAsync(context.RequestAborted);
            var receiving = ReceiveLoopAsync(connection, socket, dispatcher, logger, context.RequestAborted);

            await Task.WhenAny(sending, receiving);
        }
        finally
        {
            connection.SignalClosed();
            registry.Remove(connection);
            await connection.DisposeAsync();

            // Best effort: the request is already aborting, so this gets its own token.
            await dispatcher.DispatchAsync(
                LinkEnvelope.Create(KlippyEvents.DeviceDisconnected, presence, source: device.DeviceId.ToString()),
                CancellationToken.None);
        }
    }

    private static async Task ReceiveLoopAsync(
        LinkConnection connection,
        WebSocket socket,
        EventDispatcher dispatcher,
        ILogger logger,
        CancellationToken ct)
    {
        var buffer = new byte[8 * 1024];
        var message = new MemoryStream();

        while (!ct.IsCancellationRequested && socket.State == WebSocketState.Open)
        {
            WebSocketReceiveResult result;
            try
            {
                result = await socket.ReceiveAsync(buffer, ct);
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (WebSocketException ex)
            {
                logger.LogDebug(ex, "Receive ended for {DeviceName}", connection.DeviceName);
                return;
            }

            if (result.MessageType == WebSocketMessageType.Close)
            {
                return;
            }

            message.Write(buffer, 0, result.Count);

            if (message.Length > MaxMessageBytes)
            {
                logger.LogWarning("{DeviceName} sent an oversized message; dropping the connection", connection.DeviceName);
                return;
            }

            if (!result.EndOfMessage)
            {
                continue;
            }

            var text = Encoding.UTF8.GetString(message.ToArray());
            message.SetLength(0);

            var envelope = LinkEnvelope.TryParse(text);
            if (envelope is null)
            {
                logger.LogWarning("{DeviceName} sent a message that is not an envelope", connection.DeviceName);
                continue;
            }

            // Keepalives never leave this method.
            if (envelope.Type == KlippyEvents.LinkPing)
            {
                connection.Enqueue(LinkEnvelope.Create(KlippyEvents.LinkPong));
                continue;
            }

            if (envelope.Type == KlippyEvents.LinkPong)
            {
                continue;
            }

            // The sender is whoever the token says it is, not whoever the message claims.
            await dispatcher.DispatchAsync(
                envelope with { Source = connection.DeviceId.ToString() }, ct);
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
