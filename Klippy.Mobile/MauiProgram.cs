using Klippy.Mobile.Data;
using Klippy.Mobile.Features.AudioCast;
using Klippy.Mobile.Features.Clipboard;
using Klippy.Mobile.Features.Discovery;
using Klippy.Mobile.Features.Link;
using Klippy.Mobile.Features.Pairing;
using Klippy.Mobile.Features.Pet;
using Microsoft.Extensions.Logging;

namespace Klippy.Mobile;

public static class MauiProgram
{
	public static MauiApp CreateMauiApp()
	{
		var builder = MauiApp.CreateBuilder();
		builder
			.UseMauiApp<App>()
			.ConfigureFonts(fonts =>
			{
				fonts.AddFont("OpenSans-Regular.ttf", "OpenSansRegular");
				fonts.AddFont("OpenSans-Semibold.ttf", "OpenSansSemibold");
			});

		// Shared plumbing.
		builder.Services.AddSingleton<MobileDatabase>();

		// Feature slices.
		builder.Services.AddSingleton<PairedServerStore>();
		builder.Services.AddSingleton<ServerLocator>();
		builder.Services.AddSingleton<ManualAddressStore>();
		builder.Services.AddSingleton<MobilePairingClient>();
		builder.Services.AddSingleton<KlippyLinkClient>();
		builder.Services.AddSingleton<PetPage>();

		builder.Services.AddSingleton<ClipboardSettings>();
		builder.Services.AddSingleton<ClipboardStore>();
		builder.Services.AddSingleton<ClipboardApiClient>();
		builder.Services.AddTransient<ClipboardPage>();

#if ANDROID
		// The audio sink is the one part of the cast that is platform-specific; the client
		// above it only knows IAudioSink.
		builder.Services.AddSingleton<IAudioSink, Platforms.Android.AudioTrackSink>();
		builder.Services.AddSingleton<AudioCastClient>();

		// Likewise images on the clipboard: MAUI's own Clipboard is text and nothing else.
		// Registered as the only implementation of a collection the page resolves, so a
		// platform without one still gets a working text-only tab.
		builder.Services.AddSingleton<IClipboardImages, Platforms.Android.AndroidClipboardImages>();
#endif

#if DEBUG
		builder.Logging.AddDebug();
#endif

		return builder.Build();
	}
}
