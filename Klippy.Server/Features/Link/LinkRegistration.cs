namespace Klippy.Server.Features.Link;

public static class LinkRegistration
{
    public static IServiceCollection AddLinkFeature(this IServiceCollection services)
    {
        services.AddSingleton<LinkRegistry>();
        services.AddSingleton<EventDispatcher>();
        services.AddSingleton<IEventPublisher>(sp => sp.GetRequiredService<EventDispatcher>());
        services.AddScoped<LinkEventRepository>();
        services.AddHostedService<RevokedDeviceDisconnector>();
        return services;
    }
}
