using Klippy.Shared.Audio;
using Microsoft.Extensions.Logging;

namespace Klippy.Tests.AudioCast.Probe;

/// <summary>
/// Drives <see cref="AdaptiveJitterBuffer"/> through synthetic arrival traces.
///
/// Step 6 is where the latency number is actually won, and it is the one component whose
/// failure mode — an occasional click on a bad WiFi night — is nearly impossible to
/// reproduce on demand with a real phone. So the traces are generated instead: a clean
/// LAN, ordinary WiFi, WiFi with the 30-50 ms retransmit spikes the plan warns about, and
/// the same with loss on top. Each one is replayed against the adaptive buffer and
/// against fixed buffers, so the claim that a fixed buffer has to choose between
/// dropouts and permanent latency is a measurement rather than an assertion.
/// </summary>
internal static class JitterCommand
{
    private sealed record Packet(uint Sequence, uint TimestampMs, long ArrivalMs);

    private sealed record Scenario(string Name, double JitterMs, double SpikeChance, double SpikeMs, double LossRate);

    private sealed record Outcome(
        string Buffer,
        long Played,
        long Concealed,
        long Starvations,
        int FinalTargetMs,
        double MeanLatencyMs,
        double P99LatencyMs);

    public static Task<int> RunAsync(string[] args, ILoggerFactory loggerFactory, CancellationToken cancellationToken)
    {
        var seconds = ProbeArgs.Seconds(args, 30.0);
        var frames = (int)(seconds * 1000 / AudioCastFormat.FrameMilliseconds);

        Scenario[] scenarios =
        [
            new("clean LAN", 1, 0, 0, 0),
            new("typical WiFi", 5, 0, 0, 0),
            new("WiFi + 30-50ms spikes", 5, 0.02, 40, 0),
            new("spikes + 1% loss", 5, 0.02, 40, 0.01),
        ];

        Console.WriteLine($"Replaying {seconds:F0}s traces ({frames} frames at {AudioCastFormat.FrameMilliseconds} ms)\n");
        Console.WriteLine("Latency is capture-to-playout for frames actually played: buffer depth plus");
        Console.WriteLine("network delay, not counting capture or codec.\n");

        var failures = 0;

        foreach (var scenario in scenarios)
        {
            var trace = Generate(scenario, frames, seed: 20260910);

            Console.WriteLine($"=== {scenario.Name} ===");
            Console.WriteLine($"    jitter +/-{scenario.JitterMs:F0} ms, " +
                              $"spikes {scenario.SpikeChance * 100:F0}% x {scenario.SpikeMs:F0} ms, " +
                              $"loss {scenario.LossRate * 100:F0}%, {trace.Count} of {frames} packets sent");

            List<Outcome> outcomes =
            [
                Adaptive(trace, frames, AudioRoute.Speaker, "adaptive (speaker)"),
                Adaptive(trace, frames, AudioRoute.BluetoothA2dp, "adaptive (A2DP)"),
                Fixed(trace, frames, 10, "fixed 10 ms"),
                Fixed(trace, frames, 30, "fixed 30 ms"),
                Fixed(trace, frames, 80, "fixed 80 ms"),
            ];

            Console.WriteLine($"    {"buffer",-20} {"played",7} {"conceal",8} {"starve",7} " +
                              $"{"target",7} {"mean ms",9} {"p99 ms",8}");

            foreach (var outcome in outcomes)
            {
                Console.WriteLine($"    {outcome.Buffer,-20} {outcome.Played,7} {outcome.Concealed,8} " +
                                  $"{outcome.Starvations,7} {outcome.FinalTargetMs,7} " +
                                  $"{outcome.MeanLatencyMs,9:F1} {outcome.P99LatencyMs,8:F1}");
            }

            // The adaptive buffer's job is to not starve. Concealing a packet that was
            // genuinely lost is correct; running dry because we held too little is not.
            var adaptiveSpeaker = outcomes[0];
            var lost = frames - trace.Count;
            var unexplained = adaptiveSpeaker.Concealed - lost;

            if (adaptiveSpeaker.Starvations > 0)
            {
                Console.WriteLine($"    -> FAIL: adaptive starved {adaptiveSpeaker.Starvations} time(s)");
                failures++;
            }
            else
            {
                Console.WriteLine($"    -> ok: no starvation; concealed {adaptiveSpeaker.Concealed} " +
                                  $"({lost} genuinely lost, {unexplained} other)");
            }

            Console.WriteLine();
        }

        Console.WriteLine(failures == 0
            ? "PASS - the adaptive buffer rode out every trace without running dry."
            : $"FAIL - {failures} scenario(s) starved.");

        return Task.FromResult(failures == 0 ? 0 : 1);
    }

    /// <summary>
    /// Builds an arrival trace. Spikes are the interesting part: a retransmit delays one
    /// packet without delaying the ones behind it, which is exactly how a fixed buffer
    /// gets caught out.
    /// </summary>
    private static List<Packet> Generate(Scenario scenario, int frames, int seed)
    {
        var random = new Random(seed);
        var packets = new List<Packet>(frames);

        for (var i = 0; i < frames; i++)
        {
            if (random.NextDouble() < scenario.LossRate)
            {
                continue;
            }

            var sent = (long)i * AudioCastFormat.FrameMilliseconds;
            var delay = (random.NextDouble() - 0.5) * 2 * scenario.JitterMs;

            if (scenario.SpikeChance > 0 && random.NextDouble() < scenario.SpikeChance)
            {
                delay += scenario.SpikeMs * (0.75 + (random.NextDouble() * 0.5));
            }

            packets.Add(new Packet(
                (uint)i,
                (uint)(i * AudioCastFormat.FrameMilliseconds),
                Math.Max(0, sent + (long)Math.Round(delay))));
        }

        // Arrival order, not send order: that is what reordering means on the wire.
        packets.Sort((a, b) => a.ArrivalMs.CompareTo(b.ArrivalMs));
        return packets;
    }

    private static Outcome Adaptive(List<Packet> trace, int frames, AudioRoute route, string label)
    {
        var buffer = new AdaptiveJitterBuffer(route);
        var payload = new byte[80];
        var latencies = new List<double>(frames);
        var arrival = 0;

        // Enough slots to drain the trace even after the initial fill.
        var ticks = frames + (200 / AudioCastFormat.FrameMilliseconds) + 100;

        for (var tick = 0; tick < ticks; tick++)
        {
            var now = (long)tick * AudioCastFormat.FrameMilliseconds;

            while (arrival < trace.Count && trace[arrival].ArrivalMs <= now)
            {
                var packet = trace[arrival++];
                buffer.Push(new AudioCastPacketHeader(packet.Sequence, packet.TimestampMs), payload, now);
            }

            var frame = buffer.Next();
            if (frame.Action == JitterBufferAction.Play)
            {
                latencies.Add(now - (frame.Sequence * (double)AudioCastFormat.FrameMilliseconds));
            }

            // Stop once the trace is spent and nothing is held. Ticking past that is the
            // stream ending, not a dropout, and counting it as starvation made even a
            // perfect trace look like it was failing.
            if (arrival >= trace.Count && buffer.BufferedMs == 0 && buffer.FramesPlayed > 0)
            {
                break;
            }
        }

        return Summarise(label, buffer.FramesPlayed, buffer.FramesConcealed, buffer.Starvations,
            buffer.TargetMs, latencies);
    }

    /// <summary>
    /// The straw man, modelled honestly: fill to a fixed depth, then play one frame per
    /// slot, concealing whatever is not there.
    /// </summary>
    private static Outcome Fixed(List<Packet> trace, int frames, int depthMs, string label)
    {
        var held = new Dictionary<uint, bool>();
        var latencies = new List<double>(frames);
        var arrival = 0;
        var playing = false;
        uint next = 0;
        long played = 0, concealed = 0, starvations = 0;

        var ticks = frames + (depthMs / AudioCastFormat.FrameMilliseconds) + 100;

        for (var tick = 0; tick < ticks; tick++)
        {
            var now = (long)tick * AudioCastFormat.FrameMilliseconds;

            while (arrival < trace.Count && trace[arrival].ArrivalMs <= now)
            {
                var packet = trace[arrival++];
                if (!playing || packet.Sequence >= next)
                {
                    held[packet.Sequence] = true;
                }
            }

            if (!playing)
            {
                if (held.Count * AudioCastFormat.FrameMilliseconds < depthMs)
                {
                    continue;
                }

                playing = true;
                next = held.Keys.Min();
            }

            if (held.Remove(next))
            {
                latencies.Add(now - (next * (double)AudioCastFormat.FrameMilliseconds));
                played++;
            }
            else
            {
                concealed++;
                if (held.Count == 0)
                {
                    starvations++;
                }
            }

            next++;

            // Same drain-tail exclusion as the adaptive run, so the comparison is fair.
            if (arrival >= trace.Count && held.Count == 0 && played > 0)
            {
                break;
            }
        }

        return Summarise(label, played, concealed, starvations, depthMs, latencies);
    }

    private static Outcome Summarise(
        string label,
        long played,
        long concealed,
        long starvations,
        int targetMs,
        List<double> latencies)
    {
        latencies.Sort();

        return new Outcome(
            label,
            played,
            concealed,
            starvations,
            targetMs,
            latencies.Count > 0 ? latencies.Average() : 0,
            latencies.Count > 0 ? latencies[(int)(latencies.Count * 0.99)] : 0);
    }
}
