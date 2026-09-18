namespace Klippy.Mobile.Features.Clipboard;

/// <summary>
/// Images on and off the system clipboard.
///
/// MAUI's own <c>Clipboard</c> is text and nothing else, so this is the seam the
/// platform-specific half plugs into. Only Android implements it here, the same way only
/// Android implements the audio sink; everywhere else the clipboard tab quietly offers
/// text alone rather than showing a button that cannot work.
/// </summary>
public interface IClipboardImages
{
    /// <summary>The image on the clipboard as a PNG, or null when there is not one.</summary>
    Task<byte[]?> ReadPngAsync();

    /// <summary>Puts a PNG on the clipboard. Returns null on success, or a sentence saying why not.</summary>
    Task<string?> WritePngAsync(byte[] png);
}
