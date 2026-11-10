class_name RenderSettings
extends Resource
## How a skin wants its pictures filtered and placed on the pixel grid. Today the whole project draws with "nearest" filtering and
## snaps every 2D transform to whole pixels (Project Settings > Rendering > Textures > Default Texture Filter, and 2D > Snap);
## both are also properties of a `Viewport` and the filter is one of every `CanvasItem`, so a skin that draws 4x art, or smooth
## vector shapes, sets its own without touching the project.
##
## The defaults below ARE the project's settings (`project.godot`), so a `RenderSettings.new()` leaves the original look exactly as
## it is; `tests/engine/test_skin_render.gd` pins them to `ProjectSettings` so the two cannot drift apart.
##
## Teaches: a project setting is only the DEFAULT of a node's property. The `Window` at the root of the tree is a `Viewport` that
## starts with the project's values; changing its properties at run time changes what is drawn from the next frame on, and every
## `CanvasItem` inherits `texture_filter` from its parent unless it says otherwise (`TEXTURE_FILTER_PARENT_NODE`).

## The filter for every picture that does not choose its own (Viewport.canvas_item_default_texture_filter). Nearest keeps pixels sharp.
@export var texture_filter: Viewport.DefaultCanvasItemTextureFilter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST

## Snap the position of every 2D node to a whole pixel (Viewport.snap_2d_transforms_to_pixel): no shimmer while something moves
## between two pixels, and none of the blur linear filtering would add.
@export var snap_transforms: bool = true

## Snap the corners of every drawn rectangle and sprite to whole pixels (Viewport.snap_2d_vertices_to_pixel).
@export var snap_vertices: bool = true

## The filter of the playfield (the presenter's node and everything below it), for a skin whose HUD and playfield want different
## ones. The default says "like the parent": the playfield inherits `texture_filter`, as it does today.
@export var playfield_filter: CanvasItem.TextureFilter = CanvasItem.TEXTURE_FILTER_PARENT_NODE


## Puts these settings on `viewport` (the root window, or a `SubViewport` of a skin that draws into one). A `SubViewport` does not
## inherit the window's settings: every one a skin makes should be given them with this call.
func apply_to(viewport: Viewport) -> void:
	viewport.canvas_item_default_texture_filter = texture_filter
	viewport.snap_2d_transforms_to_pixel = snap_transforms
	viewport.snap_2d_vertices_to_pixel = snap_vertices


## Puts the playfield's own filter on `playfield` (a presenter). With the default it inherits from the viewport, so nothing changes.
func apply_to_playfield(playfield: CanvasItem) -> void:
	playfield.texture_filter = playfield_filter


## True when `viewport` already has these settings (the tests, and a way to avoid touching a viewport that is right already).
func is_applied_to(viewport: Viewport) -> bool:
	return viewport.canvas_item_default_texture_filter == texture_filter \
			and viewport.snap_2d_transforms_to_pixel == snap_transforms \
			and viewport.snap_2d_vertices_to_pixel == snap_vertices
