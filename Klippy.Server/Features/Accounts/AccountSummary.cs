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

    [Map("is_admin")]
    public bool IsAdmin { get; set; }

    [Map("created_at")]
    public DateTimeOffset CreatedAt { get; set; }

    [Map("device_count")]
    public int DeviceCount { get; set; }
}
