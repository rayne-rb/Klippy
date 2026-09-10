using Android.App;
using Android.Content;
using Android.OS;
using AndroidX.Core.App;

namespace Klippy.Mobile.Platforms.Android;

/// <summary>
/// Keeps the process alive while audio is playing.
///
/// Without this Android stops the app seconds after the screen locks, and for a music
/// stream a locked screen is the normal case, not an edge one. The notification is not
/// decoration either: a foreground service that cannot show one is killed.
///
/// <para><b>Unverified.</b> Compile-checked only; there is no device attached to this
/// machine.</para>
/// </summary>
[Service(
    Exported = false,
    ForegroundServiceType = global::Android.Content.PM.ForegroundService.TypeMediaPlayback)]
public sealed class AudioCastForegroundService : Service
{
    private const string ChannelId = "klippy.audiocast";
    private const int NotificationId = 4711;

    /// <summary>Starts the service, so playback survives the screen locking.</summary>
    public static void Start(string sourceName)
    {
        var context = global::Android.App.Application.Context;
        var intent = new Intent(context, typeof(AudioCastForegroundService));
        intent.PutExtra("source", sourceName);

        if (OperatingSystem.IsAndroidVersionAtLeast(26))
        {
            context.StartForegroundService(intent);
        }
        else
        {
            context.StartService(intent);
        }
    }

    public static void Stop()
    {
        var context = global::Android.App.Application.Context;
        context.StopService(new Intent(context, typeof(AudioCastForegroundService)));
    }

    public override IBinder? OnBind(Intent? intent) => null;

    public override StartCommandResult OnStartCommand(Intent? intent, StartCommandFlags flags, int startId)
    {
        var source = intent?.GetStringExtra("source") ?? "your PC";
        var notification = Build(source);

        if (OperatingSystem.IsAndroidVersionAtLeast(29))
        {
            StartForeground(
                NotificationId,
                notification,
                global::Android.Content.PM.ForegroundService.TypeMediaPlayback);
        }
        else
        {
            StartForeground(NotificationId, notification);
        }

        // Not sticky: if Android kills us the stream is gone anyway, and silently
        // restarting a capture the user is no longer listening to would be worse than
        // stopping.
        return StartCommandResult.NotSticky;
    }

    private Notification Build(string source)
    {
        if (OperatingSystem.IsAndroidVersionAtLeast(26))
        {
            // Low importance: this is a status notification, not something to interrupt
            // for, and it must never make a sound over the audio it is reporting on.
            var channel = new NotificationChannel(ChannelId, "Audio cast", NotificationImportance.Low)
            {
                Description = "Shown while Klippy is playing audio from your PC.",
            };

            channel.SetShowBadge(false);
            (GetSystemService(NotificationService) as NotificationManager)?.CreateNotificationChannel(channel);
        }

        var notification = new NotificationCompat.Builder(this, ChannelId)
            .SetContentTitle("Klippy audio")!
            .SetContentText($"Playing from {source}")!
            .SetSmallIcon(global::Android.Resource.Drawable.IcMediaPlay)!
            .SetOngoing(true)!
            .SetSilent(true)!
            .SetPriority((int)NotificationPriority.Low)!
            .Build();

        return notification
               ?? throw new InvalidOperationException("Could not build the audio cast notification.");
    }
}
