using Klippy.Server.Features.Link;

namespace Klippy.Server.Features.Market;

public static class MarketRegistration
{
    public static IServiceCollection AddMarketFeature(this IServiceCollection services)
    {
        services.AddSingleton<MarketNotifier>();
        services.AddScoped<MarketRepository>();
        services.AddScoped<IKlippyEventHandler, MarketEventHandler>();
        return services;
    }
}
