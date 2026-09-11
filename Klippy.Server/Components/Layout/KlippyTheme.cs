using MudBlazor;

namespace Klippy.Server.Components.Layout;

/// <summary>
/// The single MudBlazor theme the app renders with, in both light and dark mode.
/// </summary>
/// <remarks>
/// The font stack is deliberately made of fonts the OS already has. MudBlazor's default
/// typography asks for Roboto, which would mean pulling it from a font CDN — and this
/// server is reached over the LAN by devices that may have no route to the internet.
/// </remarks>
public static class KlippyTheme
{
    private static readonly string[] FontStack =
    [
        "system-ui",
        "-apple-system",
        "Segoe UI",
        "Roboto",
        "Helvetica Neue",
        "Arial",
        "sans-serif",
    ];

    public static MudTheme Value { get; } = new()
    {
        PaletteLight = new PaletteLight
        {
            Primary = "#1b6ec2",
            Secondary = "#6b3fa0",
            AppbarBackground = "#052767",
            Success = "#2e9e4f",
            Info = "#0087ff",
            Error = "#e50000",
        },
        PaletteDark = new PaletteDark
        {
            Primary = "#6b9ed2",
            Secondary = "#b18ede",
            AppbarBackground = "#12151c",
            Success = "#4bbf6b",
            Info = "#3ba3ff",
            Error = "#ff5a5a",
        },
        Typography = new Typography
        {
            Default = new DefaultTypography { FontFamily = FontStack },
            H1 = new H1Typography { FontFamily = FontStack },
            H2 = new H2Typography { FontFamily = FontStack },
            H3 = new H3Typography { FontFamily = FontStack },
            H4 = new H4Typography { FontFamily = FontStack },
            H5 = new H5Typography { FontFamily = FontStack },
            H6 = new H6Typography { FontFamily = FontStack },
            Subtitle1 = new Subtitle1Typography { FontFamily = FontStack },
            Subtitle2 = new Subtitle2Typography { FontFamily = FontStack },
            Body1 = new Body1Typography { FontFamily = FontStack },
            Body2 = new Body2Typography { FontFamily = FontStack },
            Button = new ButtonTypography { FontFamily = FontStack },
            Caption = new CaptionTypography { FontFamily = FontStack },
            Overline = new OverlineTypography { FontFamily = FontStack },
        },
    };
}
