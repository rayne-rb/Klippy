using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using Klippy.Mobile.Features.Pairing;
using Klippy.Shared;
using Klippy.Shared.Clipboard;

namespace Klippy.Mobile.Features.Clipboard;

/// <summary>
/// The phone's end of /api/clipboard.
///
/// Everything the clipboard moves goes over HTTP rather than the link, for the reasons on
/// <see cref="Klippy.Shared.Link.KlippyEvents.ClipboardEntry"/>: both directions want a
/// real answer, and content has no business on a socket that archives what crosses it.
/// </summary>
public sealed class ClipboardApiClient(PairedServerStore servers)
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    /// <summary>The board, or an empty list when this phone is not paired or the server is away.</summary>
    public async Task<IReadOnlyList<ClipboardEntryView>> ListAsync(CancellationToken ct = default)
    {
        var request = await BuildAsync(HttpMethod.Get, "/api/clipboard", ct);
        if (request is null)
        {
            return [];
        }

        using var response = await Http.SendAsync(request, ct);
        if (!response.IsSuccessStatusCode)
        {
            return [];
        }

        return await response.Content.ReadFromJsonAsync<List<ClipboardEntryView>>(
            KlippyJson.Options, ct) ?? [];
    }

    /// <summary>Shares something copied here. Returns null on success, or a sentence saying why not.</summary>
    public async Task<string?> PostTextAsync(string text, string visibility, CancellationToken ct = default)
    {
        var request = await BuildAsync(HttpMethod.Post, "/api/clipboard", ct);
        if (request is null)
        {
            return "This phone is not paired with a server.";
        }

        request.Content = JsonContent.Create(
            new ClipboardTextBody { Text = text, Visibility = visibility }, options: KlippyJson.Options);

        return await SendAsync(request, ct);
    }

    /// <summary>The same for an image, posted as a raw PNG body.</summary>
    public async Task<string?> PostImageAsync(byte[] png, string visibility, CancellationToken ct = default)
    {
        var request = await BuildAsync(
            HttpMethod.Post, $"/api/clipboard/image?visibility={Uri.EscapeDataString(visibility)}", ct);
        if (request is null)
        {
            return "This phone is not paired with a server.";
        }

        request.Content = new ByteArrayContent(png);
        request.Content.Headers.ContentType = new MediaTypeHeaderValue(ClipboardContentTypes.Png);

        return await SendAsync(request, ct);
    }

    /// <summary>One entry's content, or null when it could not be fetched.</summary>
    public async Task<byte[]?> FetchContentAsync(string entryId, CancellationToken ct = default)
    {
        var request = await BuildAsync(HttpMethod.Get, $"/api/clipboard/{entryId}/content", ct);
        if (request is null)
        {
            return null;
        }

        using var response = await Http.SendAsync(request, ct);
        return response.IsSuccessStatusCode
            ? await response.Content.ReadAsByteArrayAsync(ct)
            : null;
    }

    public async Task<string?> DeleteAsync(string entryId, CancellationToken ct = default)
    {
        var request = await BuildAsync(HttpMethod.Delete, $"/api/clipboard/{entryId}", ct);
        return request is null ? "This phone is not paired with a server." : await SendAsync(request, ct);
    }

    /// <summary>Asks one of your own devices to put this entry on its clipboard.</summary>
    public async Task<string?> ApplyToAsync(string entryId, string targetDeviceId, CancellationToken ct = default)
    {
        var request = await BuildAsync(HttpMethod.Post, $"/api/clipboard/{entryId}/apply", ct);
        if (request is null)
        {
            return "This phone is not paired with a server.";
        }

        request.Content = JsonContent.Create(
            new ClipboardApplyBody { TargetDeviceId = targetDeviceId }, options: KlippyJson.Options);

        return await SendAsync(request, ct);
    }

    private async Task<HttpRequestMessage?> BuildAsync(HttpMethod method, string path, CancellationToken ct)
    {
        var server = await servers.GetAsync(ct);
        if (server is null)
        {
            return null;
        }

        var request = new HttpRequestMessage(method, server.BaseUrl.TrimEnd('/') + path);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", server.Token);
        return request;
    }

    private static async Task<string?> SendAsync(HttpRequestMessage request, CancellationToken ct)
    {
        try
        {
            using var response = await Http.SendAsync(request, ct);
            if (response.IsSuccessStatusCode)
            {
                return null;
            }

            // The server explains itself in one sentence; pass that on rather than
            // inventing a second, vaguer one here.
            var body = await response.Content.ReadAsStringAsync(ct);
            return Describe(response.StatusCode, body);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            return "Could not reach the server.";
        }
    }

    private static string Describe(System.Net.HttpStatusCode status, string body)
    {
        try
        {
            using var document = System.Text.Json.JsonDocument.Parse(body);
            if (document.RootElement.TryGetProperty("error", out var error)
                && error.GetString() is { Length: > 0 } message)
            {
                return message;
            }
        }
        catch (System.Text.Json.JsonException)
        {
            // Not the shape we hoped for; fall through to the status.
        }

        return status switch
        {
            System.Net.HttpStatusCode.Unauthorized => "This phone is no longer paired.",
            System.Net.HttpStatusCode.NotFound => "That entry is gone.",
            System.Net.HttpStatusCode.Conflict => "That device is not connected.",
            _ => "The server would not take that.",
        };
    }

    private sealed record ClipboardTextBody
    {
        public required string Text { get; init; }
        public required string Visibility { get; init; }
    }

    private sealed record ClipboardApplyBody
    {
        public required string TargetDeviceId { get; init; }
    }
}
