using Klippy.Server.Features.Link;

namespace Klippy.Server.Features.Clipboard;

public static class ClipboardRegistration
{
    public static IServiceCollection AddClipboardFeature(this IServiceCollection services)
    {
        services.AddSingleton<ClipboardSessions>();
        services.AddSingleton<ClipboardNotifier>();
        services.AddScoped<ClipboardRepository>();
        services.AddScoped<ClipboardService>();
        services.AddScoped<IKlippyEventHandler, ClipboardEventHandler>();
        return services;
    }
}
