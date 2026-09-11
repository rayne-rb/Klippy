using System.Collections.Concurrent;

namespace Klippy.Server.Features.Pairing;

/// <summary>
/// Holds a freshly minted token between the human clicking Approve and the device's
/// next poll picking it up. Deliberately in memory and single-use: the plaintext token
/// never reaches the database, only its hash does.
///
/// If the server restarts in that window the device sees "approved, no token" and
/// starts pairing over, which is the right outcome for a lost secret.
/// </summary>
public sealed class ApprovedTokenCache
{
    private static readonly TimeSpan Ttl = TimeSpan.FromMinutes(10);

    private readonly ConcurrentDictionary<Guid, (string Token, DateTimeOffset ExpiresAt)> _tokens = new();

    public void Store(Guid requestId, string token) =>
        _tokens[requestId] = (token, DateTimeOffset.UtcNow.Add(Ttl));

    /// <summary>Returns the token once, then forgets it.</summary>
    public string? Collect(Guid requestId)
    {
        Prune();

        if (!_tokens.TryRemove(requestId, out var entry))
        {
            return null;
        }

        return entry.ExpiresAt > DateTimeOffset.UtcNow ? entry.Token : null;
    }

    private void Prune()
    {
        var now = DateTimeOffset.UtcNow;
        foreach (var (key, value) in _tokens)
        {
            if (value.ExpiresAt <= now)
            {
                _tokens.TryRemove(key, out _);
            }
        }
    }
}
