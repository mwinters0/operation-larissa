class_name Progression
extends RefCounted
## The rules of "how far has this player got": the progress word, sectors, zones, the
## educational level and the midpoint flag. Pure functions, no nodes, no state.
##
## Teaches: a `RefCounted` class that is only a bag of `static` functions (nobody ever calls
## `Progression.new()`), and packing two facts into one integer. The original stores a player's
## position as ONE 16 bit number, `progress` (DESIGN 3.8):
##
##     progress = sector * 2 + midpoint_flag        sector = progress >> 1,  flag = progress & 1
##
## Voyager plays sectors 0-14 (progress 0, 2 ... 28 = 0x1C), Expert sectors 15-29 (0x1E ... 0x3A).
## Behind the last one comes the finale sector: 30 (progress 0x3C) for Voyager, 31 (0x3E) for Expert.
##
## WHICH SECTORS, WHICH ORDER, WHERE IT ENDS is not in this file: it is in the `Campaign`. The original compares numbers
## (`>= 30` is a finale, `/ 15` is the game, `% 15` the place in it); here the functions ask the campaign the sector belongs to, so a
## campaign with 8 sectors and a finale numbered 60 works the same. `progress` holds a SECTOR ID * 2 + flag, as in the original (the save
## format keeps it so; why is in `PlayerProfile`'s header), and the campaign's list decides whether a progress is valid. Each function that needs the campaign takes it as the last argument; left out, it is the one the sector belongs
## to (`Catalog.campaign_of_sector`).

## The progress words of the original's games: where a new player starts and where each game ends. These are what the two campaigns
## (`data/campaigns/`) work out (`tests/engine/test_campaign.gd`); they are named here for the save file's limits and for tests.
const VOYAGER_START := 0
const EXPERT_START := 0x1E
const VOYAGER_FINALE := 0x3C
const EXPERT_FINALE := 0x3E


## The progress of a new player of the original's game `game` (0 Voyager, 1 Expert).
static func start_progress(game: int) -> int:
	return Catalog.campaign_for_game(game).start_progress()


static func sector_of(progress: int) -> int:
	return progress >> 1


static func past_midpoint(progress: int) -> bool:
	return progress & 1 == 1


## `progress` with the midpoint flag set to `flag`.
static func with_midpoint(progress: int, flag: bool) -> int:
	return (progress >> 1) * 2 + (1 if flag else 0)


## The campaign the sector of `progress` belongs to, or null.
static func campaign_of(progress: int) -> Campaign:
	return Catalog.campaign_of_sector(sector_of(progress))


## 0 = Voyager, 1 = Expert (the original's `GetGameLevel`), the number a save file keeps in `PlayerProfile.game`; -1 for a sector of
## another campaign. The finales belong to their game: sectors 0-14 and 30 are Voyager.
static func game_of(progress: int) -> int:
	var campaign := campaign_of(progress)
	return Catalog.game_of_campaign(campaign.id) if campaign != null else -1


## The zone of the sector (index into `zones.tres`): 0-4 are the five undersea areas, 5 and 6 the finales of Voyager / Expert. It is the
## sector's own field, `SectorData.zone`.
static func zone_of(progress: int) -> int:
	var data := Catalog.sector(sector_of(progress))
	return data.zone if data != null else 0


## Is this a finale sector, where docking ends the game?
static func is_finale(progress: int, campaign: Campaign = null) -> bool:
	var owner_campaign := campaign if campaign != null else campaign_of(progress)
	return owner_campaign != null and owner_campaign.is_finale(sector_of(progress))


## The level of the math problems when the player did not customise the game.
## It is stored in the campaign, from `zones.tres` (DESIGN 3.8; the original keeps 10 levels, `game * 5 + zone`: Voyager whole, whole,
## fractions x3; Expert decimals x3, then everything x2); a finale uses the last zone's. `game` is the saved game number 0 / 1.
static func default_edu_level(game: int, zone: int) -> int:
	return Catalog.campaign_for_game(game).default_edu_level(zone)


## `IncrementSector`: the progress after finishing the current sector (midpoint flag cleared), by the campaign's list of sectors. After
## the last sector of Voyager comes the finale (0x3C), after the last of Expert its finale (0x3E); the finale sectors stay where they
## are (the closing sequence ends the game).
static func next_progress(progress: int, campaign: Campaign = null) -> int:
	var owner_campaign := campaign if campaign != null else campaign_of(progress)
	if owner_campaign == null:
		return (sector_of(progress) + 1) * 2
	return owner_campaign.next_progress(progress)


## What `MidpointHelper` (0x4191e0) computes: the flag turns on once the sub has been on the
## midpoint screen (`reached`) AND every piece that lies before it (screens 0-5 in the original) is collected.
## `midpoint_screen` is the run's (`Tuning.midpoint_screen`), `piece_screens[i]` is the screen of piece i, `pieces_mask` has bit i set
## for collected pieces.
static func midpoint_flag(reached: bool, pieces_mask: int, piece_screens: PackedInt32Array, midpoint_screen: int) -> bool:
	if not reached:
		return false
	for i in piece_screens.size():
		if piece_screens[i] < midpoint_screen and pieces_mask & (1 << i) == 0:
			return false
	return true


## `pieces_mask` as a sector with `total` pieces can have it: the bits of pieces that do not exist are dropped (a save written when the
## sector had more pieces, or a damaged one).
static func valid_pieces_mask(pieces_mask: int, total: int) -> int:
	return pieces_mask & ((1 << clampi(total, 0, 16)) - 1)


## How many of the `total` pieces are missing in `pieces_mask`.
static func pieces_missing(pieces_mask: int, total: int) -> int:
	var missing := 0
	for i in total:
		if pieces_mask & (1 << i) == 0:
			missing += 1
	return missing
