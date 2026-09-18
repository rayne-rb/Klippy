namespace Klippy.Server.Features.Visits;

public static class VisitsRegistration
{
    public static IServiceCollection AddVisitsFeature(this IServiceCollection services)
    {
        // One instance wearing both hats: the hosted service subscribes it to the
        // registry, and the link's welcome asks the same object for a device's friends.
        services.AddSingleton<VisitNeighborhood>();
        services.AddHostedService(sp => sp.GetRequiredService<VisitNeighborhood>());
        return services;
    }
}
