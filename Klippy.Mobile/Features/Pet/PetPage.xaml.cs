using Klippy.Mobile.Features.Link;
using Klippy.Shared.Link;
using Klippy.Shared.Link.Payloads;

namespace Klippy.Mobile.Features.Pet;

/// <summary>
/// The whole phone app, near enough: what Klippy is up to, and a few ways to bother it.
///
/// Everything arrives on the link's background loop, so every handler hops to the main
/// thread before touching a control.
/// </summary>
public partial class PetPage : ContentPage
{
    private const int ActivityLines = 6;

    private readonly KlippyLinkClient _link;
    private readonly Queue<string> _activity = new();
    private bool _dvdOn;

    public PetPage(KlippyLinkClient link)
    {
        InitializeComponent();
        _link = link;

        _link.StateChanged += OnStateChanged;
        _link.EventReceived += OnEventReceived;
        _link.PairingCodeReady += OnPairingCodeReady;

        OnStateChanged(_link.State);
        _link.Start();

        _ = ShowSavedAddressAsync();
    }

    private async Task ShowSavedAddressAsync()
    {
        var saved = await _link.GetManualAddressAsync();
        if (!string.IsNullOrEmpty(saved))
        {
            Dispatcher.Dispatch(() => AddressEntry.Text = saved);
        }
    }

    private void OnStateChanged(LinkState state) => Dispatcher.Dispatch(() =>
    {
        if (state != LinkState.Pairing)
        {
            CodeLabel.IsVisible = false;
        }

        switch (state)
        {
            case LinkState.Offline:
                StatusLabel.Text = "Not connected";
                HintLabel.Text = "Trying again shortly.";
                break;
            case LinkState.Searching:
                StatusLabel.Text = "Looking for Klippy";
                HintLabel.Text = "Make sure this phone is on the same network as the server.";
                break;
            case LinkState.Pairing:
                StatusLabel.Text = "Waiting to be let in";
                break;
            case LinkState.Connecting:
                StatusLabel.Text = "Connecting";
                HintLabel.Text = string.Empty;
                break;
            case LinkState.Connected:
                StatusLabel.Text = $"Connected to {_link.ServerName}";
                HintLabel.Text = string.Empty;
                break;
        }

        var live = state == LinkState.Connected;
        ControlsSection.IsVisible = live;
        UnpairButton.IsVisible = state is LinkState.Connected or LinkState.Offline;

        // Only worth offering once automatic discovery has visibly not worked.
        ManualSection.IsVisible = state is LinkState.Offline or LinkState.Searching;
    });

    private void OnPairingCodeReady(string code) => Dispatcher.Dispatch(() =>
    {
        CodeLabel.Text = code;
        CodeLabel.IsVisible = true;
        HintLabel.Text = "Approve this code on the server's Devices page.";
    });

    private void OnEventReceived(LinkEnvelope envelope) => Dispatcher.Dispatch(() =>
    {
        switch (envelope.Type)
        {
            case KlippyEvents.PetStats:
                if (envelope.PayloadAs<PetStatsPayload>() is { } stats)
                {
                    ShowStats(stats);
                }

                break;

            case KlippyEvents.PetSpoke:
                Note($"Klippy said “{envelope.PayloadAs<SayPayload>()?.Text}”");
                break;

            case KlippyEvents.PetDied:
                Note("Klippy died.");
                break;

            case KlippyEvents.PetRevived:
                Note("Klippy came back.");
                break;

            case KlippyEvents.DeviceConnected:
                Note($"{envelope.PayloadAs<DevicePresencePayload>()?.DeviceName} came online.");
                break;

            case KlippyEvents.DeviceDisconnected:
                Note($"{envelope.PayloadAs<DevicePresencePayload>()?.DeviceName} went offline.");
                break;

            case KlippyEvents.LinkWelcome:
                var welcome = envelope.PayloadAs<WelcomePayload>();
                Note(welcome?.Peers.Count > 0
                    ? $"Also here: {string.Join(", ", welcome.Peers.Select(p => p.DeviceName))}"
                    : "Nothing else is connected yet.");
                // Ask for vitals straight away rather than waiting for the next tick.
                _link.Publish(KlippyEvents.PetStatsRequest);
                break;
        }
    });

    private void ShowStats(PetStatsPayload stats)
    {
        VitalsSection.IsVisible = true;

        FoodLabel.Text = $"Food · {stats.FoodStatus} ({stats.Food:0})";
        MoodLabel.Text = $"Mood · {stats.MoodStatus} ({stats.Mood:0})";
        HealthLabel.Text = $"Health · {stats.HealthStatus} ({stats.Health:0})";

        FoodBar.Progress = Math.Clamp(stats.Food / 100.0, 0, 1);
        MoodBar.Progress = Math.Clamp(stats.Mood / 100.0, 0, 1);
        HealthBar.Progress = Math.Clamp(stats.Health / 100.0, 0, 1);

        SeenLabel.Text = stats.IsDead
            ? "Klippy is dead."
            : stats.FeedingEnabled
                ? $"Updated {DateTime.Now:HH:mm:ss}"
                : $"Feeding is switched off · updated {DateTime.Now:HH:mm:ss}";

        FeedButton.IsEnabled = stats.FeedingEnabled && !stats.IsDead;
    }

    private void Note(string line)
    {
        _activity.Enqueue($"{DateTime.Now:HH:mm:ss}  {line}");
        while (_activity.Count > ActivityLines)
        {
            _activity.Dequeue();
        }

        ActivityLabel.Text = string.Join("\n", _activity.Reverse());
    }

    private async void OnAddressSubmitted(object? sender, EventArgs e)
    {
        var typed = AddressEntry.Text?.Trim();
        if (string.IsNullOrEmpty(typed))
        {
            return;
        }

        // Reject it here rather than letting the link loop fail on it silently.
        if (Discovery.ServerLocator.NormaliseAddress(typed) is null)
        {
            Note($"'{typed}' is not an address I can use.");
            return;
        }

        Note($"Trying {typed}");
        await _link.SetManualAddressAsync(typed);
    }

    private void OnFeedClicked(object? sender, EventArgs e) =>
        _link.Publish(KlippyEvents.PetFeed, new FeedPayload { Count = 1 });

    private void OnDvdClicked(object? sender, EventArgs e)
    {
        _dvdOn = !_dvdOn;
        DvdButton.Text = _dvdOn ? "DVD off" : "DVD on";
        _link.Publish(KlippyEvents.PetDvdToggle, new TogglePayload { Enabled = _dvdOn });
    }

    private void OnRefreshClicked(object? sender, EventArgs e) =>
        _link.Publish(KlippyEvents.PetStatsRequest);

    private void OnSayClicked(object? sender, EventArgs e)
    {
        var text = SpeechEntry.Text?.Trim();
        if (string.IsNullOrEmpty(text))
        {
            return;
        }

        _link.Publish(KlippyEvents.PetSay, new SayPayload { Text = text });
        SpeechEntry.Text = string.Empty;
    }

    private async void OnUnpairClicked(object? sender, EventArgs e)
    {
        if (!await DisplayAlertAsync("Forget this server?",
                "Klippy will have to be paired again from the server's Devices page.",
                "Forget", "Cancel"))
        {
            return;
        }

        VitalsSection.IsVisible = false;
        await _link.ForgetPairingAsync();
    }
}
