class_name CanisterLog
extends RefCounted
## Which log entries the data canister's log screen lists, and how its menu moves. Pure functions, no nodes.
##
## Teaches: game rules as data plus a few `static` functions. The original keeps the rules in two byte tables
## in the EXE and in `PrepareCanisterLog` (0x41e787) (DESIGN 7, "Canister log screen"); here the tables are the
## `Campaign`'s (`log_unlock_order`, `log_texts`, `log_voices`; the originals' are in `data/campaigns/`) and this class is the menu around them:
##
##   * Voyager and Expert have 15 entries each ("ENTRY 1.01" .. "1.15" and "2.01" .. "2.15"; text ids 10648-10677,
##     the speech is the voice groups `log_0` .. `log_29`).
##   * The k-th sector of a game (0-14 of Voyager, 15-29 of Expert) has k entries unlocked: the first k numbers of the campaign's
##     unlock order. The last of those is the entry the canister has just delivered; it is the one the screen opens on. (The finales
##     list what `Campaign.finale_log_counts` says: the original's `s % 15 + 1` gives sector 30 one entry and sector 31 two.)
##   * The menu lists the unlocked numbers in ascending order, followed by DONE.
##
## The functions take the sector and, optionally, the campaign; left out it is the one the sector belongs to.

## The menu has two columns of eight rows (`LogRowX` 0x4419f4, `LogRowY` 0x441a34): row r is at
## (COLUMN_X[r / 8], FIRST_ROW_Y + 20 * (r % 8)); the highlight is 115 x 16 px starting 2 px left of the text.
const COLUMN_X: Array[int] = [362, 485]
const FIRST_ROW_Y := 88
const ROW_PITCH := 20
const ROWS_PER_COLUMN := 8
const ROW_SIZE := Vector2i(115, 16)

## The scan before the entry is read (`AnimateLogScan` 0x41e092), in the original's ticks (1/73 s): eight lights, a red one running
## left to right, six times, 5 ticks a picture = 240 ticks (3.3 s). The screen is told this length (`scan_ticks()`) and plays inside
## it; the picture shown at each tick is `scan_picture`. The eight lights are the scanner's art; how long a picture stays and how many
## sweeps there are is data (`log_scan.*` of `data/rules/durations.json`, `Durations`).
const SCAN_PICTURES_PER_SWEEP := 8
## The picture the scanner rests on once the scan is over: all green.
const SCAN_RESTING_PICTURE := SCAN_PICTURES_PER_SWEEP

## What a navigation key does to the highlighted row.
enum Move { UP, DOWN, SIDEWAYS }


## Which of the scanner's nine pictures shows `tick` ticks into the scan: the red light at position `(tick / 5) % 8`, all green from
## the end of the scan on.
@warning_ignore("integer_division")
static func scan_picture(tick: int) -> int:
	if tick >= scan_ticks():
		return SCAN_RESTING_PICTURE
	return (maxi(tick, 0) / scan_picture_ticks()) % SCAN_PICTURES_PER_SWEEP


## How many ticks one picture of the scan stays (5).
static func scan_picture_ticks() -> int:
	return maxi(Durations.at("log_scan.ticks_per_picture"), 1)


## How many ticks the whole scan lasts (240): pictures per sweep, ticks a picture, sweeps.
static func scan_ticks() -> int:
	return scan_picture_ticks() * SCAN_PICTURES_PER_SWEEP * maxi(Durations.at("log_scan.sweeps"), 0)


## The campaign whose log is meant: `campaign` if given, else the one `sector` belongs to.
static func campaign_of(sector: int, campaign: Campaign = null) -> Campaign:
	return campaign if campaign != null else Catalog.campaign_of_sector(sector)


## How many entries the log lists in `sector` (`PrepareCanisterLog`); 0 for a sector of no campaign.
static func count(sector: int, campaign: Campaign = null) -> int:
	var owner_campaign := campaign_of(sector, campaign)
	return owner_campaign.log_count(sector) if owner_campaign != null else 0


## The entry number (1-15) the canister of `sector` delivers; 0 for a sector of no campaign.
static func newest(sector: int, campaign: Campaign = null) -> int:
	var owner_campaign := campaign_of(sector, campaign)
	return owner_campaign.log_newest(sector) if owner_campaign != null else 0


## The entry numbers listed in `sector`, ascending (the original's insertion sort).
static func entries(sector: int, campaign: Campaign = null) -> PackedInt32Array:
	var owner_campaign := campaign_of(sector, campaign)
	return owner_campaign.log_entries(sector) if owner_campaign != null else PackedInt32Array()


## The row the menu opens on: where the newest entry sits in the sorted list.
static func initial_row(sector: int, campaign: Campaign = null) -> int:
	return entries(sector, campaign).find(newest(sector, campaign))


## The `text` name of entry `number` (1-15) of `campaign`: `log_entry_0` .. `log_entry_29` for the originals (a campaign of its own may hold the words
## instead; the screen shows `Campaign.log_entry_text`).
static func text_name(campaign: Campaign, number: int) -> StringName:
	return campaign.log_text_name(number)


## The menu row caption: the string "ENTRY" (11032) and " 1.00" with the campaign's series digit and the entry number patched in.
static func label(entry_word: String, campaign: Campaign, number: int) -> String:
	return "%s %d.%02d" % [entry_word, campaign.log_series, number]


## Top-left corner of menu row `row` (0 .. count; the last row is DONE).
@warning_ignore("integer_division")
static func row_position(row: int) -> Vector2i:
	return Vector2i(COLUMN_X[row / ROWS_PER_COLUMN], FIRST_ROW_Y + ROW_PITCH * (row % ROWS_PER_COLUMN))


## The highlighted row after `move`. Rows 0 .. `entry_count` - 1 are the entries, row `entry_count` is DONE. Up and down
## wrap around the whole list; sideways jumps to the other column (row +- 8) and stops at DONE if the other column is shorter.
static func next_row(row: int, entry_count: int, move: Move) -> int:
	match move:
		Move.UP:
			return row - 1 if row > 0 else entry_count
		Move.DOWN:
			return row + 1 if row < entry_count else 0
		_:
			var target := row + ROWS_PER_COLUMN if row < ROWS_PER_COLUMN else row - ROWS_PER_COLUMN
			return mini(target, entry_count)
