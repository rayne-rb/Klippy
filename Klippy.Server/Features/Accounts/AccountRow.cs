using RepoDb.Attributes;

namespace Klippy.Server.Features.Accounts;

/// <summary>Row in <c>users</c>. Owned by the accounts slice; nothing else writes it.</summary>
[Map("users")]
public sealed class AccountRow
{
    [Primary]
    [Map("user_id")]
    public Guid UserId { get; set; }

    /// <summary>Stored already lowercased, so sign-in can compare without a function index.</summary>
    [Map("username")]
    public string Username { get; set; } = string.Empty;

    [Map("password_hash")]
    public string PasswordHash { get; set; } = string.Empty;

    [Map("is_admin")]
    public bool IsAdmin { get; set; }

    [Map("created_at")]
    public DateTimeOffset CreatedAt { get; set; }
}
