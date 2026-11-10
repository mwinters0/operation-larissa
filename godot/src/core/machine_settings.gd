class_name MachineSettings
extends RefCounted
## Settings that belong to the machine, not to a player: the options the original keeps in its `ONWINCD` INI file.
##
## Teaches: a `ConfigFile` (Godot's INI-like format, in `user://`) read once into `static var`s that any script can
## ask without a node or an autoload, and the rule "unknown, missing or damaged means the default". The music set
## and the volumes (`Audio.save_settings`) live in the same kind of file; a player's own choices (sound on / off ...)
## are in the player's save instead.
##
## `Collision` (`ReadCollisionSetting` 0x4147ac, called by `StartupChecks`): the original reads `[ONWINCD] Collision`
## (default "TRUE") and stores `value != "FALSE"` in a global (0x446590). That global is read in ONE place, `update_animals`
## (0x41ed0c), where a creature that touches the sub may only become "the one that hurts" while it is 1. With it off the creatures
## are still touched, still run their contact scripts and can still be inked, but nothing hurts the sub and Zoom
## brings no tank. The Options menu has no entry for it: you edit the INI. Here you edit `machine_settings.cfg`
## in the `user://` folder:
##
##     [ONWINCD]
##     Collision=false
##

const SETTINGS_PATH := "user://machine_settings.cfg"
const SECTION := "ONWINCD"
const COLLISION_KEY := "Collision"

## Where `load_settings` / `save_settings` read and write. Tests point it at a scratch file.
static var settings_path: String = SETTINGS_PATH
## Does touching a creature hurt (and does Zoom's tank count)? On unless the file says it is off.
static var collision_enabled: bool = true


static func _static_init() -> void:
	load_settings()


## Reads the file if there is one; a missing or damaged file leaves the defaults.
static func load_settings() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)                       # on an error the config stays empty: every get_value gives its default
	collision_enabled = is_enabled(config.get_value(SECTION, COLLISION_KEY, true))


static func save_settings() -> Error:
	var config := ConfigFile.new()
	config.load(settings_path)                       # keep entries this version does not know
	config.set_value(SECTION, COLLISION_KEY, collision_enabled)
	if config.has_section("packs"):
		config.erase_section("packs")                # (the list of switched-on packs of an earlier version: the game now uses one pack and its chain, `Packs`)
	return config.save(settings_path)


## The original's test is `lstrcmpA(value, "FALSE") != 0`: only the exact word FALSE switches it off. A boolean
## `false` (what `save_settings` writes) does too, and so does the text "FALSE"; anything else leaves it on.
static func is_enabled(value: Variant) -> bool:
	if value is bool:
		return value
	return not (value is String and value == "FALSE")
