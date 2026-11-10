class_name TickSmoothing
extends RefCounted
## Draws things smoothly although their logic only advances 12.17 times a second.
##
## Teaches: the classic "fixed timestep + interpolation" pattern.
##
## The game logic (sub, creatures, ink pellets) moves in whole-pixel steps once per
## GameClock tick, exactly like the original. Drawn as they are, those steps would
## look like a 12 fps slideshow on a 60 Hz monitor. So every moving thing keeps its
## position from the previous tick and its sprite is drawn somewhere BETWEEN the
## previous and the current logic position, depending on how far into the current
## tick we are (`GameClock.tick_fraction()`, 0..1). The logic and the collisions
## never see this: only the picture is shifted. The price is that the picture lags
## the logic position by up to one tick (82 ms), the same for every moving thing,
## so they still line up with each other.
##
## The fraction is an ARGUMENT, not something this function looks up: the presenter is given it once per frame
## (`SectorPresenter.show_between_ticks`), so a presenter needs no autoload, and a test can ask for any fraction it likes.
##
## Usage, in a node whose `position` is the logic position:
##     func _on_tick(): _previous_position = position; ...move...
##     func show_between_ticks(fraction): visual.position = TickSmoothing.offset(_previous_position, position, fraction)


## How far to shift a sprite (relative to its node) so that it appears at the
## interpolated position: the previous position when the tick has just started,
## the logic position when it is about to end. `fraction`: how far into the tick we are, 0..1 (`GameClock.tick_fraction()`).
static func offset(previous: Vector2, current: Vector2, fraction: float) -> Vector2:
	return (previous - current) * (1.0 - fraction)
