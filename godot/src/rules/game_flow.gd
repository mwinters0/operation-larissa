class_name GameFlow
extends RefCounted
## What happens next in ONE player's mission: the start of a sector, the dock (pieces missing, or the lock), the supply message
## and the next sector, a lost tank (respawn), game over (the sector starts over), the finale and the closing, the Hall of Fame,
## the hints, the saves, the Options questions. `Game` (src/gameplay/game.gd, a node) is only its view.
##
## Teaches: separating the FLOW of a game from the way it is shown (as `ProblemFlow` does for one problem). This
## class knows no node, texture, font, `Input`, timer or tween, and it names no autoload either. Everything it needs from the
## outside is HANDED to it, the way `SimWorld` is handed its `run`:
##
##   run      the player's numbers: oxygen, ink, pieces, lights, the midpoint, the hints. In the game it is the `GameState` autoload;
##            a test hands over a fresh instance of the same script that is in no tree.
##   store    the roster and the Hall of Fame (`save_roster`, `add_to_hall`, `post_write_error`, the signal `write_failed`). In the
##            game it is the `SaveStore` autoload; a test hands over a small fake that counts the saves.
##   world    the playfield, called the STAGE here: it starts a sector (`begin_sector`), drives the sub into the station (`dock`),
##            sends the balloon up, makes a problem and takes the result back. `SectorWorld` is one (a node that owns a `SimWorld`
##            and a presenter); anything with the same methods and signals is another (see `STAGE_METHODS`).
##   messages the message line (`MessageQueue`, plain logic: hints and questions wait there; the view shows them).
##   view     whoever SHOWS things (see `VIEW_METHODS`): screens, the music, the end of the scene. In the game it is `Game`.
##
## HOW A WAIT WORKS. When the flow has to wait for something that is shown (the surface ship screen, a math problem, the closing
## sequence, the Hall of Fame) it asks the view and `await`s the call: the view's method comes back when the player has finished
## with the screen. A view that shows nothing comes back at once, so a whole mission can be played in a test with plain objects
## (`tests/engine/test_game_flow_machine.gd`). When the flow has to wait for the RULES (the launch, the dock, the balloon) it awaits the
## stage, which waits for the sim to count the ticks: the flow itself never counts time and never reads a clock. The stage comes back
## between two ticks (`SimWorld.sequence_over`) and hands it the dock there too (`SimWorld.after_tick`), so nothing the flow does next
## runs in the middle of a tick (docs/engine/ARCHITECTURE.md, "Nothing the owner does runs inside a tick").
##
## WHERE IT LIVES. `src/rules/`, next to `SimWorld`: this is the rules of a mission (what follows what, what costs what, what is
## saved when), and that folder is the one where "no view class in here" is one checked rule. (`ProblemFlow` lives with the problems
## because its view and its models do.) What stays autoload-coupled is only a few static lookups of DATA - `Catalog.text`,
## `Progression`, `ProblemFactory` - which are plain classes with no engine view in them.
##
## THE CAMPAIGN. What differs between one game and another - the order of the sectors and where the game ends
## (`Progression.next_progress`, `Campaign.is_finale`), the closing scene (`view.show_closing(campaign, ...)`), the name of the game in
## the customised-game notice - is asked of `campaign`, the `Campaign` the player is in (`PlayerProfile.campaign()`, set by `enter`).
## The flow itself knows no sector number: a campaign of 8 sectors and a finale numbered 60 plays through the same steps. (The song and
## the supply message of a sector are the view's: they find the sector's campaign by the sector number.)

## An Options question was answered: the setting is changed in the player's record. The view shows the check mark and tells the
## sound system (`Audio` switches buses on `&"sound"` and `&"voice"`, the song on `&"music"`).
signal option_changed(option: StringName, enabled: bool)

## What the flow calls on its view. Those that are awaited come back when the player is done with what they show.
## show_pieces_missing(missing: int)                      the surface ship says N pieces are still out there; until Enter
## show_supply_message(completed_sector: int)             the mission control message; until Enter (or 20 s after the speech)
## show_problem(problem: ProblemInstance, calculator_allowed: bool, after_prompt: Callable) -> ProblemSession
##                                                        the problem screen; `after_prompt` is called once the prompt is drawn
## show_closing(campaign: Campaign, sub_at: Vector2i, sub_cell: int)   the closing sequence of the finished game: the scene `campaign.closing_scene`
## show_hall_of_fame()                                    the Hall of Fame
## play_sector_music(sector: int), stop_music()           the song of a sector, silence
## go_to_sign_in(), quit_game()                           the end of the scene, the end of the program
const VIEW_METHODS: Array[StringName] = [&"show_pieces_missing", &"show_supply_message", &"show_problem", &"show_closing",
		&"show_hall_of_fame", &"play_sector_music", &"stop_music", &"go_to_sign_in", &"quit_game"]

## What the flow needs from the stage (`SectorWorld`): the methods below, the reads `sector_index`, `sector` (its `pieces`) and
## `sim` (the sub's `original_position()` and `cell`, for the closing), and the signals `problem_pending(slot)`,
## `problem_requested(slot)`, `dock_reached` and `finale_reached`.
const STAGE_METHODS: Array[StringName] = [&"begin_sector", &"dock", &"send_balloon", &"make_problem", &"problem_resolved",
		&"stop_flight"]

## The exit questions start on "No" (button 1): the original's dialog record names "No" as the default button.
const YES_NO_DEFAULT_NO := 1
## Options > ...: title and question strings of the Yes / No dialogs (`MenuNewPlayerHints` 0x42bc56, `MenuSoundEffects` 0x42bcdf,
## `MenuMusic` 0x42bd56, `MenuVoice` 0x42bdcd): [title text, question text] (names of the `text` kind).
const OPTION_QUESTIONS := {
	&"hints": [&"question_hints_title", &"question_hints_text"],
	&"sound": [&"question_sound_title", &"question_sound_text"],
	&"music": [&"question_music_title", &"question_music_text"],
	&"voice": [&"question_voice_title", &"question_voice_text"],
}

var run: Object
var store: Object
var messages: MessageQueue
## The playfield (see above). Set before `enter`.
var world: Object
## Whoever shows things (see above). Set before `enter`.
var view: Object

var profile: PlayerProfile
## The campaign being played: the player's own (`PlayerProfile.campaign()`), or, in free play, the one the chosen sector belongs to. Set by
## `enter`; a test may replace it afterwards to run the same steps through another campaign.
var campaign: Campaign
## True when no player was chosen (the scene was started directly): nothing is saved.
var free_play: bool = false
## True while a scripted sequence (docking, a respawn) runs; the dock and loss handlers wait.
var busy: bool = false
## Runs a call "a little later, outside the signal that asked for it". The default is `call_deferred` (a lost tank can be announced
## from inside a physics callback, where the playfield must not be rebuilt); a test collects the calls and runs them itself.
var defer_call: Callable = func(action: Callable) -> void: action.call_deferred()

# The signals the flow listens to, so that `leave` can let go of them: the autoloads outlive the scene.
var _connections: Array = []


func _init(game_run: Object, game_store: Object, message_queue: MessageQueue) -> void:
	run = game_run
	store = game_store
	messages = message_queue


# --- coming and going -------------------------------------------------------------------------

## The mission begins: the player comes from `run.profile` (the sign-in screen set it). Started on its own (F6, or a test) there is
## none, and the flow plays "free play" with a throw-away player that is never saved, at sector `free_play_sector`. The level of free
## play is the throw-away player's own choice (`customized`, `edu_level`): the run reads its level from the player
## (`refresh_edu_level`) at every sector start, respawn and restart, so the choice is made there and not on the run's copy.
func enter(free_play_sector: int, free_play_edu_level: int) -> void:
	free_play = run.profile == null
	if free_play:
		var demo := PlayerProfile.new_player("Free play", PlayerProfile.Game.VOYAGER)
		demo.progress = free_play_sector * 2
		demo.customized = true
		demo.edu_level = free_play_edu_level
		run.apply_profile(demo)
	else:
		run.apply_profile(run.profile)
	profile = run.profile
	campaign = profile.campaign()
	if free_play and Catalog.campaign_of_sector(free_play_sector) != null:     # (any sector can be tried: its own campaign decides the finale)
		campaign = Catalog.campaign_of_sector(free_play_sector)
	if free_play:
		run.use_campaign_hooks(campaign)                     # (and the mods it declares: a run with a player resolved them when it began, `GameState.begin_run`)
	_listen(store.write_failed, _on_write_failed)
	_listen(world.problem_pending, _on_problem_pending)
	_listen(world.problem_requested, open_problem)
	_listen(world.dock_reached, on_dock_reached)
	_listen(world.finale_reached, play_closing)
	_listen(run.tank_lost, _on_tank_lost)
	_listen(run.game_over, _on_game_over)
	_listen(run.oxygen_changed, _on_oxygen_changed)
	_listen(run.piece_collected, _on_piece_collected)
	_listen(run.midpoint_changed, _on_midpoint_changed)


## The first sector, and the very first hint (how to steer). Returns when the sub is under control.
func begin_mission() -> void:
	await begin_sector(profile.sector(), run.past_midpoint)
	show_hint(HintSystem.CONTROLS)


## The scene is going away: stop listening (the autoloads live on) and forget the throw-away player of free play.
func leave() -> void:
	for pair: Array in _connections:
		var source: Signal = pair[0]
		if is_instance_valid(source.get_object()) and source.is_connected(pair[1]):
			source.disconnect(pair[1])
	_connections.clear()
	if free_play and run.profile == profile:
		run.profile = null                                # the throw-away player must not leak into the next scene


func _listen(source: Signal, handler: Callable) -> void:
	source.connect(handler)
	_connections.append([source, handler])


# --- starting a sector ------------------------------------------------------------------------

## Starts sector `index` (the start of a sector, a resume from a save, or a respawn): screen 6 at the respawn point once the
## midpoint is passed, otherwise the launch from the supply station. The run is told the sector first (`set_sector`): a save written
## while the sector had another number of pieces starts its collecting over there, midpoint included, so a start past the midpoint
## (`past_midpoint`, the run's flag as the caller read it) holds only while the run is still past it.
func begin_sector(index: int, past_midpoint: bool) -> void:
	run.refresh_edu_level()
	run.set_sector(index, Catalog.sector(index).pieces.size())
	view.play_sector_music(index)
	await world.begin_sector(index, past_midpoint and run.past_midpoint)


## (Re)starts the sector's song. The original does this at the start of a sector and after a problem or a message that stopped it,
## but NOT when the sub merely changes screens (the song plays on across screens).
func _play_sector_music() -> void:
	view.play_sector_music(world.sector_index)


# --- hints -------------------------------------------------------------------------------------

## Shows new-player hint `id` the first time it is asked for (and only while hints are on).
func show_hint(id: int) -> void:
	if not run.hints.take(id):
		return
	var text := HintSystem.text_for(id)
	if text.is_empty():
		return
	messages.post(Catalog.text(&"new_player_hint_title"), text)
	save_progress()                                       # the mask of seen hints is part of the player's record


func _on_oxygen_changed(_tanks: int, oxygen: int) -> void:
	if oxygen == 1:
		show_hint(HintSystem.LOW_OXYGEN)


func _on_piece_collected(index: int) -> void:
	if index == 0:
		show_hint(HintSystem.DATA_CANISTER)


func _on_problem_pending(_slot: int) -> void:
	show_hint(HintSystem.BLINKING_LIGHT)


## Which hints belong to this problem (`DoMathProblem` (0x423629), after the prompt is drawn): not for the lock (0) or the ballast
## panels (28, 29); else hint 3 (type the answer) when the player's calculator option is off, hint 4 (calculator) when it is on, and
## hint 6 (fractions) at EduLevel 1 or 3 (the levels that use fractions).
func show_problem_hints(problem: ProblemInstance) -> void:
	var type_id := problem.type.id
	if type_id == 0 or type_id == 28 or type_id == 29:
		return
	show_hint(HintSystem.CALCULATOR if profile.calculator_on else HintSystem.TYPE_ANSWER)
	if run.edu_level == 1 or run.edu_level == 3:
		show_hint(HintSystem.FRACTIONS)


# --- messages and saving --------------------------------------------------------------------

## "This Voyager game has been customized. EDUCATIONAL LEVEL: ... CALCULATOR: ..." (strings 11195-11206). The original shows it on
## the sign-in screen (`CustomizedGameNotice` 0x42f4be, called from `SignInScreenLoop` after the Start button's 36-tick pressed
## look), so `SignIn` posts it; the text is built here, next to the other customization code.
static func customized_notice_text(player: PlayerProfile) -> String:
	return Catalog.text(&"customized_intro") + player.campaign().display_title() + Catalog.text(&"customized_game_suffix") \
			+ Catalog.text(StringName("customized_level_%d" % player.edu_level)).strip_edges(true, false) + Catalog.text(&"customized_calculator_heading") \
			+ (Catalog.text(&"customized_calculator_on") if player.calculator_on else Catalog.text(&"customized_calculator_off")).strip_edges(true, false) + Catalog.text(&"customized_footer")


## A save did not reach the disk: the "Write Error" dialog (`write_users_dat` 0x41bce2); the game goes on.
func _on_write_failed(_path: String) -> void:
	store.post_write_error(messages)


## Copies the running game into the player's record and writes the roster. (Not in free play.)
func save_progress() -> bool:
	if free_play:
		return false
	run.capture_profile()
	return store.save_roster()


## Escape / File > Exit: "Do you want to exit the program?" (original strings 11130 / 11132). Saves, then quits.
func ask_to_exit() -> void:
	if messages.is_open():
		return
	var message := messages.post(Catalog.text(&"exit_title"), Catalog.text(&"exit_text").replace("\r", "\n"),
			PackedStringArray(["Yes", "No"]), true, 0, YES_NO_DEFAULT_NO)
	var choice: int = await message.closed
	if choice == 0:
		save_progress()
		view.quit_game()


## File > Return to Sign In (strings 11126 / 11127, `MenuReturnToSignInSave` 0x42b914): "Only those sectors you have completed will
## be saved. Do you want to return to Sign In?", then save and go back to the player list. (The wording of 11128 / 11129 belongs
## to Math Practice's menu, `MenuReturnToSignIn` 0x42b98f.)
func ask_to_return_to_sign_in() -> void:
	if messages.is_open():
		return
	var message := messages.post(Catalog.text(&"return_to_sign_in_title"), Catalog.text(&"return_to_sign_in_text").replace("\r", "\n"),
			PackedStringArray(["Yes", "No"]), true, 0, YES_NO_DEFAULT_NO)
	var choice: int = await message.closed
	if choice == 0:
		leave_to_sign_in()


func leave_to_sign_in() -> void:
	save_progress()
	view.go_to_sign_in()


# --- the menu --------------------------------------------------------------------------------

## Options > New Player Hints / Sound Effects / Music / Voice: the original asks "Do you want the Music on?" with Yes / No (the button
## that would CHANGE the setting is the default one, so Enter toggles it); Escape leaves the setting alone. Yes on Music starts the
## song again from its beginning, Yes on Hints also makes every hint new.
func ask_option(option: StringName) -> void:
	if messages.is_open() or not OPTION_QUESTIONS.has(option):
		return
	var texts: Array = OPTION_QUESTIONS[option]
	var message := messages.post(Catalog.text(texts[0]), Catalog.text(texts[1]).replace("\r", "\n"),
			PackedStringArray(["Yes", "No"]), true, 0, 1 if option_is_on(option) else 0, -1)
	var choice: int = await message.closed
	if choice < 0:
		return
	set_option(option, choice == 0)


func option_is_on(option: StringName) -> bool:
	match option:
		&"hints":
			return run.hints.enabled
		&"sound":
			return profile.sound_on
		&"music":
			return profile.music_on
		&"voice":
			return profile.voice_on
	return false


## Changes a setting of the player and saves it. (`option_changed` tells the view; the buses and the song are its business.)
func set_option(option: StringName, enabled: bool) -> void:
	match option:
		&"hints":
			run.hints.enabled = enabled
			if enabled:
				run.hints.reset()                         # (0x42bc56: Yes sets the mask of unseen hints to 0xffff)
		&"sound":
			profile.sound_on = enabled
		&"music":
			profile.music_on = enabled
		&"voice":
			profile.voice_on = enabled
	option_changed.emit(option, enabled)
	save_progress()


## Done in the customization dialog: a change of level or calculator marks the game "customized" ("Cust" on the console, "(c)" in the
## Hall of Fame).
func customize(level: int, calculator: bool) -> void:
	if level != profile.effective_edu_level() or calculator != profile.calculator_on:
		profile.customized = true
		run.customized = true
	profile.edu_level = level
	profile.calculator_on = calculator
	run.refresh_edu_level()
	save_progress()


func _on_midpoint_changed(_past: bool) -> void:
	save_progress()                                       # the original saves the flag with the progress


# --- math problems ----------------------------------------------------------------------------

## Shows the math problem of trigger `slot` and tells the world how it went.
func open_problem(slot: int) -> void:
	var problem: ProblemInstance = world.make_problem(slot)
	var session := await run_problem(problem)
	world.problem_resolved(slot, session)
	_play_sector_music()                                  # the music was stopped while the problem was up


## Puts the problem on screen and returns the finished session. Any "air ran out" that happened inside is announced only after this
## returns to the caller (`hold_losses` of the run, which the problem screen takes).
func run_problem(problem: ProblemInstance) -> ProblemSession:
	view.stop_music()                                     # silence during a math problem (the original stops the song)
	return await view.show_problem(problem, profile.calculator_on, show_problem_hints.bind(problem))


# --- the supply station -----------------------------------------------------------------------

## The sub is at the dock. Pieces missing: the ship says how many. Otherwise: the lock, and if it opens, the sector is done.
func on_dock_reached() -> void:
	if busy:
		return
	view.stop_music()                                     # the song stops at the dock (and starts again if the sub must go on)
	var missing := Progression.pieces_missing(run.pieces_mask, world.sector.pieces.size())
	if missing > 0:
		busy = true
		run.set_message_light(true, false)                # DisplayShipMathIcon(1, 0) 0x419ec3: the ship's light and sound 0x2f
		await view.show_pieces_missing(missing)           # PiecesNotCollectedMessage 0x432ac4
		run.set_message_light(false, false)               # DisplayShipMathIcon(0, 0) after the message
		_play_sector_music()
		busy = false
		return
	busy = true
	var level: int = run.edu_level
	var problem := ProblemFactory.make(0, level)
	while problem == null and level > 0:                  # (the lock exists at every level, but be safe)
		level -= 1
		problem = ProblemFactory.make(0, level)
	var session := await run_problem(problem)
	if session.oxygen_code != OxygenModel.OK:
		busy = false                                      # the lost tank is handled by `_on_tank_lost`
		return
	await complete_sector()
	busy = false


## The lock is open: the creatures start over, drive in (to the sector's song), show the surface ship message (silent music), send the
## pieces up (the song again), refill, start the next sector (its own song). `DoAction` 0x417ffc, 0x4181fb-0x41824c: after
## `DoMathProblem(0)` returns 0 it reloads the sector (`FreeSectorResources` 0x433ec2, `LoadSectorResources` 0x433d13: the creature
## records are read again) before `EnterSupplyStation` 0x432b96 and `LaunchBalloon` 0x432eae, and returns 0; only then does `Main`
## (0x427bb4) refill (`UpdateOxygen(3)`, `UpdateInkPelletUses(0x15)`, `ProbesPickedUp` = 0) and call `IncrementSector` (0x42e201).
func complete_sector() -> void:
	var finished_sector := profile.sector()
	world.sim.reload_creatures()                          # LoadSectorResources 0x433d13: every creature from its start record
	_play_sector_music()                                  # PlaySectorMusic(1) 0x41822d: the song plays while the sub docks
	await world.dock()
	view.stop_music()                                     # StopSectorMusic 0x418238: silence for the supply message
	run.begin_sector()                                    # the pieces are "transported to the surface ship", the midpoint is forgotten
	profile.progress = Progression.next_progress(profile.progress, campaign)
	run.refresh_edu_level()
	save_progress()
	await view.show_supply_message(finished_sector)
	_play_sector_music()                                  # PlaySectorMusic(1) 0x41824c: the finished sector's song, for LaunchBalloon
	await world.send_balloon()
	run.update_oxygen(3)                                  # `Main` after DoAction returned 0: at least 2 tanks and a full tank
	run.refill_ink()
	save_progress()                                       # (the record keeps the refill, as `IncrementSector`'s UpdateRosterData does)
	if campaign.is_finale(finished_sector):
		await finish_game()                               # docking in a finale (screen 11 is out of reach there): IncrementSector returns 1, no closing
		return
	await begin_sector(profile.sector(), false)           # (after sector 14 / 29 this is the finale sector 30 / 31)


## The closing sequence: the end of the game (the Voyager one in sector 30, the Expert one in 31). The sub stops, the campaign's closing
## sequence plays on top of the sector, and then the player goes into the Hall of Fame.
func play_closing() -> void:
	busy = true
	var sub_at: Vector2i = world.sim.sub.original_position()
	var sub_cell: int = world.sim.sub.cell
	world.stop_flight()                                   # the closing scenes draw their own sub
	view.stop_music()
	await view.show_closing(campaign, sub_at, sub_cell)
	await finish_game()
	busy = false


## The game is won (DESIGN 2 item 4): into the Hall of Fame, and back to sign-in.
func finish_game() -> void:
	if free_play:
		messages.post("Operation Neptune", "That was the end of the free play.")
		return
	store.add_to_hall(profile)
	save_progress()
	await view.show_hall_of_fame()
	view.go_to_sign_in()


# --- losing air -------------------------------------------------------------------------------

## The air ran out and a spare tank takes over (result code 1): a fresh tank, back to screen 6 past the midpoint or to the station
## before it. The pieces stay collected. (Deferred: this signal can arrive from inside a physics callback, where the playfield must
## not be rebuilt.) When a creature took the last air, the sub has already dissolved away by now (`SimWorld._apply_creature_damage`
## and `SectorWorld._on_sub_damaged`, `RedrawFrameAfterTankLoss` 0x418bcb): the signal is held back until the dissolve is over, the
## way the original only returns to its loop (and respawns, `UpdateOxygen(4)`) after `dissolve` (0x414f81) has finished.
func _on_tank_lost(_code: int) -> void:
	defer_call.call(respawn)


func respawn() -> void:
	busy = true
	run.respawn()
	save_progress()
	await begin_sector(world.sector_index, run.past_midpoint)
	busy = false


## No tank left (result code 2): the sector starts over with full ink and nothing collected; `tries` goes up.
func _on_game_over() -> void:
	defer_call.call(restart)


func restart() -> void:
	busy = true
	run.restart_sector()
	save_progress()
	var message := messages.post("Operation Neptune", "You have run out of oxygen and spare tanks.\nThe sector starts over.")
	await message.closed
	await begin_sector(world.sector_index, false)
	busy = false
