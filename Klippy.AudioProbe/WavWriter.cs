using System.Buffers.Binary;
using System.Runtime.InteropServices;

namespace Klippy.AudioProbe;

/// <summary>
/// Writes float32 PCM to a WAV file, patching the two length fields on close.
///
/// The format tag is 3 (<c>WAVE_FORMAT_IEEE_FLOAT</c>), not the 1 that most examples
/// use. That is correct here and it is also a trap: tools that only understand integer
/// PCM reject the result — Python's stdlib <c>wave</c> raises
/// "unknown format: 3" — which looks exactly like a broken capture and is not one.
/// Play it back with something float-aware (pw-play, paplay, VLC, Audacity).
/// </summary>
internal sealed class WavWriter : IAsyncDisposable
{
    private const int FormatIeeeFloat = 3;
    private const int HeaderBytes = 44;

    private readonly FileStream _file;
    private readonly int _channels;
    private readonly int _sampleRate;
    private long _dataBytes;

    private WavWriter(FileStream file, int channels, int sampleRate)
    {
        _file = file;
        _channels = channels;
        _sampleRate = sampleRate;
    }

    public long DataBytes => _dataBytes;

    public static async Task<WavWriter> CreateAsync(string path, int channels, int sampleRate)
    {
        var file = new FileStream(path, FileMode.Create, FileAccess.Write, FileShare.None);
        var writer = new WavWriter(file, channels, sampleRate);

        // Placeholder; rewritten with real sizes on dispose.
        await file.WriteAsync(new byte[HeaderBytes]);

        return writer;
    }

    /// <summary>
    /// Deliberately synchronous: writing a reinterpreted span costs no allocation,
    /// where the async overload would force a copy to reach a <see cref="Memory{T}"/>.
    /// This is a buffered local file, so there is nothing to wait for.
    /// </summary>
    public void Write(ReadOnlySpan<float> samples)
    {
        var bytes = MemoryMarshal.AsBytes(samples);
        _file.Write(bytes);
        _dataBytes += bytes.Length;
    }

    public async ValueTask DisposeAsync()
    {
        var header = new byte[HeaderBytes];
        var bitsPerSample = sizeof(float) * 8;
        var blockAlign = _channels * sizeof(float);

        "RIFF"u8.CopyTo(header);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(4), (uint)(36 + _dataBytes));
        "WAVE"u8.CopyTo(header.AsSpan(8));

        "fmt "u8.CopyTo(header.AsSpan(12));
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(16), 16);
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(20), FormatIeeeFloat);
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(22), (ushort)_channels);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(24), (uint)_sampleRate);
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(28), (uint)(_sampleRate * blockAlign));
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(32), (ushort)blockAlign);
        BinaryPrimitives.WriteUInt16LittleEndian(header.AsSpan(34), (ushort)bitsPerSample);

        "data"u8.CopyTo(header.AsSpan(36));
        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(40), (uint)_dataBytes);

        _file.Position = 0;
        await _file.WriteAsync(header);
        await _file.FlushAsync();
        await _file.DisposeAsync();
    }
}
