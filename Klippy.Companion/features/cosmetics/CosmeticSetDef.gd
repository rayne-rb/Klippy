class_name CosmeticSetDef
extends Resource

## One entry in [CosmeticCatalog]: a full, ready-to-apply look for Klippy. New
## presets are added by giving [CosmeticCatalog] another one of these rather
## than teaching the apply code a new special case.

@export var id: String
@export var display_name: String
@export var body_texture: Texture2D
@export var expression_texture: Texture2D
@export var left_eye_texture: Texture2D
@export var right_eye_texture: Texture2D
@export var left_pupil_texture: Texture2D
@export var right_pupil_texture: Texture2D
