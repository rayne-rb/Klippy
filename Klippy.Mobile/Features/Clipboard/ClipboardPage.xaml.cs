using Klippy.Mobile.Features.Link;
using MauiClipboard = Microsoft.Maui.ApplicationModel.DataTransfer.Clipboard;
using Klippy.Shared.Clipboard;
using Klippy.Shared.Link;

namespace Klippy.Mobile.Features.Clipboard;

/// <summary>
/// The phone's end of the shared clipboard: a switch, who it shares with, and what has
/// been copied lately across this account's devices.
///
/// The one place this differs from the Companion is that it does not watch. Since Android
/// 10 an application may only read the clipboard while it has focus, so there is nothing
/// to watch with — instead the clipboard is read when this page comes to the front, and
/// there is a button for the rest of the time. Pretending otherwise would mean a switch
/// that silently does nothing in a pocket.
/// </summary>
public partial class ClipboardPage : ContentPage
{
    private readonly KlippyLinkClient _link;
    private readonly ClipboardApiClient _api;
    private readonly ClipboardStore _cache;
    private readonly ClipboardSettings _settings;
    private readonly IClipboardImages? _images;

    private string _visibility = ClipboardVisibility.Group;
    private bool _enabled;

    /// <summary>Guards the toggle handlers while the stored settings are being put on screen.</summary>
    private bool _loading;

    /// <summary>What was last shared from here, so the same copy is not sent twice.</summary>
    private string? _lastShared;

    public ClipboardPage(
        KlippyLinkClient link,
        ClipboardApiClient api,
        ClipboardStore cache,
        ClipboardSettings settings,
        IEnumerable<IClipboardImages> images)
    {
        InitializeComponent();

        _link = link;
        _api = api;
        _cache = cache;
        _settings = settings;

        // Resolved as a collection so the page works on a platform that registers none.
        _images = images.FirstOrDefault();

        _link.EventReceived += OnEventReceived;
    }

    protected override async void OnAppearing()
    {
        base.OnAppearing();

        await LoadSettingsAsync();
        await ShowCachedAsync();
        await RefreshAsync();

        // Coming back to this page is the one moment Android will let us read the
        // clipboard, so take it.
        if (_enabled)
        {
            await ShareCurrentAsync(quiet: true);
        }
    }

    private async Task LoadSettingsAsync()
    {
        _loading = true;

        _enabled = await _settings.GetEnabledAsync();
        _visibility = await _settings.GetVisibilityAsync();

        EnabledSwitch.IsToggled = _enabled;
        VisibilityPicker.SelectedIndex = _visibility == ClipboardVisibility.Server ? 1 : 0;
        VisibilityPicker.IsEnabled = _enabled;
        ShareButton.IsEnabled = _enabled;

        _loading = false;
        ShowState();
    }

    private void ShowState()
    {
        if (_link.State != LinkState.Connected)
        {
            StateLabel.Text = "Not connected to a server, so nothing is being shared.";
            return;
        }

        if (_link.OwnerName is null)
        {
            StateLabel.Text = "This phone has not been approved into an account yet. "
                              + "Approve it on the server's Devices page.";
            return;
        }

        StateLabel.Text = !_enabled
            ? "Off. Nothing on this phone's clipboard is read while it is."
            : _visibility == ClipboardVisibility.Server
                ? $"On, as {_link.OwnerName}. What you copy here is shared with everyone on this server."
                : $"On, as {_link.OwnerName}. What you copy here stays on your own devices.";
    }

    private async void OnEnabledToggled(object? sender, ToggledEventArgs e)
    {
        if (_loading)
        {
            return;
        }

        _enabled = e.Value;
        await _settings.SetEnabledAsync(_enabled);

        VisibilityPicker.IsEnabled = _enabled;
        ShareButton.IsEnabled = _enabled;

        Announce();
        ShowState();

        if (_enabled)
        {
            // Whatever is on the clipboard counts from the moment it is switched on, and
            // nothing at all before that.
            _lastShared = null;
            await ShareCurrentAsync(quiet: true);
        }
    }

    private async void OnVisibilityChanged(object? sender, EventArgs e)
    {
        if (_loading)
        {
            return;
        }

        _visibility = VisibilityPicker.SelectedIndex == 1
            ? ClipboardVisibility.Server
            : ClipboardVisibility.Group;

        await _settings.SetVisibilityAsync(_visibility);

        Announce();
        ShowState();
    }

    /// <summary>Tells the server this phone is taking part, so its own page can say who is.</summary>
    private void Announce() =>
        _link.Publish(KlippyEvents.ClipboardSharing, new ClipboardSharingPayload
        {
            Enabled = _enabled,
            Visibility = _visibility,
        });

    private async void OnShareClicked(object? sender, EventArgs e) => await ShareCurrentAsync(quiet: false);

    /// <summary>
    /// Reads whatever is on the clipboard now and sends it up. An image is preferred when
    /// there is one: an application offering a picture often offers its filename as text
    /// alongside, and the picture is what was meant.
    /// </summary>
    private async Task ShareCurrentAsync(bool quiet)
    {
        if (!_enabled)
        {
            return;
        }

        if (_images is not null && await _images.ReadPngAsync() is { Length: > 0 } png)
        {
            var digest = Convert.ToHexStringLower(System.Security.Cryptography.SHA256.HashData(png));
            if (digest == _lastShared)
            {
                return;
            }

            _lastShared = digest;
            var failure = await _api.PostImageAsync(png, _visibility);
            await ReportAsync(failure, "Shared the image you copied.", quiet);
            return;
        }

        var text = await MauiClipboard.Default.GetTextAsync();
        if (string.IsNullOrWhiteSpace(text))
        {
            if (!quiet)
            {
                BoardStatusLabel.Text = "There is nothing on the clipboard to share.";
            }

            return;
        }

        if (text == _lastShared)
        {
            return;
        }

        _lastShared = text;
        var error = await _api.PostTextAsync(text, _visibility);
        await ReportAsync(error, "Shared what you copied.", quiet);
    }

    private async Task ReportAsync(string? error, string success, bool quiet)
    {
        if (error is not null)
        {
            // Let the next attempt try again rather than sitting on something that never
            // reached the server.
            _lastShared = null;
            BoardStatusLabel.Text = error;
            return;
        }

        if (!quiet)
        {
            BoardStatusLabel.Text = success;
        }

        await RefreshAsync();
    }

    private async void OnRefreshClicked(object? sender, EventArgs e) => await RefreshAsync();

    private async Task RefreshAsync()
    {
        var entries = await _api.ListAsync();

        // An empty answer from an unreachable server should not wipe what is on screen.
        if (entries.Count == 0 && _link.State != LinkState.Connected)
        {
            return;
        }

        await _cache.SaveAsync(entries);
        Show(entries);
    }

    private async Task ShowCachedAsync() => Show(await _cache.GetAsync());

    private void Show(IReadOnlyList<ClipboardEntryView> entries)
    {
        BoardView.ItemsSource = entries.Select(e => new ClipboardRow(e)).ToList();
        BoardStatusLabel.Text = entries.Count == 0
            ? "Nothing copied yet."
            : $"{entries.Count} entr{(entries.Count == 1 ? "y" : "ies")}";
    }

    private async void OnCopyClicked(object? sender, EventArgs e)
    {
        if (RowOf(sender) is not { } row)
        {
            return;
        }

        var content = await _api.FetchContentAsync(row.EntryId);
        if (content is null)
        {
            BoardStatusLabel.Text = "Could not fetch that entry.";
            return;
        }

        if (row.IsImage)
        {
            if (_images is null)
            {
                BoardStatusLabel.Text = "This phone cannot put an image on the clipboard.";
                return;
            }

            var failure = await _images.WritePngAsync(content);
            BoardStatusLabel.Text = failure ?? "Image copied.";
            return;
        }

        var text = System.Text.Encoding.UTF8.GetString(content);
        await MauiClipboard.Default.SetTextAsync(text);

        // Ours coming back, not a fresh copy: without this the next visit to this page
        // would send it straight up again.
        _lastShared = text;
        BoardStatusLabel.Text = "Copied.";
    }

    private async void OnSendClicked(object? sender, EventArgs e)
    {
        if (RowOf(sender) is not { } row)
        {
            return;
        }

        // The server only ever lists this account's devices, so everything offered here
        // is already something this phone is allowed to reach.
        var peers = _link.Peers;
        if (peers.Count == 0)
        {
            BoardStatusLabel.Text = "None of your other devices are connected.";
            return;
        }

        var names = peers.Select(p => p.DeviceName).ToArray();
        var chosen = await DisplayActionSheetAsync("Send to", "Cancel", null, names);
        var target = peers.FirstOrDefault(p => p.DeviceName == chosen);

        if (target is null)
        {
            return;
        }

        BoardStatusLabel.Text = await _api.ApplyToAsync(row.EntryId, target.DeviceId)
                                ?? $"Sent to {target.DeviceName}.";
    }

    private async void OnDeleteClicked(object? sender, EventArgs e)
    {
        if (RowOf(sender) is not { } row)
        {
            return;
        }

        var error = await _api.DeleteAsync(row.EntryId);
        if (error is not null)
        {
            BoardStatusLabel.Text = error;
            return;
        }

        await RefreshAsync();
    }

    /// <summary>
    /// An entry arriving or leaving is announced without its content, so the only useful
    /// response is to ask for the list again.
    /// </summary>
    private void OnEventReceived(LinkEnvelope envelope)
    {
        switch (envelope.Type)
        {
            case KlippyEvents.ClipboardEntry:
            case KlippyEvents.ClipboardRemoved:
                Dispatcher.Dispatch(async () => await RefreshAsync());
                break;

            case KlippyEvents.ClipboardApply:
                if (envelope.PayloadAs<ClipboardApplyPayload>() is { } apply)
                {
                    Dispatcher.Dispatch(async () => await ApplyAsync(apply.EntryId));
                }

                break;

            case KlippyEvents.LinkWelcome:
                Dispatcher.Dispatch(ShowState);
                break;
        }
    }

    /// <summary>
    /// Another of your devices asking this phone to hold something. The content is fetched
    /// here with this phone's own token — being asked to apply an entry is not the same as
    /// being handed one.
    /// </summary>
    private async Task ApplyAsync(string entryId)
    {
        var content = await _api.FetchContentAsync(entryId);
        if (content is null)
        {
            return;
        }

        if (LooksLikePng(content))
        {
            if (_images is not null)
            {
                await _images.WritePngAsync(content);
                BoardStatusLabel.Text = "An image was sent to this phone's clipboard.";
            }

            return;
        }

        var text = System.Text.Encoding.UTF8.GetString(content);
        await MauiClipboard.Default.SetTextAsync(text);
        _lastShared = text;
        BoardStatusLabel.Text = "Something was sent to this phone's clipboard.";
    }

    private static ClipboardRow? RowOf(object? sender) =>
        (sender as Button)?.BindingContext as ClipboardRow;

    /// <summary>The eight bytes every PNG starts with — a surer test than anything claimed about it.</summary>
    private static bool LooksLikePng(byte[] content) =>
        content.Length > 8
        && content[0] == 0x89 && content[1] == 0x50 && content[2] == 0x4E && content[3] == 0x47
        && content[4] == 0x0D && content[5] == 0x0A && content[6] == 0x1A && content[7] == 0x0A;
}
