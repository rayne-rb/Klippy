namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// Which output to capture when a listener does not ask for a particular one.
///
/// In memory only, deliberately. The plan's position is that a cast does not outlive the
/// process capturing for it, so there is no schema change here; if the choice should
/// survive a restart it becomes <c>db/up/0004_audio_cast.sql</c> and this grows a
/// repository behind the same two members.
/// </summary>
public sealed class AudioCastPreferences
{
    private readonly Lock _gate = new();
    private string? _preferredOutputDeviceId;

    /// <summary>Raised when the choice changes, so an open dashboard re-renders.</summary>
    public event Action? Changed;

    /// <summary>Null means whatever the platform calls its default output.</summary>
    public string? PreferredOutputDeviceId
    {
        get
        {
            lock (_gate)
            {
                return _preferredOutputDeviceId;
            }
        }
    }

    public void SetPreferredOutput(string? deviceId)
    {
        lock (_gate)
        {
            if (_preferredOutputDeviceId == deviceId)
            {
                return;
            }

            _preferredOutputDeviceId = deviceId;
        }

        Changed?.Invoke();
    }
}
