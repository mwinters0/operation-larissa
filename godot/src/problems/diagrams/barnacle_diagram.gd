class_name BarnacleDiagram
extends DiagramBase
## Type 14, Closed-Circuit Monitor: barnacles on the monitor screen, the unhealthy ones in one picture.
##
## Teaches: a draw list that changes over time. The healthy barnacles come in two pictures that
## swap (the original does that three times), so the diagram has a `phase` and rebuilds its items.

## 0 or 1: which healthy picture the first group of healthy barnacles shows.
var phase: int = 1


func _build() -> void:
	add_spec_items(spec["items"])
	var barnacle: Dictionary = spec["barnacle"]
	var positions: Array = barnacle["pos"]
	var total := record.int_at(barnacle["total_field"])
	var unhealthy := record.int_at(barnacle["unhealthy_field"])
	var healthy := total - unhealthy
	@warning_ignore("integer_division")
	var first_group := healthy / 2                  # the healthy ones are split in two groups, the picture swapping
	if first_group == 0:
		first_group = healthy
	var pics: Array = barnacle["healthy_pics"]
	for i in total:
		var at := vector(positions[i])
		if i < unhealthy:
			add_picture(barnacle["unhealthy_pic"], at)
		elif i < unhealthy + first_group:
			add_picture(pics[phase], at)
		else:
			add_picture(pics[1 - phase], at)


## Number of barnacles drawn (the record's total).
func barnacle_count() -> int:
	return record.int_at(spec["barnacle"]["total_field"])


## Barnacles that are not unhealthy.
func healthy_count() -> int:
	return barnacle_count() - record.int_at(spec["barnacle"]["unhealthy_field"])


## `AnimateBarnacles` (0x4278dc) and `do_ccmonitor_opening` (0x427b10): three rounds of "show the pictures with phase 0, wait 30 ticks,
## show phase 1, wait 40 ticks"; at the start of each round the original calls `PlaySoundEffect(0x24)` once per healthy barnacle
## (back to back, so one sound is heard); 20 ticks after the last round the prompt may appear. Ends as built by `_build`.
func _schedule_intro() -> DiagramTimeline:
	var plan: Dictionary = spec["intro"]
	var barnacle: Dictionary = spec["barnacle"]
	var first_ticks: int = barnacle["ticks"][0]
	var round_ticks: int = first_ticks + int(barnacle["ticks"][1])
	var timeline := DiagramTimeline.new()
	for round_index in int(barnacle["rounds"]):
		var start := round_index * round_ticks
		var step := timeline.add_step(start, _items_in_phase(0), plan["sfx"] if healthy_count() > 0 else -1)
		step.sfx_calls = healthy_count()
		timeline.add_step(start + first_ticks, _items_in_phase(1))
	timeline.end_tick = int(barnacle["rounds"]) * round_ticks + int(plan["tail"])
	return timeline


func _items_in_phase(wanted: int) -> Array[DiagramItem]:
	var saved := phase
	phase = wanted
	var made := _aside(_build)
	phase = saved
	return made
