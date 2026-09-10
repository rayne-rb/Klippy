using Klippy.Server.Features.Link;

namespace Klippy.Server.Features.AudioCast;

public static class AudioCastRegistration
{
    public static IServiceCollection AddAudioCastFeature(this IServiceCollection services)
    {
        services.AddSingleton<OpusEncoderPool>();
        services.AddSingleton<AudioBroadcaster>();
        services.AddSingleton<AudioCastSessions>();
        services.AddSingleton<AudioCastPreferences>();

        // Registered twice on purpose: the hosted service owns the socket, and the event
        // handler needs the same instance to read the port it actually bound.
        services.AddSingleton<AudioCastUdpServer>();
        services.AddHostedService(sp => sp.GetRequiredService<AudioCastUdpServer>());

        services.AddHostedService<AudioCastStateBroadcaster>();
        services.AddScoped<IKlippyEventHandler, AudioCastEventHandler>();

        // Capture is per-platform. Both are registered where they can run and neither is
        // where it cannot, so AudioBroadcaster just takes the first that says it is
        // supported.
        if (OperatingSystem.IsLinux())
        {
            services.AddSingleton<IAudioSourceCatalog, PulseAudioSourceCatalog>();
            services.AddSingleton<IAudioCaptureSourceFactory, ParecCaptureSourceFactory>();
        }
        else if (OperatingSystem.IsWindows())
        {
            services.AddSingleton<IAudioSourceCatalog, WasapiSourceCatalog>();
            services.AddSingleton<IAudioCaptureSourceFactory, WasapiCaptureSourceFactory>();
        }

        return services;
    }
}
