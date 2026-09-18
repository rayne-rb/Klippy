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

    /// <summary>The admin role's name, kept here for the attributes that ask for it by string.</summary>
    public const string AdminRole = KlippyRoles.Admin;

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

        // Always, not only for an admin: a page that wants to know what someone is can
        // then ask, rather than inferring "not an admin" from the absence of a claim.
        yield return new Claim(ClaimTypes.Role, account.Role);
    }

    /// <summary>The signed-in account's id, or null when nobody is signed in.</summary>
    public static Guid? AccountId(this ClaimsPrincipal? principal) =>
        Guid.TryParse(principal?.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : null;

    public static string? AccountName(this ClaimsPrincipal? principal) =>
        principal?.FindFirstValue(ClaimTypes.Name);

    public static bool IsAdmin(this ClaimsPrincipal? principal) =>
        principal?.IsInRole(KlippyRoles.Admin) ?? false;

    /// <summary>The signed-in account's role, or null when nobody is signed in.</summary>
    public static string? Role(this ClaimsPrincipal? principal) =>
        principal?.FindFirstValue(ClaimTypes.Role);
}
