using System.Net.WebSockets;
using System.Text;
using System.Threading.Channels;
using Klippy.Shared.Discovery;
using Klippy.Shared.Link;
using Klippy.Mobile.Features.Discovery;
using Klippy.Mobile.Features.Pairing;

namespace Klippy.Mobile.Features.Link;

/// <summary>
/// The phone's end of the link, and the mirror image of the Companion's KlippyLink:
/// find a server, pair if we have not already, hold a socket open, and surface what
/// arrives.
///
/// Runs one long-lived loop rather than a timer-driven state machine, so the whole
/// lifecycle reads top to bottom and reconnecting is just the loop going round again.
/// </summary>
public sealed class KlippyLinkClient(
    ServerLocator locator,
    MobilePairingClient pairing,
    PairedServerStore store,
    ManualAddressStore manualAddress,
    ILogger<KlippyLinkClient> logger) : IAsyncDisposable
{
    private static readonly TimeSpan RetryDelay = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan DiscoveryTimeout = TimeSpan.FromSeconds(10);

    /// <summary>
    /// How long a typed address gets before we settle for what multicast found.
    /// Generous enough for a relayed tailnet round trip on a link that has just woken,
    /// short enough that a stale address is not felt as a hang.
    /// </summary>
    private static readonly TimeSpan TypedAddressTimeout = TimeSpan.FromSeconds(4);

    private readonly Channel<LinkEnvelope> _outbound =
        Channel.CreateBounded<LinkEnvelope>(new BoundedChannelOptions(64)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
        });

    private CancellationTokenSource? _cts;
    private Task? _runner;

    /// <summary>An event arrived from the server.</summary>
    public event Action<LinkEnvelope>? EventReceived;

    /// <summary>The connection state changed.</summary>
    public event Action<LinkState>? StateChanged;

    /// <summary>A pairing code the user must confirm on the server.</summary>
    public event Action<string>? PairingCodeReady;

    public LinkState State { get; private set; } = LinkState.Offline;

    public string? ServerName { get; private set; }

    public void Start()
    {
        if (_runner is not null)
        {
            return;
        }

        _cts = new CancellationTokenSource();
        _runner = Task.Run(() => RunAsync(_cts.Token));
    }

    /// <summary>Queues an event for the server. Dropped silently while offline.</summary>
    public void Publish(string type, object? payload = null)
    {
        var envelope = payload is null
            ? LinkEnvelope.Create(type)
            : LinkEnvelope.Create(type, payload);

        _outbound.Writer.TryWrite(envelope);
    }

    /// <summary>The address the user typed, if any.</summary>
    public Task<string?> GetManualAddressAsync() => manualAddress.GetAsync();

    /// <summary>
    /// Records where the server is and retries at once, rather than waiting out the
    /// next retry delay.
    /// </summary>
    public async Task SetManualAddressAsync(string? address)
    {
        await manualAddress.SetAsync(address);
        await StopAsync();
        Start();
    }

    /// <summary>Forgets the pairing and starts looking for a server again.</summary>
    public async Task ForgetPairingAsync()
    {
        await store.ClearAsync();
        await StopAsync();
        Start();
    }

    private void SetState(LinkState state)
    {
        if (State == state)
        {
            return;
        }

        State = state;
        StateChanged?.Invoke(state);
    }

    private async Task RunAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var server = await EnsurePairedAsync(ct);
                if (server is null)
                {
                    SetState(LinkState.Offline);
                    await Task.Delay(RetryDelay, ct);
                    continue;
                }

                ServerName = server.Name;
                await ConnectAndPumpAsync(server, ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogWarning(ex, "Link loop stumbled; retrying");
            }

            SetState(LinkState.Offline);

            try
            {
                await Task.Delay(RetryDelay, ct);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }

        SetState(LinkState.Offline);
    }

    /// <summary>Returns a server we hold a token for, pairing first if necessary.</summary>
    private async Task<PairedServerRow?> EnsurePairedAsync(CancellationToken ct)
    {
        var stored = await store.GetAsync(ct);

        SetState(LinkState.Searching);

        var typed = await manualAddress.GetAsync(ct);
        var beacon = await LocateAsync(typed, ct);

        if (stored is not null)
        {
            // Adopt a new address for the same server rather than making the user
            // pair again because the router handed out a different lease.
            if (beacon is not null && beacon.ServerId == stored.ServerId &&
                (beacon.BaseUrl != stored.BaseUrl || beacon.WsUrl != stored.WsUrl))
            {
                await store.UpdateAddressAsync(stored.ServerId, beacon.BaseUrl, beacon.WsUrl, ct);
                stored.BaseUrl = beacon.BaseUrl;
                stored.WsUrl = beacon.WsUrl;
            }

            return stored;
        }

        if (beacon is null)
        {
            return null;
        }

        SetState(LinkState.Pairing);

        void Forward(string code) => PairingCodeReady?.Invoke(code);
        pairing.CodeReady += Forward;

        try
        {
            var result = await pairing.PairAsync(
                beacon.BaseUrl, DeviceNaming.Describe(), DeviceNaming.Platform(), ct);

            if (result is null)
            {
                return null;
            }

            var row = new PairedServerRow
            {
                ServerId = beacon.ServerId,
                Name = beacon.Name,
                BaseUrl = beacon.BaseUrl,
                WsUrl = beacon.WsUrl,
                DeviceId = result.Value.DeviceId,
                Token = result.Value.Token,
                PairedAt = DateTimeOffset.UtcNow.ToString("O"),
            };

            await store.SaveAsync(row, ct);
            return row;
        }
        finally
        {
            pairing.CodeReady -= Forward;
        }
    }

    /// <summary>
    /// Finds the server, by a typed address and by multicast at the same time.
    ///
    /// A typed address still wins whenever it answers: it is an explicit choice, and in
    /// the cases that call for one - a tailnet, mobile data, an emulator behind
    /// user-mode NAT - multicast can never succeed. But such an address is usually
    /// stale rather than wrong, the phone having come back to the Wi-Fi the server is
    /// on with the VPN off. Running the probe alongside it rather than after it means
    /// that case costs the typed address's timeout instead of that plus a whole fresh
    /// discovery window, and the fallback is already in hand the moment it is needed.
    /// </summary>
    private async Task<ServerBeacon?> LocateAsync(string? typed, CancellationToken ct)
    {
        // The ordinary case: same Wi-Fi, nothing configured.
        if (string.IsNullOrEmpty(typed))
        {
            return await locator.FindAsync(DiscoveryTimeout, ct);
        }

        using var probeCts = CancellationTokenSource.CreateLinkedTokenSource(ct);

        // Started first so it is already listening while the HTTP round trip runs.
        var probing = locator.FindAsync(DiscoveryTimeout, probeCts.Token);

        try
        {
            // Bounded here rather than inside the locator: the wait is only worth
            // cutting short because there is a probe running behind it.
            using var typedCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            typedCts.CancelAfter(TypedAddressTimeout);

            var resolved = await locator.ResolveAsync(typed, typedCts.Token);
            if (resolved is not null)
            {
                return resolved;
            }

            // ResolveAsync reports a cancelled token as "nothing there", which is the
            // right answer for its own deadline but not for the app shutting down.
            ct.ThrowIfCancellationRequested();

            logger.LogInformation(
                "Nothing answered at '{Typed}'; falling back to what multicast found", typed);

            return await probing;
        }
        finally
        {
            await probeCts.CancelAsync();

            // Let the probe unwind before its socket goes out of scope.
            await probing;
        }
    }

    private async Task ConnectAndPumpAsync(PairedServerRow server, CancellationToken ct)
    {
        SetState(LinkState.Connecting);

        using var socket = new ClientWebSocket();
        var url = new Uri($"{server.WsUrl}?token={Uri.EscapeDataString(server.Token)}");

        try
        {
            await socket.ConnectAsync(url, ct);
        }
        catch (WebSocketException ex)
        {
            // A rejected token means the pairing was revoked on the server; drop it
            // so the next loop pairs afresh instead of retrying a dead credential.
            if (ex.Message.Contains("401") || ex.Message.Contains("Unauthorized"))
            {
                logger.LogWarning("The server no longer recognises this device; unpairing");
                await store.ClearAsync(ct);
            }

            throw;
        }

        SetState(LinkState.Connected);
        logger.LogInformation("Connected to {ServerName}", server.Name);

        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct);

        var sending = SendLoopAsync(socket, linked.Token);
        var receiving = ReceiveLoopAsync(socket, linked.Token);

        await Task.WhenAny(sending, receiving);
        await linked.CancelAsync();
    }

    private async Task SendLoopAsync(ClientWebSocket socket, CancellationToken ct)
    {
        try
        {
            await foreach (var envelope in _outbound.Reader.ReadAllAsync(ct))
            {
                var bytes = Encoding.UTF8.GetBytes(envelope.ToJson());
                await socket.SendAsync(bytes, WebSocketMessageType.Text, endOfMessage: true, ct);
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or WebSocketException)
        {
            // Connection ending.
        }
    }

    private async Task ReceiveLoopAsync(ClientWebSocket socket, CancellationToken ct)
    {
        var buffer = new byte[16 * 1024];
        var message = new MemoryStream();

        try
        {
            while (!ct.IsCancellationRequested && socket.State == WebSocketState.Open)
            {
                var result = await socket.ReceiveAsync(buffer, ct);

                if (result.MessageType == WebSocketMessageType.Close)
                {
                    return;
                }

                message.Write(buffer, 0, result.Count);
                if (!result.EndOfMessage)
                {
                    continue;
                }

                var text = Encoding.UTF8.GetString(message.ToArray());
                message.SetLength(0);

                var envelope = LinkEnvelope.TryParse(text);
                if (envelope is null)
                {
                    continue;
                }

                if (envelope.Type == KlippyEvents.LinkPing)
                {
                    Publish(KlippyEvents.LinkPong);
                    continue;
                }

                if (envelope.Type == KlippyEvents.LinkPong)
                {
                    continue;
                }

                EventReceived?.Invoke(envelope);
            }
        }
        catch (Exception ex) when (ex is OperationCanceledException or WebSocketException)
        {
            // Connection ending.
        }
    }

    private async Task StopAsync()
    {
        if (_cts is null)
        {
            return;
        }

        await _cts.CancelAsync();

        if (_runner is not null)
        {
            try
            {
                await _runner;
            }
            catch (OperationCanceledException)
            {
                // Expected.
            }
        }

        _cts.Dispose();
        _cts = null;
        _runner = null;
    }

    public async ValueTask DisposeAsync() => await StopAsync();
}
