namespace Klippy.Mobile.Features.Link;

/// <summary>
/// How this phone introduces itself when pairing. The name lands in front of whoever
/// is approving it on the server, so it should be recognisable at a glance.
/// </summary>
public static class DeviceNaming
{
    public static string Describe()
    {
        var model = DeviceInfo.Current.Model;
        var name = DeviceInfo.Current.Name;

        // Android often reports a generic model; the user-set device name is better
        // when there is one.
        if (!string.IsNullOrWhiteSpace(name) && !name.Equals(model, StringComparison.OrdinalIgnoreCase))
        {
            return name;
        }

        return string.IsNullOrWhiteSpace(model) ? "Phone" : model;
    }

    public static string Platform() =>
        $"{DeviceInfo.Current.Platform} {DeviceInfo.Current.VersionString}";
}
