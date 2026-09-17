class_name ConsumableDef
extends Resource

## One entry in [ConsumableCatalog]: what a consumable looks like and how much
## it feeds Klippy. New consumable kinds are added by giving [ConsumableCatalog]
## another one of these rather than teaching the consumable/spawning code a new
## special case.

@export var id: String
@export var display_name: String
@export var texture: Texture2D
@export var feed_amount: float = 5.0

## How long, in seconds, eating this consumable buffs Klippy for. 0 means no
## buff — the consumable just feeds (or doesn't, if [member feed_amount] is
## also 0). A repeat feeding refreshes the timer rather than stacking it.
@export var buff_duration: float = 0.0
## Replaces [constant PetBody.BOUNCE_DAMPING] for the buff's duration.
## Negative means "leave bounciness alone".
@export var bounce_damping_override: float = -1.0
## Whether impacts land no throw damage for the buff's duration.
@export var damage_immune: bool = false
## XP and mood granted every bounce (not just damaging ones) for the buff's
## duration. 0 means that bounce reward is off.
@export var bounce_xp_reward: float = 0.0
@export var bounce_mood_reward: float = 0.0

## XP granted once, the instant this consumable is eaten — unlike the bounce
## rewards above, not tied to any buff duration. 0 means none.
@export var xp_reward: float = 0.0

## Klippy Points granted once, the instant this consumable is eaten. 0 means
## none.
@export var points_reward: int = 0
