namespace Klippy.Server.Features.Pairing;

public static class PairingRegistration
{
    public static IServiceCollection AddPairingFeature(this IServiceCollection services)
    {
        services.AddSingleton<ApprovedTokenCache>();
        services.AddSingleton<PairingNotifier>();
        services.AddScoped<PairingRepository>();
        services.AddScoped<PairingService>();
        return services;
    }
}
