class_name FoodDef
extends Resource

## One entry in [FoodCatalog]: what a food looks like and how much it feeds
## Klippy. New food kinds are added by giving [FoodCatalog] another one of
## these rather than teaching the food/spawning code a new special case.

@export var id: String
@export var display_name: String
@export var texture: Texture2D
@export var feed_amount: float = 5.0
