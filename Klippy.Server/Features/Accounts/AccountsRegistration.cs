using Microsoft.AspNetCore.Authentication.Cookies;

namespace Klippy.Server.Features.Accounts;

public static class AccountsRegistration
{
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
                options.AccessDeniedPath = "/login";
                options.ExpireTimeSpan = TimeSpan.FromDays(30);
                options.SlidingExpiration = true;

                // The server is reached over plain HTTP by IP on the LAN (see the note in
                // Program.cs), so requiring a secure cookie would lock everyone out.
                options.Cookie.SecurePolicy = CookieSecurePolicy.SameAsRequest;
                options.Cookie.SameSite = SameSiteMode.Lax;
                options.Cookie.HttpOnly = true;
            });

        services.AddAuthorization();
        services.AddCascadingAuthenticationState();

        return services;
    }
}
