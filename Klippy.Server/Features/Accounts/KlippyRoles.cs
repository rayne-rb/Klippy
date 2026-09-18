namespace Klippy.Server.Features.Accounts;

/// <summary>
/// What an account is allowed to be.
///
/// Carried as the role claim on the sign-in cookie, so <c>[Authorize(Roles = ...)]</c> and
/// <c>AuthorizeView</c> work against these names directly.
/// </summary>
public static class KlippyRoles
{
    /// <summary>Sees and manages every account, every device and every clipboard on this server.</summary>
    public const string Admin = "admin";

    /// <summary>Sees their own devices and their own clipboard. The default for a new account.</summary>
    public const string User = "user";

    public static bool IsKnown(string? value) => value is Admin or User;

    /// <summary>Every role, in the order a picker should offer them.</summary>
    public static IReadOnlyList<string> All { get; } = [User, Admin];

    /// <summary>One line on what a role can do, for the screen that hands them out.</summary>
    public static string Describe(string role) => role switch
    {
        Admin => "Manages accounts, and sees every device and clipboard on this server",
        _ => "Sees their own devices and their own clipboard",
    };
}
