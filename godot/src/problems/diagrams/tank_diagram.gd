class_name TankDiagram
extends DiagramBase
## Type 21, Water Tank: the tank fills with water up to the given amount and a label names it.
##
## Teaches: reproducing a draw ORDER. The original fills the tank by stamping the same 156 x 32 water
## picture 2 pixels higher each frame and redrawing the tank's rim over it after every stamp.


func _build() -> void:
	add_spec_items(spec["items"])
	var quantity := supply()
	var tank: Dictionary = spec["tank"]
	var scale_info: Dictionary = spec["quantity"]["liters" if quantity["liters"] else "gallons"]
	add_picture(scale_info["pic"], vector(spec["quantity"]["scale_pos"]))
	add_picture(tank["front_pic"], vector(tank["front_pos"]))
	var frames := water_frames(quantity["amount"])
	var last_y: int = tank["water_y0"]
	var first := items.size()
	if frames == 0:                                  # a nearly empty tank: one picture, no rim
		add_picture(tank["water_pic"], Vector2(tank["water_x"], last_y))
		_end_group(first)
	for frame in frames:
		first = items.size()
		last_y = water_top(frame)
		add_picture(tank["water_pic"], Vector2(tank["water_x"], last_y))
		add_picture(tank["rim_pic"], vector(tank["rim_pos"]))
		_end_group(first)                            # one water frame per 6 ticks (spec "intro")
	# the label sits halfway between the water surface and the bottom of the tank
	first = items.size()
	@warning_ignore("integer_division")
	add_text(str(quantity["amount"]) + scale_info["unit"], Vector2(tank["label_x"], (last_y + int(tank["label_y_add"])) / 2))
	_end_group(first)                                # the last group: the label appears when the tank is full


## `Prob21_Diagram` (0x43378d): the sound 0x28 starts with the first water frame, every frame takes 6 ticks, and when the tank
## is full `StopCommonSoundEffect` cuts the sound and the label is written.
func _schedule_intro() -> DiagramTimeline:
	var plan: Dictionary = spec["intro"]
	var interval: int = plan["interval"]
	var events := []
	var frame_groups := _groups.size() - 1           # all but the label
	for i in frame_groups:
		events.append(_event(i * interval, _groups[i], plan["sfx"] if i == 0 else -1))
	var full_at := water_frames(supply()["amount"]) * interval
	events.append(_event(full_at, _groups.back(), -1, true))
	return _assemble(events, full_at)


## {"liters": bool, "amount": int}: the supply as the original shows it (liters if f0 is set, else gallons).
func supply() -> Dictionary:
	var info: Dictionary = spec["quantity"]
	var liters := record.int_at(info["liters_field"])
	if liters != 0:
		return {"liters": true, "amount": liters}
	return {"liters": false, "amount": record.int_at(info["gallons_field"])}


## Number of frames of water: 3 per unit, minus 7 (the tank's own bottom), never negative.
func water_frames(amount: int) -> int:
	var tank: Dictionary = spec["tank"]
	return maxi(0, amount * int(tank["frames_per_unit"]) - int(tank["frames_minus"]))


## y of the water picture's top in frame `frame` (0 = lowest).
func water_top(frame: int) -> int:
	var tank: Dictionary = spec["tank"]
	return int(tank["water_y0"]) + int(tank["water_step"]) * frame
