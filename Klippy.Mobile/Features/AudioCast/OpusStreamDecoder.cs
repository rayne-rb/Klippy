using Concentus;
using Klippy.Shared.Audio;

namespace Klippy.Mobile.Features.AudioCast;

/// <summary>
/// Decodes the stream, and covers the gaps where frames never arrived.
///
/// Concealment is the whole reason a lost frame is survivable. Handing the decoder an
/// empty payload makes it synthesise a continuation from what it already played instead
/// of returning a hole — verified against Concentus 2.2.2: an empty span returns a full
/// 240-sample frame with real energy in it. At 5 ms per frame a single loss is a gap far
/// too short to hear, which is what makes running without in-band FEC an acceptable
/// trade for the lookahead it saves.
/// </summary>
public sealed class OpusStreamDecoder : IDisposable
{
    private readonly IOpusDecoder _decoder;
    private readonly float[] _frame;

    public OpusStreamDecoder(int sampleRate, int channels)
    {
        Channels = channels;
        _decoder = OpusCodecFactory.CreateDecoder(sampleRate, channels);
        _frame = new float[AudioCastFormat.SampleCount(channels)];
    }

    public int Channels { get; }

    public long Decoded { get; private set; }

    public long Concealed { get; private set; }

    /// <summary>Decodes one packet, returning the frame as interleaved floats.</summary>
    public ReadOnlySpan<float> Decode(ReadOnlySpan<byte> payload)
    {
        var produced = _decoder.Decode(payload, _frame, AudioCastFormat.SamplesPerChannel, decode_fec: false);
        Decoded++;

        return Result(produced);
    }

    /// <summary>
    /// Produces a frame for a packet that never came. Silence would be an audible click;
    /// the decoder's own concealment is not.
    /// </summary>
    public ReadOnlySpan<float> Conceal()
    {
        Concealed++;

        try
        {
            var produced = _decoder.Decode(
                ReadOnlySpan<byte>.Empty, _frame, AudioCastFormat.SamplesPerChannel, decode_fec: false);

            return Result(produced);
        }
        catch (Exception ex) when (ex is ArgumentException or IndexOutOfRangeException)
        {
            // Should not happen on 2.2.2, but silence beats a crash mid-stream.
            Array.Clear(_frame);
            return _frame;
        }
    }

    /// <summary>Silence, for the stretch before the buffer has enough to start.</summary>
    public ReadOnlySpan<float> Silence()
    {
        Array.Clear(_frame);
        return _frame;
    }

    private ReadOnlySpan<float> Result(int producedPerChannel)
    {
        if (producedPerChannel == AudioCastFormat.SamplesPerChannel)
        {
            return _frame;
        }

        // A short frame would otherwise leave the previous frame's tail in the buffer and
        // play it twice.
        var produced = producedPerChannel * Channels;
        if (produced < 0 || produced > _frame.Length)
        {
            Array.Clear(_frame);
            return _frame;
        }

        Array.Clear(_frame, produced, _frame.Length - produced);
        return _frame;
    }

    public void Dispose() => _decoder.Dispose();
}
