using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Identity;
using Npgsql;

namespace Klippy.Server.Features.Accounts;

/// <summary>
/// The account rules: who exists, what a password has to look like, and which devices
/// belong to whom.
///
/// Passwords go through <see cref="PasswordHasher{TUser}"/>, which ships in the
/// ASP.NET Core shared framework — it is the hasher on its own, with none of Identity's
/// stores or Entity Framework behind it, so it costs no package and breaks no rule about
/// how this solution reaches a database.
/// </summary>
public sealed partial class AccountService(
    AccountRepository repository,
    ILogger<AccountService> logger)
{
    public const int MinimumPasswordLength = 8;
    private const int MaximumUsernameLength = 32;
    private const int MinimumUsernameLength = 3;

    /// <summary>
    /// Deliberately strict: a username is an identifier, not a display name, and it is
    /// folded to lowercase so "Tulonga" and "tulonga" cannot become two accounts.
    /// </summary>
    [GeneratedRegex("^[a-z0-9][a-z0-9._-]*$")]
    private static partial Regex UsernamePattern();

    private static readonly PasswordHasher<AccountRow> Hasher = new();

    public Task<bool> AnyAsync(CancellationToken ct) => repository.AnyAsync(ct);

    public Task<IReadOnlyList<AccountRow>> GetAllAsync(CancellationToken ct) =>
        repository.GetAllAsync(ct);

    public Task<AccountRow?> FindAsync(Guid userId, CancellationToken ct) =>
        repository.FindAsync(userId, ct);

    public Task<AccountRow?> FindFirstAdminAsync(CancellationToken ct) =>
        repository.FindFirstAdminAsync(ct);

    public Task<IReadOnlyList<AccountSummary>> GetSummariesAsync(CancellationToken ct) =>
        repository.GetSummariesAsync(ct);

    /// <summary>
    /// Creates an account, or says in one sentence why it could not. Returns the error
    /// rather than throwing: every caller is a form that has to put it on the screen.
    /// </summary>
    public async Task<(AccountRow? Account, string? Error)> CreateAsync(
        string? username, string? password, bool isAdmin, CancellationToken ct)
    {
        var name = (username ?? string.Empty).Trim().ToLowerInvariant();

        if (name.Length is < MinimumUsernameLength or > MaximumUsernameLength)
        {
            return (null, $"A username is between {MinimumUsernameLength} and {MaximumUsernameLength} characters.");
        }

        if (!UsernamePattern().IsMatch(name))
        {
            return (null, "A username can hold lowercase letters, digits, dots, dashes and underscores.");
        }

        if ((password ?? string.Empty).Length < MinimumPasswordLength)
        {
            return (null, $"A password needs at least {MinimumPasswordLength} characters.");
        }

        var row = new AccountRow
        {
            UserId = Guid.NewGuid(),
            Username = name,
            IsAdmin = isAdmin,
            CreatedAt = DateTimeOffset.UtcNow,
        };
        row.PasswordHash = Hasher.HashPassword(row, password!);

        try
        {
            await repository.InsertAsync(row, ct);
        }
        catch (PostgresException ex) when (ex.SqlState == PostgresErrorCodes.UniqueViolation)
        {
            // Caught rather than pre-checked: two people submitting the same new name at
            // once would both pass a prior existence check.
            return (null, $"There is already an account called '{name}'.");
        }

        logger.LogInformation("Created account '{Username}'{Admin}", name, isAdmin ? " (admin)" : string.Empty);
        return (row, null);
    }

    /// <summary>
    /// Resolves a username and password to an account, or null. Says nothing about which
    /// half was wrong, to the caller or the log.
    /// </summary>
    public async Task<AccountRow?> VerifyAsync(string? username, string? password, CancellationToken ct)
    {
        var name = (username ?? string.Empty).Trim().ToLowerInvariant();
        if (name.Length == 0 || string.IsNullOrEmpty(password))
        {
            return null;
        }

        var account = await repository.FindByUsernameAsync(name, ct);
        if (account is null)
        {
            return null;
        }

        var result = Hasher.VerifyHashedPassword(account, account.PasswordHash, password);

        if (result == PasswordVerificationResult.SuccessRehashNeeded)
        {
            // The hasher's own format moved on. Re-store it now, while the plaintext is
            // in hand, rather than leaving the account on the old parameters forever.
            await repository.SetPasswordAsync(account.UserId, Hasher.HashPassword(account, password), ct);
            return account;
        }

        return result == PasswordVerificationResult.Success ? account : null;
    }

    public async Task<string?> SetPasswordAsync(Guid userId, string? password, CancellationToken ct)
    {
        if ((password ?? string.Empty).Length < MinimumPasswordLength)
        {
            return $"A password needs at least {MinimumPasswordLength} characters.";
        }

        var account = await repository.FindAsync(userId, ct);
        if (account is null)
        {
            return "That account is gone.";
        }

        await repository.SetPasswordAsync(userId, Hasher.HashPassword(account, password!), ct);
        return null;
    }

    /// <summary>
    /// Removes an account. Refuses to remove the last admin: an installation with no
    /// admin has no way to make one, short of editing the database by hand.
    /// </summary>
    public async Task<string?> DeleteAsync(Guid userId, CancellationToken ct)
    {
        var accounts = await repository.GetAllAsync(ct);
        var target = accounts.FirstOrDefault(a => a.UserId == userId);

        if (target is null)
        {
            return null;
        }

        if (target.IsAdmin && accounts.Count(a => a.IsAdmin) == 1)
        {
            return "That is the only admin account, so it cannot be removed.";
        }

        await repository.DeleteAsync(userId, ct);
        logger.LogInformation("Removed account '{Username}'", target.Username);
        return null;
    }

    public Task AssignDeviceAsync(Guid deviceId, Guid ownerUserId, CancellationToken ct) =>
        repository.AssignDeviceAsync(deviceId, ownerUserId, ct);

    public Task ReleaseDeviceAsync(Guid deviceId, CancellationToken ct) =>
        repository.ReleaseDeviceAsync(deviceId, ct);

    public Task<int> CountUnownedDevicesAsync(CancellationToken ct) =>
        repository.CountUnownedDevicesAsync(ct);

    public Task<int> ClaimUnownedDevicesAsync(Guid ownerUserId, CancellationToken ct) =>
        repository.ClaimUnownedDevicesAsync(ownerUserId, ct);
}
