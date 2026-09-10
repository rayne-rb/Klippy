using System.Net;
using System.Security.Cryptography;
using Klippy.Shared.Audio;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// One listener's cast: who asked, what they are listening to, and where to send it.
///
/// Mutable state is only ever changed through <see cref="AudioCastSessions"/>, which
/// holds the lock.
/// </summary>
public sealed class AudioCastSession
{
    public required Guid DeviceId { get; init; }

    public required string DeviceName { get; init; }

    /// <summary>The ephemeral secret a hello has to carry. Never broadcast.</summary>
    public required string StreamKey { get; init; }

    public required IAudioSubscription Subscription { get; init; }

    /// <summary>The output being captured, as the catalog names it. Null means the platform default.</summary>
    public required string? OutputDeviceId { get; init; }

    public required string OutputName { get; init; }

    /// <summary>Learned from the hello's source address, not configured. Null until the first one arrives.</summary>
    public IPEndPoint? Endpoint { get; internal set; }

    public long LastHelloTicks { get; internal set; }

    /// <summary>Cancels this listener's send loop. Owned by the UDP server.</summary>
    public CancellationTokenSource? Sender { get; internal set; }

    public bool IsReceiving => Endpoint is not null;

    public int Channels => Subscription.Format.Channels;
}

/// <summary>
/// Who is casting right now. In memory only, like <c>PetStateStore</c> — a cast does not
/// outlive the process that is capturing for it, so there is nothing to migrate.
/// </summary>
public sealed class AudioCastSessions(ILogger<AudioCastSessions> logger)
{
    private readonly Lock _gate = new();
    private readonly Dictionary<Guid, AudioCastSession> _byDevice = [];
    private readonly Dictionary<string, AudioCastSession> _byKey = [];

    /// <summary>Raised whenever the cast set changes, for the dashboard and for audio.cast.state.</summary>
    public event Action? Changed;

    public IReadOnlyList<AudioCastSession> All
    {
        get
        {
            lock (_gate)
            {
                return _byDevice.Values.ToList();
            }
        }
    }

    public bool Any
    {
        get
        {
            lock (_gate)
            {
                return _byDevice.Count > 0;
            }
        }
    }

    /// <summary>
    /// Registers a cast and mints its key.
    ///
    /// A device asking again replaces its previous cast rather than doubling up, which
    /// is what happens in practice when a phone's socket dies without a close frame and
    /// it simply asks again.
    /// </summary>
    public AudioCastSession Create(
        Guid deviceId,
        string deviceName,
        IAudioSubscription subscription,
        string? outputDeviceId,
        string outputName)
    {
        var session = new AudioCastSession
        {
            DeviceId = deviceId,
            DeviceName = deviceName,
            StreamKey = Convert.ToBase64String(RandomNumberGenerator.GetBytes(AudioCastTransport.StreamKeyBytes)),
            Subscription = subscription,
            OutputDeviceId = outputDeviceId,
            OutputName = outputName,
            LastHelloTicks = Environment.TickCount64,
        };

        AudioCastSession? replaced;

        lock (_gate)
        {
            _byDevice.Remove(deviceId, out replaced);
            if (replaced is not null)
            {
                _byKey.Remove(replaced.StreamKey);
            }

            _byDevice[deviceId] = session;
            _byKey[session.StreamKey] = session;
        }

        if (replaced is not null)
        {
            logger.LogInformation("Replacing the existing cast for '{Device}'", replaced.DeviceName);
            _ = RetireAsync(replaced);
        }

        Changed?.Invoke();
        return session;
    }

    /// <summary>
    /// Matches a hello's key and records where it came from.
    ///
    /// The endpoint is taken from the datagram rather than anything the listener claims,
    /// so there is no address to configure and nothing to correct when the phone moves
    /// to a different network.
    /// </summary>
    public AudioCastSession? Claim(string streamKey, IPEndPoint endpoint)
    {
        AudioCastSession? session;
        var firstContact = false;

        lock (_gate)
        {
            if (!_byKey.TryGetValue(streamKey, out session))
            {
                return null;
            }

            session.LastHelloTicks = Environment.TickCount64;

            if (!Equals(session.Endpoint, endpoint))
            {
                firstContact = session.Endpoint is null;
                session.Endpoint = endpoint;
            }
        }

        if (firstContact)
        {
            logger.LogInformation("'{Device}' is receiving audio at {Endpoint}", session.DeviceName, endpoint);
            Changed?.Invoke();
        }

        return session;
    }

    public AudioCastSession? Find(Guid deviceId)
    {
        lock (_gate)
        {
            return _byDevice.GetValueOrDefault(deviceId);
        }
    }

    /// <summary>Ends a device's cast, if it has one. Returns false when there was nothing to stop.</summary>
    public async Task<bool> StopAsync(Guid deviceId)
    {
        AudioCastSession? session;

        lock (_gate)
        {
            if (!_byDevice.Remove(deviceId, out session))
            {
                return false;
            }

            _byKey.Remove(session.StreamKey);
        }

        logger.LogInformation("Stopped casting to '{Device}'", session.DeviceName);
        await RetireAsync(session);
        Changed?.Invoke();

        return true;
    }

    /// <summary>
    /// Drops listeners that have stopped saying hello. Without this, a phone that goes
    /// out of range leaves the capture running forever.
    /// </summary>
    public async Task<int> SweepAsync()
    {
        List<AudioCastSession> expired = [];
        var now = Environment.TickCount64;

        lock (_gate)
        {
            foreach (var session in _byDevice.Values.ToList())
            {
                if (now - session.LastHelloTicks < AudioCastTransport.HelloTimeout.TotalMilliseconds)
                {
                    continue;
                }

                _byDevice.Remove(session.DeviceId);
                _byKey.Remove(session.StreamKey);
                expired.Add(session);
            }
        }

        foreach (var session in expired)
        {
            logger.LogInformation(
                "'{Device}' stopped saying hello; ending its cast", session.DeviceName);
            await RetireAsync(session);
        }

        if (expired.Count > 0)
        {
            Changed?.Invoke();
        }

        return expired.Count;
    }

    public async Task StopAllAsync()
    {
        List<AudioCastSession> sessions;

        lock (_gate)
        {
            sessions = _byDevice.Values.ToList();
            _byDevice.Clear();
            _byKey.Clear();
        }

        foreach (var session in sessions)
        {
            await RetireAsync(session);
        }

        if (sessions.Count > 0)
        {
            Changed?.Invoke();
        }
    }

    /// <summary>The public view: who is listening, with no keys in it.</summary>
    public AudioCastStatePayload Snapshot()
    {
        var sessions = All;
        var first = sessions.FirstOrDefault();

        return new AudioCastStatePayload
        {
            IsCasting = sessions.Count > 0,
            DeviceId = first?.OutputDeviceId,
            DeviceName = first?.OutputName,
            Listeners = sessions
                .Select(s => new AudioCastListener
                {
                    DeviceId = s.DeviceId.ToString(),
                    DeviceName = s.DeviceName,
                    IsReceiving = s.IsReceiving,
                    Channels = s.Channels,
                })
                .ToList(),
        };
    }

    private static async Task RetireAsync(AudioCastSession session)
    {
        if (session.Sender is { } sender)
        {
            await sender.CancelAsync();
            sender.Dispose();
            session.Sender = null;
        }

        // Releases this listener's share of the capture; the last one out stops it.
        await session.Subscription.DisposeAsync();
    }
}
