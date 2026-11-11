extends Node
## The current game session's numbers (autoload "GameState"): oxygen, tanks, ink.
##
## Teaches: a singleton as the single source of truth, and the "model emits,
## views observe" pattern. Gameplay code CHANGES the state through the methods
## here; the HUD only connects to the signals and never asks "what is the value
## now?" every frame. The rules themselves live in `OxygenModel` (pure, tested).
##
## It holds what the HUD shows besides air and ink: which sector we are in, how many pieces it
## has, which message light is on, and the new-player hints (`HintSystem`).
##
## It holds the player: `apply_profile` copies a saved `PlayerProfile` in, `capture_profile` copies the
## numbers back before saving. It also holds the midpoint flag, the "respawn / game over"
## helpers, and a hold on oxygen-loss signals while a math problem is open (see `hold_losses`).
##
## It holds the collected capsule pieces (a bit mask, bit 0 = the data canister) and the
## educational level (0-3) that decides which math problems appear.
##
## LIFETIMES. Every member variable belongs to one of three nested scopes, listed in `LIFE_FIELDS`, `SECTOR_FIELDS` and
## `RUN_FIELDS` (`KEPT_FIELDS` names the ones that belong to none, with the reason). Each scope has one method that clears all of
## its fields and those of the scopes inside it, then tells the listeners through `_announce_all`: `begin_life` (a sector starts
## or the sub respawns), `begin_sector` (the sector's collecting starts over) and `begin_run` (a player signs in). A new variable
## goes into one of the lists; tests/engine/test_state_lifetimes.gd fails until it does (docs/engine/ARCHITECTURE.md, "Lifetimes
## of state").

## Oxygen or the tank count changed.
signal oxygen_changed(tanks: int, oxygen: int)
## The number of ink pellets left changed.
signal ink_changed(pellets: int)
## The air ran out but there are spare tanks: the sub respawns. `code` is the
## original's -1 or -3 (see OxygenModel).
signal tank_lost(code: int)
## The air ran out and there is no spare tank.
signal game_over
## The player tried to shoot with an empty ink supply.
signal ink_empty
## A capsule piece (or the data canister, index 0) was picked up.
signal piece_collected(index: int)

## The sub just passed the midpoint of the sector (the midpoint screen seen and everything before it collected).
signal midpoint_changed(past: bool)

## The sector (0-31) or the number of pieces in it changed, or the game became (un)customised.
signal sector_changed(sector: int)
## The set of collected pieces (or the number of pieces of the sector) changed.
signal pieces_changed
## The ship / computer message lights of the console changed.
signal message_light_changed(ship: bool, computer: bool)

## Cleared by `begin_life`: what `DoAction` (0x417ffc) sets on every entry (a sector start or a respawn).
const LIFE_FIELDS: Array[StringName] = [&"ship_light", &"computer_light", &"midpoint_reached"]
## Cleared by `begin_sector` (and `begin_run`): the collecting of one sector.
const SECTOR_FIELDS: Array[StringName] = [&"pieces_mask", &"past_midpoint"]
## Cleared by `begin_run`: the player and the numbers of the game.
const RUN_FIELDS: Array[StringName] = [
	&"profile", &"tuning", &"hooks", &"oxygen_model", &"ink", &"edu_level", &"customized", &"hints", &"sector", &"piece_total", &"_loss_holds",
	&"_held_code"]
## Member variables that no scope clears, and why.
const KEPT_FIELDS: Dictionary[StringName, String] = {}

## The values the rules of this run work on (`Tuning`): the original's until a run begins, then resolved down the pack chain by `begin_run`.
## The rules, the sub and the sub-objects read it from here (`SimWorld` hands each its section), never from the file.
var tuning: Tuning = Tuning.original()
## The rule hooks of this run (`RuleHooks`): what the mods of the player's campaign add inside the rules, resolved once by `begin_run` from the campaign's `mods`. The empty table until a run begins, for a run with no
## player (free play, the tools) and for every campaign that declares none, the originals included. The rules read it from here (`SimWorld`, `ProblemFlow`), never the mods.
var hooks: RuleHooks = RuleHooks.none()
var oxygen_model := OxygenModel.new(tuning)
var ink: int = tuning.ink_max
## Bit i is set once piece i of the current sector is collected (piece 0 = data canister).
var pieces_mask: int = 0
## Educational level 0-3: 0 whole numbers, 1 + fractions, 2 + decimals, 3 all (DESIGN 3.8).
## The player's profile sets it (`refresh_edu_level`); debug scenes set it directly.
var edu_level: int = 0
## The sector being played (-1: none yet) and how many pieces it holds (7-11, the canister counts).
var sector: int = -1
var piece_total: int = 0
## True when the player changed the educational level or calculator (the console says "Cust").
var customized: bool = false:
	set(value):
		customized = value
		sector_changed.emit(sector)
## Which console lights are on (see `light_for_slot`).
var ship_light: bool = false
var computer_light: bool = false
## New-player hints: which were shown, and the Options > New Player Hints switch.
var hints := HintSystem.new()
## The player whose game is running (null in free play and in the debug scenes).
var profile: PlayerProfile
## The original's local `MidpointReached`: the sub has been on screen 6 in this run of the sector.
var midpoint_reached: bool = false
## The saved midpoint flag (bit 0 of the progress word): after a lost tank the sub restarts on screen 6.
var past_midpoint: bool = false

# While above 0, "the air ran out" is remembered instead of announced (see `hold_losses`): one count per hold.
var _loss_holds: int = 0
var _held_code: int = OxygenModel.OK


# --- the lifetimes ---------------------------------------------------------------------

## A life of the sub begins: the start of a sector and every respawn (`SimWorld.load_sector` calls it). It mirrors the entry of
## `DoAction` (0x417ffc), which zeroes `MessageLightCountdown` (0x448688) and sets `MidpointReached` (0x448680) to
## `IsPastSectorMidpoint` (0x42e1c6): cleared before the midpoint, set past it. `DisplayBezel` (0x419eec) then draws the console with
## both message lights out (`DisplayShipMathIcon(0, 0)`). (The rest of that entry, `SubVX` / `SubVY`, `StunGunFlag` and
## `InvulnerabilityCounter`, is the sub's and the pellets': `SimWorld.load_sector` and `SubModel.place_original`.)
func begin_life() -> void:
	_clear_life()
	_announce_all()


## The sector's collecting starts over: nothing collected, the midpoint forgotten, and a new life. It mirrors what `Main`
## (0x427bb4) does after `DoAction` returns 0 (the sector is done) or 2 (game over): `ProbesPickedUp` (0x44f52c) = 0, with
## `IncrementSector` (0x42e201) or `SetPastSectorMidpoint(0)` (0x42e1e2) clearing the midpoint flag. (This is the run's half;
## `SimWorld.begin_sector` is the rules' half of starting a sector, and of a respawn.)
func begin_sector() -> void:
	var was_past := past_midpoint
	_clear_sector()
	_clear_life()
	_announce_all()
	if was_past:
		midpoint_changed.emit(false)


## A run begins: the rule values are resolved down the pack chain (`Tuning.resolve`, once for the run: the sub, the air and ink limits, the
## waits), the mods the player's campaign declares are resolved into the run's rule hooks (`ModHooks.resolve`, empty for the originals), and everything else comes from `player`, or is a new Voyager player's (2 tanks, a full tank of air, a full supply of ink, every hint unseen)
## when there is none (free play is given a throw-away player by `GameFlow`; debug scenes and tests run with none). It mirrors
## `SignIn` (0x42e028), which copies the chosen roster slot into the current-player record, and so the numbers, the pieces, the
## midpoint flag, the hints and the switches of the game. Then a sector and a life begin with it. The sign-in screen calls it before
## the game scene exists, so that the console of the new game reads no light, sector or piece count of the game before.
func begin_run(player: PlayerProfile = null) -> void:
	profile = player
	TroubleLog.new_run()
	tuning = Tuning.resolve()
	use_campaign_hooks(player.campaign() if player != null else null)
	oxygen_model = OxygenModel.new(tuning)
	ink = tuning.ink_max
	edu_level = 0
	customized = false
	hints = HintSystem.new()
	sector = -1
	piece_total = 0
	_loss_holds = 0
	_held_code = OxygenModel.OK
	_clear_sector()
	if player != null:
		if player.tanks != PlayerProfile.NEW_SUPPLY:                            # (a new player: the run's own numbers, as made above)
			oxygen_model.tanks = clampi(player.tanks, 0, tuning.max_tanks)      # (a record saved under other limits: the limits of this run's rules)
		if player.oxygen != PlayerProfile.NEW_SUPPLY:
			oxygen_model.oxygen = clampi(player.oxygen, 1, tuning.max_oxygen)
		if player.ink != PlayerProfile.NEW_SUPPLY:
			ink = clampi(player.ink, 0, tuning.ink_max)
		pieces_mask = player.pieces_mask
		past_midpoint = player.past_midpoint()
		hints.load_mask(player.hints_unseen)
		hints.enabled = player.hints_enabled
		customized = player.customized
		refresh_edu_level()
	_clear_life()
	_announce_all()


## The rule hooks of `campaign` (null: none) are the run's: the mods it declares (`Campaign.mods`) resolved against the chain in use, once (`ModHooks.resolve`). `begin_run` does it for the player's campaign, and the free play of
## a sector (`GameFlow.enter`) for the campaign the sector belongs to.
func use_campaign_hooks(campaign: Campaign) -> void:
	hooks = ModHooks.resolve(campaign)


## A run with no player: a new Voyager player's numbers (debug scenes, tests).
func reset() -> void:
	begin_run(null)


func _clear_life() -> void:
	ship_light = false
	computer_light = false
	midpoint_reached = past_midpoint


func _clear_sector() -> void:
	pieces_mask = 0
	past_midpoint = false


## Tells every listener the values of the run: the same values the console (`Hud._ready`) reads when it starts. (`midpoint_changed`
## is not in it: it is an event, "the sub just passed the midpoint", which the flow saves.)
func _announce_all() -> void:
	oxygen_changed.emit(oxygen_model.tanks, oxygen_model.oxygen)
	ink_changed.emit(ink)
	sector_changed.emit(sector)
	pieces_changed.emit()
	message_light_changed.emit(ship_light, computer_light)


func tanks() -> int:
	return oxygen_model.tanks


func oxygen() -> int:
	return oxygen_model.oxygen


## Applies one of the original's `UpdateOxygen(d)` calls (see OxygenModel.update).
## Returns its result code and emits the matching signals. When the air runs out,
## `tank_lost` / `game_over` follow at once, unless the losses are held (see `hold_losses`).
func update_oxygen(d: int) -> int:
	var code := oxygen_model.update(d)
	oxygen_changed.emit(oxygen_model.tanks, oxygen_model.oxygen)
	if code != OxygenModel.OK:
		if _loss_holds == 0:
			_announce_loss(code)
		elif _held_code == OxygenModel.OK:
			_held_code = code                       # only the first one counts
	return code


func _announce_loss(code: int) -> void:
	if OxygenModel.is_tank_lost(code):
		tank_lost.emit(code)
	elif code == OxygenModel.GAME_OVER:
		game_over.emit()


## While a math problem is open the original keeps playing the problem: the air may run out at a
## wrong answer, but the sub only loses its tank when the problem is closed (the original returns
## the code AFTER the problem). `ProblemScreen` calls `hold_losses()` when it opens and
## `release_losses()` when it closes; in between `update_oxygen` still changes the numbers (the
## console shows them dropping) but `tank_lost` / `game_over` wait.
##
## Teaches: the same lesson as `GameClock.hold`. The sim holds the losses too, from a hit until the sub has dissolved
## (`SimWorld.sub_damaged` .. `settle_damage`), and a problem can open inside that wait; a plain on/off switch let the problem's
## opening forget the tank that was already lost and its closing end the sim's hold. A COUNT has no order: a loss that was
## decided before a hold began stays remembered, and it is announced when the LAST hold is released.
func hold_losses() -> void:
	_loss_holds += 1


## Ends one hold; when it was the last one, announces the loss that was waiting, if any. A release with no hold is ignored
## (a hold that was cleared by `begin_run`).
func release_losses() -> void:
	_loss_holds = maxi(0, _loss_holds - 1)
	if _loss_holds > 0:
		return
	var code := _held_code
	_held_code = OxygenModel.OK
	if code != OxygenModel.OK:
		_announce_loss(code)


## Ends one hold like `release_losses`, but when it was the last one the loss that waits is FORGOTTEN, not announced. For a hold whose
## owner is thrown away before it is over: a problem screen whose scene leaves (`ProblemScreen._exit_tree`), a dissolve whose sim is
## thrown away or loads another sector (`SimWorld.abandon_damage`). Nothing is left to respawn a sub that is gone, and the numbers
## stay as they are (the empty tank, the spare tanks untouched).
func drop_losses() -> void:
	_loss_holds = maxi(0, _loss_holds - 1)
	if _loss_holds == 0:
		_held_code = OxygenModel.OK


func has_held_loss() -> bool:
	return _loss_holds > 0 and _held_code != OxygenModel.OK


## The air ran out with a spare tank: a fresh tank, one spare less (`UpdateOxygen(4)`).
## The pieces stay collected.
func respawn() -> void:
	update_oxygen(4)


## Game over: back to the start of the sector and one more try. `Main` (0x427bb4) after `DoAction` returns 2: `UpdateOxygen(3)`,
## `UpdateInkPelletUses(21)` (a full supply: `Tuning.ink_max`), nothing collected, `SetPastSectorMidpoint(0)` (`begin_sector`), `tries` + 1.
func restart_sector() -> void:
	update_oxygen(3)
	refill_ink()
	begin_sector()
	if profile != null:
		profile.tries += 1


## Uses one pellet. Returns false (and emits `ink_empty`) when there is none.
func fire_ink() -> bool:
	if ink <= 0:
		ink_empty.emit()
		return false
	ink -= 1
	ink_changed.emit(ink)
	return true


## Back to a full supply of pellets (supply station, game over).
func refill_ink() -> void:
	ink = tuning.ink_max
	ink_changed.emit(ink)


## Tells everybody which sector is played and how many pieces it has (`SimWorld.load_sector` calls this whenever it loads a sector;
## `GameFlow.begin_sector` calls it first, before the start screen is chosen from `past_midpoint`). The collected pieces are left alone,
## except where they cannot belong to this sector. When the saved game of the player was written while the sector had another number of
## pieces (the designer added or removed one since: `PlayerProfile.pieces_total`), its bits may name other pieces and its midpoint flag
## was earned on another layout: the sector's whole collecting starts over through its reset (`begin_sector`, which announces it), and the
## player's record takes the new count, so the collecting that starts now is not thrown away again by the next load. Bits above the
## sector's last piece are dropped whatever their source (`Progression.valid_pieces_mask`).
func set_sector(index: int, pieces: int) -> void:
	sector = index
	piece_total = pieces
	if is_saved_with_other_pieces(index, pieces):
		profile.pieces_total = pieces
		begin_sector()
	pieces_mask = Progression.valid_pieces_mask(pieces_mask, pieces)
	sector_changed.emit(index)
	pieces_changed.emit()


## True when the player's saved game is of sector `index` and was written while it had another number than `pieces` (a record of the
## first release does not know its count: 0, trusted).
func is_saved_with_other_pieces(index: int, pieces: int) -> bool:
	return profile != null and profile.sector() == index and profile.pieces_total > 0 and profile.pieces_total != pieces


## Switches the console's message lights. Emits only when something changes.
func set_message_light(ship: bool, computer: bool) -> void:
	if ship == ship_light and computer == computer_light:
		return
	ship_light = ship
	computer_light = computer
	message_light_changed.emit(ship, computer)


## Which light a math trigger slot lights: x = ship, y = computer (DESIGN 5.2, `DetectMathTrigger` (0x427744)).
## Slots 2-19 and 60 up come from the surface ship, 20-59 from the onboard computer;
## the data canister (1) is the computer's.
func light_for_slot(slot: int) -> Vector2i:
	if slot == 1:
		return Vector2i(0, 1)
	if slot >= 20 and slot <= 59:
		return Vector2i(0, 1)
	return Vector2i(1, 0)


## Marks piece `index` as collected. Returns false if it already was.
func collect_piece(index: int) -> bool:
	var bit := 1 << index
	if pieces_mask & bit:
		return false
	pieces_mask |= bit
	piece_collected.emit(index)
	pieces_changed.emit()
	return true


## Takes piece `index` back (the air ran out during the canister's problem: collect it again).
func clear_piece(index: int) -> void:
	pieces_mask &= ~(1 << index)
	pieces_changed.emit()


func has_piece(index: int) -> bool:
	return pieces_mask & (1 << index) != 0


## How many pieces (the canister counts as one) are collected.
func pieces_collected() -> int:
	var count := 0
	for i in 16:
		if has_piece(i):
			count += 1
	return count


# --- the midpoint ---------------------------------------------------------------------

## The sub entered `screen` of `sector_data`. The midpoint screen is `tuning.midpoint_screen` (screen 6 in the original).
func screen_entered(screen: int, sector_data: SectorData) -> void:
	if screen == tuning.midpoint_screen:
		midpoint_reached = true
	update_midpoint(sector_data)


## The original's `SetPastSectorMidpoint(MidpointHelper())`, run after every screen change and every
## pickup: the flag turns on once screen 6 has been seen AND every piece on screens 0-5 is collected.
## It never turns off again until `begin_sector` (a new sector or a game over) or `clear_midpoint`.
func update_midpoint(sector_data: SectorData) -> void:
	if past_midpoint:
		return
	var screens := PackedInt32Array()
	for piece in sector_data.pieces:
		screens.append(piece.screen)
	if Progression.midpoint_flag(midpoint_reached, pieces_mask, screens, tuning.midpoint_screen):
		past_midpoint = true
		midpoint_changed.emit(true)


## Forgets the midpoint and nothing else (the debug jump to the finale): `SetPastSectorMidpoint(0)` (0x42e1e2).
func clear_midpoint() -> void:
	var was := past_midpoint
	midpoint_reached = false
	past_midpoint = false
	if was:
		midpoint_changed.emit(false)


# --- the player ----------------------------------------------------------------------

## Starts playing as `player`: the sub's numbers, the hints and the educational level come from the profile (`begin_run`).
func apply_profile(player: PlayerProfile) -> void:
	begin_run(player)


## The math level of the current sector: the player's own choice or the zone's default.
func refresh_edu_level() -> void:
	if profile != null:
		edu_level = profile.effective_edu_level()


## Copies the running game back into the profile (the caller saves it with `SaveStore.save_roster`).
func capture_profile() -> void:
	if profile == null:
		return
	profile.tanks = oxygen_model.tanks
	profile.oxygen = maxi(oxygen_model.oxygen, 1)          # a saved game never starts with an empty tank
	profile.ink = ink
	profile.pieces_mask = pieces_mask
	if sector == profile.sector():                          # (the piece count is only known once the player's sector is loaded)
		profile.pieces_total = piece_total
	profile.hints_unseen = hints.mask_for_save()
	profile.hints_enabled = hints.enabled
	profile.customized = customized
	profile.progress = Progression.with_midpoint(profile.progress, past_midpoint)
