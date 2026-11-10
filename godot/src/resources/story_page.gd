class_name StoryPage
extends Resource
## One page of the opening story: which pictures it shows and where. Part of a `StoryScript`.
##
## Teaches: a slide as data. Nothing here is code; a page is the names of its pictures (registry names, `ui_picture`
## kind) and the window pixels where the extra ones go.

## The heading picture (GALAXY SPACE CAPSULE, WORLD'S OCEANS, DANGEROUS TOXINS, NEPTUNE SUBMARINE).
@export var heading: StringName = &""
## The frame picture (the stars, the Pacific or the submarine's plan).
@export var frame: StringName = &""
## The page's words, drawn by the original as a finished bitmap.
@export var caption: StringName = &""
## Extra pictures and their top-left corners, in the same order.
@export var extra_pictures: Array[StringName] = []
@export var extra_positions: PackedVector2Array = PackedVector2Array()
## Whether the radar ring blinks on this page.
@export var ring: bool = false
## The last page: it waits longer and says "Click to go on".
@export var last: bool = false
