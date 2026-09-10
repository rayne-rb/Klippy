using System.Net.Http.Json;
using Klippy.Shared;
using Klippy.Shared.Link;
using Klippy.Shared.Pairing;

namespace Klippy.Mobile.Features.Pairing;

/// <summary>
/// Runs the pairing handshake: ask, show the code, poll until a human approves it on
/// the server's Devices page.
/// </summary>
public sealed class MobilePairingClient(ILogger<MobilePairingClient> logger)
{
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(1.5);

    /// <summary>Raised as soon as there is a code for the user to compare.</summary>
    public event Action<string>? CodeReady;

    /// <summary>
    /// Pairs with the server at <paramref name="baseUrl"/>, returning the device id
    /// and token, or null if it was declined, expired or the server went away.
    /// </summary>
    public async Task<(string DeviceId, string Token)?> PairAsync(
        string baseUrl,
        string deviceName,
        string platform,
        CancellationToken ct)
    {
        using var http = new HttpClient { BaseAddress = new Uri(baseUrl), Timeout = TimeSpan.FromSeconds(10) };

        var input = new PairingRequestInput
        {
            DeviceKind = DeviceKind.Mobile,
            DeviceName = deviceName,
            Platform = platform,
        };

        PairingRequestCreated? created;
        try
        {
            var response = await http.PostAsJsonAsync("/api/pairing/requests", input, KlippyJson.Options, ct);
            response.EnsureSuccessStatusCode();
            created = await response.Content.ReadFromJsonAsync<PairingRequestCreated>(KlippyJson.Options, ct);
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
        {
            logger.LogWarning(ex, "Could not start pairing with {BaseUrl}", baseUrl);
            return null;
        }

        if (created is null)
        {
            return null;
        }

        CodeReady?.Invoke(created.Code);
        logger.LogInformation("Pairing code {Code}, awaiting approval", created.Code);

        while (!ct.IsCancellationRequested && DateTimeOffset.UtcNow < created.ExpiresAt)
        {
            await Task.Delay(PollInterval, ct);

            PairingRequestState? state;
            try
            {
                state = await http.GetFromJsonAsync<PairingRequestState>(
                    $"/api/pairing/requests/{created.RequestId}", KlippyJson.Options, ct);
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
            {
                continue; // Transient; keep polling until the request expires.
            }

            switch (state?.Status)
            {
                case PairingStatus.Pending:
                    continue;

                case PairingStatus.Approved when !string.IsNullOrEmpty(state.Token):
                    return (state.DeviceId ?? string.Empty, state.Token);

                case PairingStatus.Approved:
                    // Approved but the single-use token was already collected or lost
                    // to a server restart. Nothing usable here.
                    logger.LogWarning("Pairing approved but no token was returned");
                    return null;

                default:
                    logger.LogInformation("Pairing ended as {Status}", state?.Status ?? "unknown");
                    return null;
            }
        }

        return null;
    }
}
