using Klippy.Server.Common;
using Klippy.Server.Components;
using Klippy.Server.Data;
using Klippy.Server.Features.AudioCast;
using Klippy.Server.Features.Discovery;
using Klippy.Server.Features.Link;
using Klippy.Server.Features.Pairing;
using Klippy.Server.Features.PetState;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using MudBlazor.Services;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRazorComponents()
    .AddInteractiveServerComponents();

// Dialogs, snackbars and popovers are served by providers in MainLayout.
builder.Services.AddMudServices();

// Shared plumbing.
builder.Services.AddSingleton<ServerIdentity>();
builder.Services.AddKlippyData(builder.Configuration);

// Feature slices. Each one registers everything it needs; nothing here knows their internals.
builder.Services.AddPairingFeature();
builder.Services.AddLinkFeature();
builder.Services.AddDiscoveryFeature();
builder.Services.AddPetStateFeature();
builder.Services.AddAudioCastFeature();

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
app.UseWebSockets();
app.UseAntiforgery();

app.MapStaticAssets();
app.MapRazorComponents<App>()
    .AddInteractiveServerRenderMode();

app.MapDiscoveryEndpoints();
app.MapPairingEndpoints();
app.MapLinkEndpoints();
app.MapPetStateEndpoints();
app.MapAudioCastEndpoints();

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
