class_name FoodDef
extends Resource

## One entry in [FoodCatalog]: what a food looks like and how much it feeds
## Klippy. New food kinds are added by giving [FoodCatalog] another one of
## these rather than teaching the food/spawning code a new special case.

@export var id: String
@export var display_name: String
@export var texture: Texture2D
@export var feed_amount: float = 5.0

## How long, in seconds, eating this food buffs Klippy for. 0 means no buff —
## the food just feeds. A repeat feeding refreshes the timer rather than
## stacking it.
@export var buff_duration: float = 0.0
## Replaces [constant PetBody.BOUNCE_DAMPING] for the buff's duration.
## Negative means "leave bounciness alone".
@export var bounce_damping_override: float = -1.0
## Whether impacts land no throw damage for the buff's duration.
@export var damage_immune: bool = false
