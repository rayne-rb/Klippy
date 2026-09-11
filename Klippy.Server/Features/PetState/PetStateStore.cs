using Klippy.Shared.Link.Payloads;

namespace Klippy.Server.Features.PetState;

/// <summary>
/// The server's own picture of how the pet is doing, kept current by watching the
/// event stream. Means a phone that has just connected can show something immediately
/// instead of waiting for the Companion's next update, and that the answer survives
/// the Companion being closed.
/// </summary>
public sealed class PetStateStore
{
    private readonly Lock _gate = new();
    private PetStatsPayload? _stats;
    private DateTimeOffset? _updatedAt;

    /// <summary>Raised on every change, so the dashboard can re-render.</summary>
    public event Action? Changed;

    public (PetStatsPayload? Stats, DateTimeOffset? UpdatedAt) Current
    {
        get
        {
            lock (_gate)
            {
                return (_stats, _updatedAt);
            }
        }
    }

    public void Update(PetStatsPayload stats)
    {
        lock (_gate)
        {
            _stats = stats;
            _updatedAt = DateTimeOffset.UtcNow;
        }

        Changed?.Invoke();
    }

    public void MarkDead()
    {
        lock (_gate)
        {
            if (_stats is null)
            {
                return;
            }

            _stats = _stats with { IsDead = true, Health = 0 };
            _updatedAt = DateTimeOffset.UtcNow;
        }

        Changed?.Invoke();
    }

    public void MarkRevived()
    {
        lock (_gate)
        {
            if (_stats is null)
            {
                return;
            }

            _stats = _stats with { IsDead = false };
            _updatedAt = DateTimeOffset.UtcNow;
        }

        Changed?.Invoke();
    }
}
