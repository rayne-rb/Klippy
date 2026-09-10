namespace Klippy.Server.Features.Discovery;

public static class DiscoveryRegistration
{
    public static IServiceCollection AddDiscoveryFeature(this IServiceCollection services)
    {
        services.AddHostedService<DiscoveryBeaconService>();
        return services;
    }
}
