using RepoDb.Attributes;

namespace Klippy.Server.Features.Accounts;

/// <summary>
/// An account with how many devices it owns, for the admin page. Not a table of its own.
/// </summary>
public sealed class AccountSummary
{
    [Map("user_id")]
    public Guid UserId { get; set; }

    [Map("username")]
    public string Username { get; set; } = string.Empty;

    [Map("role")]
    public string Role { get; set; } = KlippyRoles.User;

    /// <summary>
    /// Not a column. RepoDb only ever reads this type through a hand-written select, so
    /// an unmapped extra here costs nothing — unlike on a row it also inserts.
    /// </summary>
    public bool IsAdmin => Role == KlippyRoles.Admin;

    [Map("created_at")]
    public DateTimeOffset CreatedAt { get; set; }

    [Map("device_count")]
    public int DeviceCount { get; set; }
}
