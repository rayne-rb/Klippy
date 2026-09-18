using Klippy.Server.Features.Link;
using Klippy.Shared.Link;

namespace Klippy.Server.Features.AudioCast;

/// <summary>
/// Publishes <c>audio.cast.state</c> whenever the cast set changes.
///
/// Kept separate from the event handler because the set changes for reasons no handler
/// sees: a first hello arriving, a listener's keepalive lapsing, the server shutting
/// down. Hanging this off the one <see cref="AudioCastSessions.Changed"/> event means
/// every one of those is announced without each mutation site having to remember to.
///
/// Unlike the offer, this carries no key, so it is published normally — persisted and
/// fanned out like any other state event. Not to everyone, though: which of your phones
/// is playing your PC's audio is your business, so it goes out once per account, each
/// one seeing only its own listeners.
/// </summary>
public sealed class AudioCastStateBroadcaster(
    AudioCastSessions sessions,
    LinkRegistry registry,
    IEventPublisher publisher,
    ILogger<AudioCastStateBroadcaster> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        sessions.Changed += OnChanged;
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        sessions.Changed -= OnChanged;
        return Task.CompletedTask;
    }

    /// <summary>
    /// Fire and forget: the event is raised from whichever thread changed the sessions —
    /// a UDP receive loop, a sweep timer — and none of them should be made to wait on a
    /// database write and a fan-out.
    /// </summary>
    private void OnChanged() => _ = PublishAsync();

    private async Task PublishAsync()
    {
        try
        {
            foreach (var owner in registry.ConnectedGroups())
            {
                var snapshot = sessions.Snapshot(registry.DeviceIdsInGroup(owner));

                await publisher.PublishToGroupAsync(
                    owner, LinkEnvelope.Create(KlippyEvents.AudioCastState, snapshot));
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Could not publish the audio cast state");
        }
    }
}
