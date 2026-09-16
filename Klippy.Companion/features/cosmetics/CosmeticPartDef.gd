class_name CosmeticPartDef
extends Resource

## One selectable option for a single cosmetic slot (body, expression, eyes,
## or pupils). [member right_texture] is only used by paired parts (eyes,
## pupils), where each side has its own hand-drawn art; single-sprite parts
## (body, expression) leave it null.

@export var id: String
@export var display_name: String
@export var texture: Texture2D
@export var right_texture: Texture2D
## Klippy level required before this option shows up in the wardrobe. 0 means
## available from the start.
@export var required_level: int = 0
