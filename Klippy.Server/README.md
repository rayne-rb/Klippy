# Klippy.Server

The back end: it stores the data, runs the skills, and relays events between the
desktop companion and the phone.

## Getting it running

```sh
docker compose up -d          # Postgres on port 55432
dotnet run                    # migrates, then starts advertising itself
```

The schema is applied by [grate](https://erikbra.github.io/grate/) in-process at
startup, so there is no separate migration step. Open <http://localhost:5068> once it
is up.

## Slices

Each folder under `Features/` owns everything for one capability — its tables, its
data access, its endpoints, its Blazor page, and its DI registration in a
`*Registration.cs`. `Program.cs` calls those registrations and knows nothing else
about what is inside them.

| Slice | What it does |
| --- | --- |
| `Discovery` | Announces the server on the LAN over UDP multicast, and answers probes |
| `Pairing` | The approve-on-the-server handshake, device records, tokens, the Devices page |
| `Link` | The WebSocket endpoint, the connection registry, and the event dispatcher |
| `PetState` | Tracks the pet's vitals by watching the event stream — the worked example of a slice reacting to events |

`Common/` and `Data/` hold only what genuinely has no single owner: the server's
identity on the network, and the connection factory.

## Reacting to an event

Implement `IKlippyEventHandler` and register it from your slice. The dispatcher finds
it; nothing in `Link` needs to change.

```csharp
public sealed class GreetOnConnect(ILogger<GreetOnConnect> logger) : IKlippyEventHandler
{
    public bool CanHandle(string eventType) => eventType == KlippyEvents.DeviceConnected;

    public Task HandleAsync(LinkEnvelope envelope, CancellationToken ct)
    {
        logger.LogInformation("Someone turned up");
        return Task.CompletedTask;
    }
}

// in your slice's registration
services.AddScoped<IKlippyEventHandler, GreetOnConnect>();
```

A handler that throws is logged and stepped over, so it cannot cost the other
handlers their turn or stop the event reaching the devices. To emit an event of your
own, take `IEventPublisher` — but emit a *different* type than the one you handle, or
you will loop.

## Data

RepoDb over Npgsql, no EF Core. Typed helpers where the case is plain, hand-written
SQL where one statement beats a read-modify-write. Entities carry `[Map]` attributes
because the tables are snake_case.

Migrations are one-time scripts in `db/up/`, applied in filename order and
checksummed — grate reports a previously applied file that has changed rather than
quietly re-running it. Add a new file, never edit an applied one.

## A note on the setup

Two deliberate choices worth knowing about:

- **No HTTPS redirection.** Devices reach the server by IP on a home network, where a
  self-signed certificate is a worse trade than plain HTTP. Revisit if this is ever
  exposed beyond the LAN.
- **Approval is loopback-only.** The `/api/pairing/admin/*` endpoints refuse callers
  that are not on this machine, so a device on the network cannot approve itself. The
  Devices page calls the service directly and does not go through them.
