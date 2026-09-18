using System.Security.Claims;

namespace Klippy.Server.Features.Accounts;

/// <summary>
/// Turns an <see cref="AccountRow"/> into the cookie's claims and back. Pages and
/// endpoints read the signed-in account through the extensions here rather than
/// reaching for claim names of their own.
/// </summary>
public static class AccountPrincipal
{
    /// <summary>The cookie scheme's name. Devices do not use it — they carry bearer tokens.</summary>
    public const string Scheme = "Klippy";

    /// <summary>Role claim carried by an admin account. See <see cref="AccountRow.IsAdmin"/>.</summary>
    public const string AdminRole = "admin";

    public static ClaimsPrincipal CreateFor(AccountRow account) =>
        new(new ClaimsIdentity(
            BuildClaims(account),
            Scheme,
            ClaimTypes.Name,
            ClaimTypes.Role));

    private static IEnumerable<Claim> BuildClaims(AccountRow account)
    {
        yield return new Claim(ClaimTypes.NameIdentifier, account.UserId.ToString());
        yield return new Claim(ClaimTypes.Name, account.Username);

        if (account.IsAdmin)
        {
            yield return new Claim(ClaimTypes.Role, AdminRole);
        }
    }

    /// <summary>The signed-in account's id, or null when nobody is signed in.</summary>
    public static Guid? AccountId(this ClaimsPrincipal? principal) =>
        Guid.TryParse(principal?.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : null;

    public static string? AccountName(this ClaimsPrincipal? principal) =>
        principal?.FindFirstValue(ClaimTypes.Name);

    public static bool IsAdmin(this ClaimsPrincipal? principal) =>
        principal?.IsInRole(AdminRole) ?? false;
}
