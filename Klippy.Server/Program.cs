using Klippy.Server.Common;
using Klippy.Server.Components;
using Klippy.Server.Data;
using Klippy.Server.Features.Accounts;
using Klippy.Server.Features.AudioCast;
using Klippy.Server.Features.Clipboard;
using Klippy.Server.Features.Discovery;
using Klippy.Server.Features.Link;
using Klippy.Server.Features.Market;
using Klippy.Server.Features.Pairing;
using Klippy.Server.Features.PetState;
using Klippy.Shared;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using MudBlazor.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// Minimal-API results serialize with these rather than KlippyJson.Options, so the
// shared wire settings have to be stamped on here or HTTP responses drift from what
// the sockets send — notably by writing nulls the Companion does not expect.
builder.Services.ConfigureHttpJsonOptions(options => KlippyJson.Apply(options.SerializerOptions));

// Dialogs, snackbars and popovers are served by providers in MainLayout.
builder.Services.AddMudServices();

// Shared plumbing.
builder.Services.AddSingleton<ServerIdentity>();
builder.Services.AddKlippyData(builder.Configuration);

// Feature slices. Each one registers everything it needs; nothing here knows their internals.
// Accounts comes first: it owns the cookie scheme the config UI authenticates with, and
// the device-to-account ownership the link's routing and the clipboard both read.
builder.Services.AddAccountsFeature();
builder.Services.AddPairingFeature();
builder.Services.AddLinkFeature();
builder.Services.AddDiscoveryFeature();
builder.Services.AddPetStateFeature();
builder.Services.AddAudioCastFeature();
builder.Services.AddMarketFeature();
builder.Services.AddClipboardFeature();

var app = builder.Build();

// Bring the schema up to date before anything can query it.
await app.Services.GetRequiredService<DatabaseMigrator>().MigrateAsync();

// Resolved eagerly so the codec reports what it actually resolved to at startup rather
// than on the first cast. Whether Opus landed on the native or the managed path is the
// difference between zero and ~11 MB/s of allocation, and the fallback is silent.
app.Services.GetRequiredService<OpusEncoderPool>();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error", createScopeForErrors: true);
}

// Deliberately no HTTPS redirection: devices reach this over the LAN by IP address,
// and a self-signed certificate is a worse trade than plain HTTP on a home network.
// Revisit if the server is ever exposed beyond it.

app.UseStatusCodePagesWithReExecute("/not-found", createScopeForStatusCodePages: true);

// ...but not for the device API. Re-execution runs the failed request through the router
// again to render /not-found, and it keeps the original method: a DELETE that answered 404
// comes back 405, because no page handles DELETE, and a POST comes back 400, because
// antiforgery rejects a posted page carrying no token. Both tell the caller something that
// is not true, and the clipboard and market clients decide what to say from that status.
//
// Switched off per request rather than by branching the pipeline: a branch would take the
// re-execution with it, and the pages need it.
app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/api")
        && context.Features.Get<IStatusCodePagesFeature>() is { } statusCodePages)
    {
        statusCodePages.Enabled = false;
    }

    await next(context);
});
app.UseWebSockets();

// Before the antiforgery middleware, which needs to know who the caller is. Devices are
// unaffected either way: they authenticate per request with a bearer token (see
// PairingService.AuthenticateAsync), not with this cookie.
app.UseAuthentication();
app.UseAuthorization();

app.UseAntiforgery();

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.MapDiscoveryEndpoints();
app.MapPairingEndpoints();
app.MapLinkEndpoints();
app.MapPetStateEndpoints();
app.MapAudioCastEndpoints();
app.MapMarketEndpoints();
app.MapClipboardEndpoints();

// Start before advertising: the beacon has to carry the port Kestrel actually bound,
// which is only knowable once it has.
await app.StartAsync();

var identity = app.Services.GetRequiredService<ServerIdentity>();
identity.SetHttpPort(ResolveHttpPort(app));

app.Logger.LogInformation("Klippy server '{Name}' ({ServerId}) reachable at {BaseUrl}",
    identity.Name, identity.ServerId, identity.BaseUrl);

await app.WaitForShutdownAsync();

return;

static int ResolveHttpPort(WebApplication app)
{
    var addresses = app.Services.GetRequiredService<IServer>()
        .Features.Get<IServerAddressesFeature>()?.Addresses ?? [];

    foreach (var address in addresses)
    {
        if (Uri.TryCreate(address.Replace("*", "0.0.0.0").Replace("+", "0.0.0.0"), UriKind.Absolute, out var uri)
            && uri.Scheme == Uri.UriSchemeHttp)
        {
            return uri.Port;
        }
    }

    throw new InvalidOperationException(
        "No HTTP address bound. Devices pair over plain HTTP, so at least one http:// URL is required.");
}
