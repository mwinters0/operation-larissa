class_name ClosingCrewScripts
extends Resource
## The six sailors of the Expert closing's deck shot, as decoded from the original's CLOSING.C
## (`ExpertCraneTable` 0x4415a4, run by `ExpertClosingCrewStep` 0x41ceb7; DESIGN 2.1). The numbers come from
## `docs/data/expert_closing.json` through the importer (`data/closing_crew.tres`); nothing here is typed in by hand.
##
## Despite its name the original table is not a crane script: it holds one small program per sailor. A program is
## a list of 4-number records `[op, item, mirror, delay]`, stored flat. `ClosingCrewActor` runs one.

## Item `i` of a record is the loose picture `first_picture + i` (bundle 0x1d1 of the original).
@export var first_picture: int = 0          # (the data file holds the number; `Assets.ui_picture_by_number(first_picture + item)`)
## Where sailor `n` starts, in window pixels (the original's `ExpertClosingCrewPos`).
@export var start_x: PackedInt32Array = PackedInt32Array()
@export var start_y: PackedInt32Array = PackedInt32Array()
## Sailor `n`'s program: 4 numbers per record, the last record is the end op.
@export var scripts: Array[PackedInt32Array] = []
