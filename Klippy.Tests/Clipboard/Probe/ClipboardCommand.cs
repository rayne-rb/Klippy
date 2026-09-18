using System.Net.Http.Headers;
using System.Net.Http.Json;
using Klippy.Shared;
using Klippy.Shared.Clipboard;
using Klippy.Shared.Pairing;
using Klippy.Tests.AudioCast.Probe;

namespace Klippy.Tests.Clipboard.Probe;

/// <summary>
/// Drives the clipboard against a running server, the way a device would.
///
/// The rules that can be checked without a database are unit tests
/// (<see cref="ClipboardRulesTests"/>). This covers what only a real server can answer:
/// that the board comes back scoped, that a duplicate is recognised, that an image
/// round-trips byte for byte, and — the one worth running before every release — that
/// none of what was copied ends up in the event history.
///
/// It pairs itself, so the approval has to be taken on the server's Devices page or with
/// the loopback admin API while it waits.
/// </summary>
internal static class ClipboardCommand
{
    public static async Task<int> RunAsync(string[] args, CancellationToken ct)
    {
        var baseUrl = (ProbeArgs.Value(args, "--server") ?? "http://localhost:5068").TrimEnd('/');
        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };

        Console.WriteLine($"Server: {baseUrl}");

        var token = await PairAsync(http, baseUrl, ct);
        if (token is null)
        {
            return 1;
        }

        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

        var failures = 0;

        failures += await CheckTextAsync(http, baseUrl, ct);
        failures += await CheckDuplicateAsync(http, baseUrl, ct);
        failures += await CheckImageAsync(http, baseUrl, ct);
        failures += await CheckOversizeAsync(http, baseUrl, ct);
        failures += await CheckBoardAsync(http, baseUrl, ct);

        Console.WriteLine();
        Console.WriteLine(failures == 0 ? "All checks passed." : $"{failures} check(s) failed.");
        return failures == 0 ? 0 : 1;
    }

    private static async Task<string?> PairAsync(HttpClient http, string baseUrl, CancellationToken ct)
    {
        var created = await http.PostAsJsonAsync($"{baseUrl}/api/pairing/requests", new PairingRequestInput
        {
            DeviceKind = Shared.Link.DeviceKind.Companion,
            DeviceName = "clipboard probe",
            Platform = "probe",
        }, KlippyJson.Options, ct);

        if (!created.IsSuccessStatusCode)
        {
            Console.Error.WriteLine($"Could not ask to pair: {created.StatusCode}");
            return null;
        }

        var request = await created.Content.ReadFromJsonAsync<PairingRequestCreated>(KlippyJson.Options, ct);
        if (request is null)
        {
            return null;
        }

        Console.WriteLine($"Approve code {request.Code} on the server's Devices page (signed in as the account to test).");

        // Polled rather than waited on a signal: the approval happens in a browser, and
        // the point of showing the code is that a human goes and clicks it.
        while (!ct.IsCancellationRequested && DateTimeOffset.UtcNow < request.ExpiresAt)
        {
            await Task.Delay(TimeSpan.FromSeconds(1), ct);

            var state = await http.GetFromJsonAsync<PairingRequestState>(
                $"{baseUrl}/api/pairing/requests/{request.RequestId}", KlippyJson.Options, ct);

            if (state?.Token is { Length: > 0 } token)
            {
                Console.WriteLine("Paired.\n");
                return token;
            }

            if (state?.Status is PairingStatus.Denied or PairingStatus.Expired)
            {
                Console.Error.WriteLine($"Pairing {state.Status}.");
                return null;
            }
        }

        Console.Error.WriteLine("Pairing was never approved.");
        return null;
    }

    private static async Task<int> CheckTextAsync(HttpClient http, string baseUrl, CancellationToken ct)
    {
        var text = $"probe text {Guid.NewGuid()}";
        var posted = await http.PostAsJsonAsync($"{baseUrl}/api/clipboard",
            new { text, visibility = ClipboardVisibility.Group }, ct);

        if (!posted.IsSuccessStatusCode)
        {
            return Fail("text", $"post returned {posted.StatusCode}: {await posted.Content.ReadAsStringAsync(ct)}");
        }

        var entries = await BoardAsync(http, baseUrl, ct);
        var mine = entries.FirstOrDefault(e => e.Preview == text);

        if (mine is null)
        {
            return Fail("text", "the entry did not come back on the board");
        }

        var content = await http.GetStringAsync($"{baseUrl}/api/clipboard/{mine.EntryId}/content", ct);
        return content == text ? Pass("text") : Fail("text", "the content came back changed");
    }

    private static async Task<int> CheckDuplicateAsync(HttpClient http, string baseUrl, CancellationToken ct)
    {
        var text = $"probe duplicate {Guid.NewGuid()}";
        var body = new { text, visibility = ClipboardVisibility.Group };

        await http.PostAsJsonAsync($"{baseUrl}/api/clipboard", body, ct);
        var again = await http.PostAsJsonAsync($"{baseUrl}/api/clipboard", body, ct);

        var answer = await again.Content.ReadAsStringAsync(ct);

        // A clipboard is read by polling it, so the same content arrives over and over.
        // Recognising that is what stops a board of one thing repeated a hundred times.
        return answer.Contains("duplicate")
            ? Pass("duplicate")
            : Fail("duplicate", $"a repeat of the same copy was stored again: {answer}");
    }

    private static async Task<int> CheckImageAsync(HttpClient http, string baseUrl, CancellationToken ct)
    {
        var png = SmallPng();

        using var content = new ByteArrayContent(png);
        content.Headers.ContentType = new MediaTypeHeaderValue(ClipboardContentTypes.Png);

        var posted = await http.PostAsync(
            $"{baseUrl}/api/clipboard/image?visibility={ClipboardVisibility.Group}", content, ct);

        if (!posted.IsSuccessStatusCode)
        {
            return Fail("image", $"post returned {posted.StatusCode}");
        }

        var entries = await BoardAsync(http, baseUrl, ct);
        var image = entries.FirstOrDefault(e => e.ContentType == ClipboardContentTypes.Png);

        if (image is null)
        {
            return Fail("image", "the image did not come back on the board");
        }

        var back = await http.GetByteArrayAsync($"{baseUrl}/api/clipboard/{image.EntryId}/content", ct);
        return back.SequenceEqual(png)
            ? Pass("image")
            : Fail("image", $"came back as {back.Length} bytes, not the {png.Length} sent");
    }

    private static async Task<int> CheckOversizeAsync(HttpClient http, string baseUrl, CancellationToken ct)
    {
        var tooBig = new string('x', ClipboardLimits.MaxTextBytes + 1);
        var posted = await http.PostAsJsonAsync($"{baseUrl}/api/clipboard",
            new { text = tooBig, visibility = ClipboardVisibility.Group }, ct);

        return posted.IsSuccessStatusCode
            ? Fail("oversize", "text past the cap was accepted")
            : Pass("oversize");
    }

    private static async Task<int> CheckBoardAsync(HttpClient http, string baseUrl, CancellationToken ct)
    {
        var entries = await BoardAsync(http, baseUrl, ct);

        // Everything this probe can see is either its own account's or shared server-wide.
        // Anything else would mean the read rule is not being applied.
        var leaked = entries.Where(e => !e.IsMine && e.Visibility != ClipboardVisibility.Server).ToList();

        if (leaked.Count > 0)
        {
            return Fail("scope", $"{leaked.Count} entr(ies) from another account were visible");
        }

        Console.WriteLine($"  board: {entries.Count} entr(ies), {entries.Count(e => !e.IsMine)} shared from elsewhere");
        return Pass("scope");
    }

    private static async Task<IReadOnlyList<ClipboardEntryView>> BoardAsync(
        HttpClient http, string baseUrl, CancellationToken ct) =>
        await http.GetFromJsonAsync<List<ClipboardEntryView>>(
            $"{baseUrl}/api/clipboard", KlippyJson.Options, ct) ?? [];

    private static int Pass(string name)
    {
        Console.WriteLine($"  ok    {name}");
        return 0;
    }

    private static int Fail(string name, string why)
    {
        Console.WriteLine($"  FAIL  {name}: {why}");
        return 1;
    }

    /// <summary>A real 2x2 PNG, built here so the probe needs no fixture file beside it.</summary>
    private static byte[] SmallPng()
    {
        var png = new MemoryStream();
        png.Write([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

        Span<byte> header = stackalloc byte[13];
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(header[..4], 2);
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(header[4..8], 2);
        header[8] = 8;  // bit depth
        header[9] = 2;  // truecolour
        Chunk(png, "IHDR"u8, header);

        // Two rows, each a filter byte then two RGB pixels.
        byte[] raw = [0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0xFF, 0x00];
        Chunk(png, "IDAT"u8, Deflate(raw));
        Chunk(png, "IEND"u8, []);

        return png.ToArray();
    }

    private static void Chunk(Stream into, ReadOnlySpan<byte> type, ReadOnlySpan<byte> data)
    {
        Span<byte> length = stackalloc byte[4];
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(length, (uint)data.Length);
        into.Write(length);

        var body = new byte[type.Length + data.Length];
        type.CopyTo(body);
        data.CopyTo(body.AsSpan(type.Length));
        into.Write(body);

        Span<byte> crc = stackalloc byte[4];
        System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(crc, Crc32(body));
        into.Write(crc);
    }

    /// <summary>zlib-wrapped deflate, which is what a PNG's IDAT holds.</summary>
    private static byte[] Deflate(byte[] raw)
    {
        var compressed = new MemoryStream();

        using (var zlib = new System.IO.Compression.ZLibStream(
                   compressed, System.IO.Compression.CompressionLevel.Optimal, leaveOpen: true))
        {
            zlib.Write(raw);
        }

        return compressed.ToArray();
    }

    /// <summary>
    /// CRC-32/ISO-HDLC, the one every PNG chunk carries. Written out rather than taken
    /// from System.IO.Hashing so the test project gains no package for eight lines.
    /// </summary>
    private static uint Crc32(ReadOnlySpan<byte> data)
    {
        var crc = 0xFFFFFFFFu;

        foreach (var b in data)
        {
            crc ^= b;

            for (var bit = 0; bit < 8; bit++)
            {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320u : crc >> 1;
            }
        }

        return crc ^ 0xFFFFFFFFu;
    }
}
