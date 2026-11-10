class_name SurfaceShipScreen
extends Control
## The surface ship's screen: what the original shows for the mission control message after a sector and for the
## "pieces not collected" message at the end station. Both draw the same picture and differ only in the text.
##
## Teaches: a screen that takes data (`show_supply_message`, `show_pieces_missing`) and answers with one signal
## (`finished`); the problem screen's picture reused through `ProblemScreenLayout`; a wait that is COUNTED IN TICKS (a `TickMeter`,
## not a `Timer`: its length is a number of the original's) and starts only when the speech is over. The speech is over when
## the clips' recorded lengths are (`Audio`, `VoiceIndex.durations`), so a replaced recording cannot change how long the screen stays.
##
## What the original draws (`place_surface_ship_graphic` 0x432a67, DESIGN 3.7):
##   * the problem screen's picture (`DrawProblemBackground` 0x423338: picture 1780 at (12, 30), two monitors),
##   * the surface ship, picture 1979 (logical 0x1c2), at (36, 126) on the left monitor,
##   * the title "Surface Ship" (string 11108, `DisplayMathTitle(0x22)` 0x424eea) centred over the left monitor,
##   * the text in the right monitor's box (364, 48, 238 x 202), white.
## There is no map and no progress dots (the strings "Map Screen: Zone #n" 11064-11073 are never used), and no
## "press Enter" line.
##
## Supply message (`DisplaySupplyStationMessage` 0x432e32): the text of the sector just completed (bundle 0x1c3 item
## `GetSector()`, strings 10678-10707); the speech (`PlaySupplyMessageSpeech` 0x4326c0: the jingle, then the clips) first;
## then `WaitEnterOrTicks(0x5b4)` (0x432ddb): Enter or 1460 ticks (20 s), counted from the end of the speech. Enter during
## the speech cuts it and ends the screen at once (the key stays in the input queue). Space and mouse clicks do nothing
## (no hot spot is registered); Esc cuts the speech and opens the quit dialog (`SaveAndExit`, handled by `Game`).
##
## Pieces missing (`PiecesNotCollectedMessage` 0x432ac4): the text 11212, title line included ("Surface Ship Message:" and
## the rest after the line break), written with `WriteMessageText` (0x4234c0); it waits for Enter with no time-out.

signal finished

## 1460 ticks of the original's 73 Hz timer (20 s): `surface_ship.wait_ticks` of `data/rules/durations.json` (`Durations`).
static func wait_ticks() -> int:
	return maxi(Durations.at("surface_ship.wait_ticks"), 0)

## The string "Surface Ship" (`DisplayMathTitle(0x22)`: string 0x2b42 + 0x22).
const STRING_TITLE := &"surface_ship_title"
## The pieces-not-collected text: "Surface Ship Message:\nShip's magnetometer indicates ...".
const STRING_PIECES_MISSING := &"pieces_missing_text"
## Where `place_surface_ship_graphic` puts the ship (the problem-art picture `surface_ship`, 276 x 94).
const SHIP_POSITION := Vector2(36, 126)
const SHIP_PICTURE := &"surface_ship"

## The text on the screen (also in `message_label`).
var text: String = ""

## Ticks of the supply message's 20 second wait that are left, or -1 while it is not running (before the end of the speech, and for
## the pieces-missing screen: no time-out).
var wait_ticks_left: int = -1
var _meter := TickMeter.new()
var _holding_clock: bool = false
var _closed: bool = false

@onready var background: TextureRect = %Background
@onready var ship: TextureRect = %Ship
@onready var title_label: Label = %Title
@onready var message_label: Label = %Message


func _ready() -> void:
	var layout := Catalog.screen_layout()
	background.texture = layout.background
	background.position = Vector2(layout.background_position)
	ship.texture = Assets.problem_art(SHIP_PICTURE)
	ship.position = SHIP_POSITION
	title_label.position = Vector2(layout.title_box_x, layout.title_y)
	title_label.size = Vector2(layout.title_box_width, layout.line_height)
	title_label.add_theme_color_override("font_color", layout.color(15))
	title_label.text = Catalog.text(STRING_TITLE)
	var box := Rect2(layout.message_box)
	message_label.position = box.position
	message_label.size = box.size
	message_label.add_theme_color_override("font_color", layout.color(15))
	message_label.add_theme_constant_override("line_spacing", layout.line_separation)     # (data, not the font's height)


## `DisplaySupplyStationMessage`: the message of the finished `sector`, spoken, then a 20 second wait for Enter.
func show_supply_message(sector: int) -> void:
	_hold_clock()
	text = supply_message(sector)
	message_label.text = text
	# Mission control speaks first: the "incoming transmission" sound, then the lines (the music has stopped). A campaign with no
	# recordings names no voice group (or one that does not exist): `clips` gives nothing, the jingle plays alone and the 20 seconds start
	# when it is over - the wait is counted from the lengths in the data, so a missing clip adds none.
	var cues := Catalog.voice_cues()
	var speech: Array[StringName] = [cues.jingle()]
	var campaign := Catalog.campaign_of_sector(sector)
	if campaign != null:
		speech.append_array(cues.clips(String(campaign.supply_voice_name(sector))))
	Audio.play_voice_sequence(speech)
	if Audio.is_voice_playing():
		Audio.voice_finished.connect(start_wait, CONNECT_ONE_SHOT)    # `WaitEnterOrTicks` is called after the speech
	else:
		start_wait()


## The 1460 ticks of `WaitEnterOrTicks(0x5b4)` begin.
func start_wait() -> void:
	wait_ticks_left = wait_ticks()
	_meter.reset()


## `ticks` ticks of the wait went by (`_process` feeds real time through the meter; a test gives them directly).
func advance_wait(ticks: int) -> void:
	if wait_ticks_left < 0:
		return
	wait_ticks_left -= ticks
	if wait_ticks_left <= 0:
		finish()


func _process(delta: float) -> void:
	if wait_ticks_left >= 0:
		advance_wait(_meter.feed(delta))


## `PiecesNotCollectedMessage(missing)`: the ship says how many pieces are still out there; Enter, no time-out.
func show_pieces_missing(missing: int) -> void:
	_hold_clock()
	text = pieces_missing_text(missing)
	message_label.text = text


## The mission control text for finishing `sector`: the campaign's message for that place in the game (the originals have 15 each, in
## order: bundle 0x1c3 item `GetSector()`); a text name or the campaign's own words (`Campaign.text`). Empty for a finale, where the game
## ends, and for a sector of no campaign.
static func supply_message(sector: int) -> String:
	var campaign := Catalog.campaign_of_sector(sector)
	return campaign.supply_message_text(sector).strip_edges() if campaign != null else ""


## String 11212 with the two control codes filled in the way `PiecesNotCollectedMessage` does: `\b\xD0` is the number
## (the digits of `missing`), `\b\xD1` the plural "s" (empty for one piece).
static func pieces_missing_text(missing: int) -> String:
	var raw := Catalog.text(STRING_PIECES_MISSING)
	return raw.replace("\u0008Ð", str(missing)).replace("\u0008Ñ", "" if missing == 1 else "s")


func finish() -> void:
	if _closed:
		return
	_closed = true
	Audio.stop_voice()                                    # Enter cuts the speech off
	wait_ticks_left = -1                                 # (after the speech was stopped: its end starts the wait)
	_release_clock()
	finished.emit()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		finish()
	elif key.keycode == KEY_ESCAPE:
		Audio.stop_voice()                                # the speech loop ends on Esc too (then `SaveAndExit` asks)


func _hold_clock() -> void:
	if not _holding_clock:
		_holding_clock = true
		GameClock.hold()


func _release_clock() -> void:
	if _holding_clock:
		_holding_clock = false
		GameClock.release()


func _exit_tree() -> void:
	_release_clock()
