using Android.Content;
using Android.Graphics;
using Klippy.Mobile.Features.Clipboard;
using Application = Android.App.Application;

namespace Klippy.Mobile.Platforms.Android;

/// <summary>
/// The Android half of clipboard images.
///
/// An image on the Android clipboard is not bytes but a <c>content://</c> URI pointing at
/// whichever application put it there, so reading one means asking that application's
/// content provider for a stream, and writing one means publishing the file through a
/// provider of our own. MAUI already declares a FileProvider for sharing, which is the one
/// used here rather than adding a second.
///
/// A caveat that belongs on the screen, not just in a comment: since Android 10 an
/// application may only read the clipboard while it holds focus. This cannot watch the
/// clipboard in the background, and no amount of service work changes that — which is why
/// the tab has a button to share what you just copied rather than pretending to watch.
/// </summary>
public sealed class AndroidClipboardImages : IClipboardImages
{
    /// <summary>Where a picture is staged before being handed to the provider.</summary>
    private const string ScratchName = "klippy-clipboard.png";

    public Task<byte[]?> ReadPngAsync()
    {
        var context = Application.Context;

        if (context.GetSystemService(Context.ClipboardService) is not ClipboardManager manager)
        {
            return Task.FromResult<byte[]?>(null);
        }

        var uri = manager.PrimaryClip is { ItemCount: > 0 } clip
            ? clip.GetItemAt(0)?.Uri
            : null;

        if (uri is null)
        {
            return Task.FromResult<byte[]?>(null);
        }

        try
        {
            using var stream = context.ContentResolver?.OpenInputStream(uri);
            if (stream is null)
            {
                return Task.FromResult<byte[]?>(null);
            }

            using var bitmap = BitmapFactory.DecodeStream(stream);
            if (bitmap is null)
            {
                return Task.FromResult<byte[]?>(null);
            }

            // Re-encoded rather than passed through: whatever the source offered could be
            // a JPEG, a WebP or a screenshot in some vendor format, and everything
            // downstream is promised a PNG.
            using var encoded = new MemoryStream();
            bitmap.Compress(Bitmap.CompressFormat.Png!, 100, encoded);
            return Task.FromResult<byte[]?>(encoded.ToArray());
        }
        catch (Exception ex) when (ex is IOException or Java.Lang.SecurityException)
        {
            // The owning application may have gone, or may not let us read it.
            return Task.FromResult<byte[]?>(null);
        }
    }

    public async Task<string?> WritePngAsync(byte[] png)
    {
        var context = Application.Context;

        if (context.GetSystemService(Context.ClipboardService) is not ClipboardManager manager)
        {
            return "This phone has no clipboard service.";
        }

        try
        {
            // The cache directory, because that is what MAUI's FileProvider is configured
            // to serve. A file anywhere else would be published as a URI nothing can open.
            var path = System.IO.Path.Combine(FileSystem.CacheDirectory, ScratchName);
            await File.WriteAllBytesAsync(path, png);

            var uri = AndroidX.Core.Content.FileProvider.GetUriForFile(
                context, $"{context.PackageName}.fileProvider", new Java.IO.File(path));

            if (uri is null)
            {
                return "Could not hand the image to the clipboard.";
            }

            var clip = ClipData.NewUri(context.ContentResolver, "Klippy", uri);
            manager.PrimaryClip = clip;

            // Without this, whichever application pastes it is refused at the provider.
            context.GrantUriPermission(
                "android", uri, ActivityFlags.GrantReadUriPermission);

            return null;
        }
        catch (Exception ex) when (ex is IOException or Java.Lang.SecurityException
                                       or Java.Lang.IllegalArgumentException)
        {
            return "Could not put the image on the clipboard.";
        }
    }
}
