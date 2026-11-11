extends OriginalPresenter
## The presenter of the "modern" skin: the original's presenter (every picture, every rule-following behaviour) with one addition, the
## shimmer of the water behind the screen. `modern_presenter.tscn` is the original's scene with a `ShaderMaterial` on its `Background`
## sprite; this script only gives that shader the time.
##
## The time is the GAME's, not the engine's: ticks so far plus the fraction of the current tick (`SectorPresenter.game_phase`, from the skin API: `view.tick_number`
## and the `fraction` that `show_between_ticks` is given). So the water stops when the game clock does (a problem or a message is open,
## the sub dissolves, a pause) and runs at the speed of play otherwise. A shader's `TIME` could do neither.
##
## It reads, and never writes, what the rules say (`SectorPresenter`: a skin uses `view`), so this skin plays the same game as every
## other (`tests/engine/test_skin_modern.gd`).
##
## Teaches: a skin with a little code as an inherited scene. The scene instances the original's, changes one node, and swaps the
## script for one that `extends` the original's, so everything else is inherited and the skin stays a few lines long.

## The material of the background (this presenter's own copy, so a second one on screen has its own phase).
var _water: ShaderMaterial


func _ready() -> void:
	super._ready()
	_water = background.material.duplicate() as ShaderMaterial
	background.material = _water
	# The skin's pictures are smooth (linear filter, no pixel snap, see its `RenderSettings`), but the walls' tile atlas is the original's
	# small pixel art: drawn smooth, a hairline of the neighbouring tile shows between tiles. The walls keep the sharp filter.
	walls.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	currents.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func show_between_ticks(fraction: float) -> void:
	super.show_between_ticks(fraction)
	if view != null:
		_water.set_shader_parameter(&"phase", game_phase(fraction))
