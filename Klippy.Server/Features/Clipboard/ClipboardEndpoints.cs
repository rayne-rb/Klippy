using Klippy.Server.Common;
using Klippy.Server.Features.Link;
using Klippy.Server.Features.Pairing;
using Klippy.Shared.Clipboard;
using Klippy.Shared.Link;

namespace Klippy.Server.Features.Clipboard;

/// <summary>
/// The clipboard's whole content path. Everything a device reads or writes goes through
/// here rather than over the Link, because both directions want a real answer — it was
/// too big, it was a duplicate, that entry is not yours — and because the Link archives
/// what crosses it.
/// </summary>
public static class ClipboardEndpoints
{
    public static IEndpointRouteBuilder MapClipboardEndpoints(this IEndpointRouteBuilder routes)
    {
        var group = routes.MapGroup("/api/clipboard").WithTags("Clipboard");

        // The board: this account's entries and everything shared server-wide. Never
        // anonymous, unlike the market's listings — a clipboard is not a shop window.
        group.MapGet("/", async (
            HttpContext context,
            PairingService pairing,
            ClipboardService clipboard,
            CancellationToken ct) =>
        {
            var (device, refusal) = await ResolveAsync(context, pairing, ct);
            if (refusal is not null)
            {
                return refusal;
            }

            if (device!.OwnerUserId is not { } owner)
            {
                // Unclaimed: a group of one with nothing in it. An empty board rather
                // than an error, so a device that has just paired shows something sane
                // while it waits to be approved.
                return Results.Ok(Array.Empty<ClipboardEntryView>());
            }

            var rows = await clipboard.ListForAccountAsync(owner, ct);
            return Results.Ok(rows.Select(ToView).ToList());
        });

        group.MapPost("/", async (
            HttpContext context,
            ClipboardTextRequest input,
            PairingService pairing,
            ClipboardService clipboard,
            CancellationToken ct) =>
        {
            var (device, refusal) = await ResolveAsync(context, pairing, ct);
            if (refusal is not null)
            {
                return refusal;
            }

            var result = await clipboard.AddTextAsync(device!, input.Text, input.Visibility, ct);
            return Answer(result);
        });

        // Raw PNG rather than multipart: the Companion posts this from GDScript, where a
        // raw body is a PackedByteArray and multipart is a boundary to assemble by hand.
        group.MapPost("/image", async (
            HttpContext context,
            PairingService pairing,
            ClipboardService clipboard,
            CancellationToken ct) =>
        {
            var (device, refusal) = await ResolveAsync(context, pairing, ct);
            if (refusal is not null)
            {
                return refusal;
            }

            // Refuse on the declared length before reading a byte of it.
            if (context.Request.ContentLength > ClipboardLimits.MaxImageBytes)
            {
                return Results.BadRequest(new { error = "That image is too large." });
            }

            using var buffer = new MemoryStream();
            await context.Request.Body.CopyToAsync(buffer, ct);

            var visibility = context.Request.Query["visibility"].FirstOrDefault();
            var result = await clipboard.AddImageAsync(device!, buffer.ToArray(), visibility, ct);
            return Answer(result);
        });

        // The content itself, the only place it is ever handed out.
        group.MapGet("/{entryId:guid}/content", async (
            HttpContext context,
            Guid entryId,
            PairingService pairing,
            ClipboardService clipboard,
            CancellationToken ct) =>
        {
            var (device, refusal) = await ResolveAsync(context, pairing, ct);
            if (refusal is not null)
            {
                return refusal;
            }

            var entry = await clipboard.FindAsync(entryId, ct);

            // One answer for "no such entry" and "not yours": telling them apart would
            // let anyone confirm what other accounts have copied by guessing ids.
            if (entry is null || !ClipboardService.CanRead(entry, device!.OwnerUserId))
            {
                return Results.NotFound();
            }

            return entry.ContentType == ClipboardContentTypes.Text
                ? Results.Text(entry.ContentText ?? string.Empty)
                : Results.Bytes(entry.ContentBlob ?? [], entry.ContentType);
        });

        group.MapDelete("/{entryId:guid}", async (
            HttpContext context,
            Guid entryId,
            PairingService pairing,
            ClipboardService clipboard,
            CancellationToken ct) =>
        {
            var (device, refusal) = await ResolveAsync(context, pairing, ct);
            if (refusal is not null)
            {
                return refusal;
            }

            // Only out of your own account: a server-wide entry stays readable to you,
            // but it is still the copier's to withdraw.
            return device!.OwnerUserId is { } owner && await clipboard.DeleteAsync(entryId, owner, ct)
                ? Results.Ok(new { deleted = true })
                : Results.NotFound();
        });

        // "Put this on that device's clipboard." The entry id travels; the content does
        // not — the target fetches it with its own token, so this cannot be used to hand
        // a device something it could not have read for itself.
        group.MapPost("/{entryId:guid}/apply", async (
            HttpContext context,
            Guid entryId,
            ClipboardApplyRequest input,
            PairingService pairing,
            ClipboardService clipboard,
            LinkRegistry registry,
            CancellationToken ct) =>
        {
            var (device, refusal) = await ResolveAsync(context, pairing, ct);
            if (refusal is not null)
            {
                return refusal;
            }

            if (!Guid.TryParse(input.TargetDeviceId, out var target))
            {
                return Results.BadRequest(new { error = "targetDeviceId is not a device id." });
            }

            var entry = await clipboard.FindAsync(entryId, ct);
            if (entry is null || !ClipboardService.CanRead(entry, device!.OwnerUserId))
            {
                return Results.NotFound();
            }

            var envelope = LinkEnvelope.Create(
                KlippyEvents.ClipboardApply,
                new ClipboardApplyPayload { EntryId = entryId.ToString() },
                source: device!.DeviceId.ToString(),
                target: target.ToString());

            // Straight to the device rather than published: this needs none of what the
            // dispatcher adds, and TrySendWithinGroup is what keeps it from reaching a
            // device in somebody else's account.
            return registry.TrySendWithinGroup(target, device!.OwnerUserId, envelope)
                ? Results.Ok(new { sent = true })
                : Results.Conflict(new { error = "That device is not connected." });
        });

        return routes;
    }

    /// <summary>
    /// The caller, or the answer to give them instead. Every endpoint here starts with it,
    /// so the one refusal they share is written once.
    /// </summary>
    private static async Task<(PairedDeviceRow? Device, IResult? Refusal)> ResolveAsync(
        HttpContext context, PairingService pairing, CancellationToken ct)
    {
        var device = await pairing.AuthenticateAsync(BearerToken.Read(context), ct);

        return device is null ? (null, Results.Unauthorized()) : (device, null);
    }

    private static IResult Answer(ClipboardService.AddResult result) =>
        result switch
        {
            { Error: { } error } => Results.BadRequest(new { error }),
            // Nothing new, and nothing wrong: the device polled a clipboard that had not
            // changed. Saying so lets it tell that apart from a failure.
            { WasDuplicate: true } => Results.Ok(new { duplicate = true }),
            _ => Results.Ok(new { entryId = result.Entry!.EntryId }),
        };

    private static ClipboardEntryView ToView(ClipboardListRow row) => new()
    {
        EntryId = row.EntryId.ToString(),
        SourceDeviceId = row.SourceDeviceId.ToString(),
        SourceDeviceName = row.SourceDeviceName,
        ContentType = row.ContentType,
        ByteSize = row.ByteSize,
        Visibility = row.Visibility,
        CopiedAt = row.CopiedAt,
        IsMine = row.IsMine,
        OwnerName = row.OwnerUsername,
        Preview = row.Preview,
    };
}

/// <summary>Body of a "I copied this text" request.</summary>
public sealed record ClipboardTextRequest
{
    public required string Text { get; init; }

    /// <summary>See <see cref="ClipboardVisibility"/>. Anything unrecognised is treated as group-only.</summary>
    public string? Visibility { get; init; }
}

/// <summary>Body of a "put this on that device" request.</summary>
public sealed record ClipboardApplyRequest
{
    public required string TargetDeviceId { get; init; }
}
