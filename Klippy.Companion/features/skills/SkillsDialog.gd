class_name SkillsDialog
extends Window

## What Klippy can be put to work on, beyond living on the desktop.
##
## One card per skill (see [SkillCard]), each looking after itself — the window only
## decides what is in the list and in what order. A new skill is a script in this
## folder and a line in [method _ready].

func _ready() -> void:
	var vbox := RockyTheme.setup_window(self, "Skills", 380)

	var intro := Label.new()
	intro.text = "Things Klippy can do with the rest of your setup."
	intro.add_theme_color_override("font_color", RockyTheme.MUTED)
	intro.add_theme_font_size_override("font_size", 12)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(SkillCard.TEXT_WIDTH, 0)
	vbox.add_child(intro)

	vbox.add_child(AudioRelaySkill.new())
