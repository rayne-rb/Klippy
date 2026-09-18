using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace Klippy.Server.Features.Accounts;

public static class AccountsRegistration
{
    /// <summary>
    /// How stale a cookie's copy of the role may get before it is checked against the
    /// database again.
    ///
    /// The cookie carries the role, so a demoted admin would otherwise stay an admin until
    /// they signed out — as would a deleted account. Checking on every request would mean
    /// a query per static asset, which is why this is a window rather than always.
    /// </summary>
    private static readonly TimeSpan RevalidateAfter = TimeSpan.FromMinutes(1);

    /// <summary>When the role on this cookie was last confirmed. Stored in the ticket.</summary>
    private const string CheckedAtKey = "role_checked_at";

    public static IServiceCollection AddAccountsFeature(this IServiceCollection services)
    {
        services.AddScoped<AccountRepository>();
        services.AddScoped<AccountService>();

        services.AddAuthentication(AccountPrincipal.Scheme)
            .AddCookie(AccountPrincipal.Scheme, options =>
            {
                options.Cookie.Name = "klippy_auth";
                options.LoginPath = "/login";
                options.LogoutPath = "/logout";

                // Not the sign-in form: being refused is not the same as not being signed
                // in, and sending someone to sign in again as the same person they already
                // are is a loop with a form in the middle of it.
                options.AccessDeniedPath = "/denied";
                options.ExpireTimeSpan = TimeSpan.FromDays(30);
                options.SlidingExpiration = true;

                // The server is reached over plain HTTP by IP on the LAN (see the note in
                // Program.cs), so requiring a secure cookie would lock everyone out.
                options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
                options.Cookie.SameSite = SameSiteMode.Lax;
                options.Cookie.HttpOnly = true;

                options.Events.OnSigningIn = context =>
                {
                    Stamp(context.Properties);
                    return Task.CompletedTask;
                };

                options.Events.OnValidatePrincipal = ValidateAsync;
            });

        services.AddAuthorization();
        services.AddCascadingAuthenticationState();

        return services;
    }

    /// <summary>
    /// Re-reads the account behind a cookie, now and then, so that changing what someone
    /// is takes effect without waiting for them to sign out.
    ///
    /// An interactive circuit reads its claims once when it opens, so a demotion lands on
    /// the next full page load rather than the next click. That is the cost of the render
    /// mode, not of this.
    /// </summary>
    private static async Task ValidateAsync(CookieValidatePrincipalContext context)
    {
        if (!IsStale(context.Properties))
        {
            return;
        }

        var accounts = context.HttpContext.RequestServices.GetRequiredService<AccountService>();

        var account = context.Principal.AccountId() is { } userId
            ? await accounts.FindAsync(userId, context.HttpContext.RequestAborted)
            : null;

        if (account is null)
        {
            // The account was removed while this cookie was still out there.
            context.RejectPrincipal();
            await context.HttpContext.SignOutAsync(AccountPrincipal.Scheme);
            return;
        }

        if (account.Role != context.Principal.Role())
        {
            // Replaced rather than rejected: their role changed, they did not stop being
            // themselves, and there is no reason to make them sign in again for it.
            context.ReplacePrincipal(AccountPrincipal.CreateFor(account));
        }

        Stamp(context.Properties);
        context.ShouldRenew = true;
    }

    private static bool IsStale(AuthenticationProperties properties) =>
        !properties.Items.TryGetValue(CheckedAtKey, out var value)
        || !DateTimeOffset.TryParse(value, out var checkedAt)
        || DateTimeOffset.UtcNow - checkedAt >= RevalidateAfter;

    private static void Stamp(AuthenticationProperties properties) =>
        properties.Items[CheckedAtKey] = DateTimeOffset.UtcNow.ToString("o");
}
