extends SceneTree
## Loads the dev pack's data with the engine's own resource classes and asks each one whether it is sound.
## Run (under the shared Godot lock):  tools/godot.sh --headless --path godot -s ../tools/dev_pack/godot/check_dev_pack.gd
## It prints one line per problem and "dev pack check: N problems" at the end; the exit code is 1 when there are any.

const ROOT := "res://packs/dev/"
var problems: Array[String] = []


func _init() -> void:
	ResourceLoader.add_resource_format_loader(FoeScriptLoader.new())     # a -s script does not get the project's custom loaders
	_load_everything(ROOT + "data")
	_sprites()
	_layouts()
	_tables()
	_problem_types()
	_sectors()
	for p in problems:
		print("PROBLEM ", p)
	print("dev pack check: %d problems" % problems.size())
	quit(1 if problems.size() > 0 else 0)


func _fail(text: String) -> void:
	problems.append(text)


func _files(dir: String, extension: String) -> Array[String]:
	var found: Array[String] = []
	for name in DirAccess.get_directories_at(dir):
		found.append_array(_files(dir + "/" + name, extension))
	for name in DirAccess.get_files_at(dir):
		if name.ends_with("." + extension):
			found.append(dir + "/" + name)
	found.sort()
	return found


func _load_everything(dir: String) -> void:
	for path in _files(dir, "tres"):
		if path.get_file() in ["sfx_catalog.tres", "music_catalog.tres", "voice_index.tres", "voice_cues.tres"]:
			continue                                                      # the audio work item's
		var res := load(path)
		if res == null:
			_fail("%s does not load" % path)


func _tex_size(path: String) -> Vector2i:
	var t := load(path) as Texture2D
	return Vector2i(t.get_size()) if t != null else Vector2i(-1, -1)


func _sprites() -> void:
	var meta_names := {"common": "foes_zone0", "ink": "foes_zone0"}
	for path in _files(ROOT + "data/sprite_meta", "tres"):
		var table := load(path) as SpriteMetaTable
		if table == null:
			_fail("%s is not a SpriteMetaTable" % path)
			continue
		for message in table.problems():
			_fail("%s: %s" % [path, message])
	var common := load(ROOT + "data/sprite_meta/sprite_meta_common.tres") as SpriteMetaTable
	var ink := load(ROOT + "data/sprite_meta/sprite_meta_ink.tres") as SpriteMetaTable
	for z in 7:
		var frames := load(ROOT + "data/sprite_frames/foes_zone%d.tres" % z) as SpriteFrames
		var own := load(ROOT + "data/sprite_meta/sprite_meta_zone%d.tres" % z) as SpriteMetaTable
		if frames == null or own == null:
			_fail("foes zone %d: no frames or no meta" % z)
			continue
		var count := frames.get_frame_count(&"all")
		if count != common.count() + ink.count() + own.count():
			_fail("foes zone %d: %d pictures but %d sprite sizes" % [z, count, common.count() + ink.count() + own.count()])
			continue
		for i in count:
			var want: Vector2i = (common.sizes + ink.sizes + own.sizes)[i]
			var got := Vector2i(frames.get_frame_texture(&"all", i).get_size())
			if want != got:
				_fail("foes zone %d slot %d: sprite meta says %s, the picture is %s" % [z, i, want, got])
	for name in ["sub_frames", "pieces_frames", "station_frames", "fx_frames"]:
		var frames := load(ROOT + "data/sprite_frames/%s.tres" % name) as SpriteFrames
		if frames == null:
			_fail("%s does not load" % name)
			continue
		for anim in frames.get_animation_names():
			for i in frames.get_frame_count(anim):
				if frames.get_frame_texture(anim, i) == null:
					_fail("%s %s frame %d has no picture" % [name, anim, i])
	var sub := load(ROOT + "data/sprite_frames/sub_frames.tres") as SpriteFrames
	if sub != null and Vector2i(sub.get_frame_texture(&"all", 0).get_size()) != PieceModel.SUB_PICTURE_SIZE:
		_fail("the sub's picture is %s, the engine assumes %s" % [sub.get_frame_texture(&"all", 0).get_size(), PieceModel.SUB_PICTURE_SIZE])
	var pieces := load(ROOT + "data/sprite_frames/pieces_frames.tres") as SpriteFrames
	if pieces != null and Vector2i(pieces.get_frame_texture(&"all", 0).get_size()) != PieceModel.PICTURE_SIZE:
		_fail("a piece's picture is %s, the engine assumes %s" % [pieces.get_frame_texture(&"all", 0).get_size(), PieceModel.PICTURE_SIZE])
	var rules := load(ROOT + "data/bubble_rules.tres") as BubbleRules
	var bubbles := load(ROOT + "data/sprite_frames/fx_frames.tres") as SpriteFrames
	if rules != null and bubbles != null:
		for i in rules.picture_sizes.size():
			if Vector2i(bubbles.get_frame_texture(&"all", i).get_size()) != rules.picture_sizes[i]:
				_fail("bubble picture %d: rules say %s, the picture is %s" % [i, rules.picture_sizes[i], bubbles.get_frame_texture(&"all", i).get_size()])


func _layouts() -> void:
	var hud := load(ROOT + "data/ui/hud_layout.tres") as HudLayout
	if hud != null:
		for pair: Array in [[hud.game_textures[0], hud.game_size], [hud.custom_texture, hud.custom_size], [hud.zone_textures[0], hud.zone_size],
				[hud.sector_textures[0], hud.sector_size], [hud.sector_final_texture, hud.sector_size]]:
			if Vector2i((pair[0] as Texture2D).get_size()) != pair[1]:
				_fail("a HUD label picture is %s, its layout size %s" % [(pair[0] as Texture2D).get_size(), pair[1]])
		if hud.playfield.size != Vector2i(608, 288):
			_fail("the playfield is %s" % hud.playfield)
	var calc := load(ROOT + "data/ui/calculator_layout.tres") as CalculatorLayout
	if calc != null:
		if Vector2i(calc.picture.get_size()) != calc.picture_size:
			_fail("calculator picture %s, layout %s" % [calc.picture.get_size(), calc.picture_size])
		if Vector2i(calc.answer_panel.get_size()) != calc.answer_size:
			_fail("answer panel %s, layout %s" % [calc.answer_panel.get_size(), calc.answer_size])
		for i in 10:
			if Vector2i(calc.digit_textures[i].get_size()) != calc.digit_sizes[i]:
				_fail("calculator digit %d picture %s, layout %s" % [i, calc.digit_textures[i].get_size(), calc.digit_sizes[i]])
		var picture := Rect2i(calc.picture_position, calc.picture_size)
		for i in calc.key_names.size():
			if not picture.encloses(calc.key_rects[i]):
				_fail("calculator key %s is outside the calculator picture" % calc.key_names[i])
	var story := load(ROOT + "data/ui/story_layout.tres") as StoryLayout
	if story != null and story.points.size() != 68:
		_fail("story layout has %d points, 68 expected" % story.points.size())
	var cartoon := load(ROOT + "data/story/news_cartoon.tres") as CutsceneTimeline
	if cartoon != null:
		for message in cartoon.problems():
			_fail("news cartoon: " + message)
	var screen := load(ROOT + "data/problems/screen_layout.tres") as ProblemScreenLayout
	if screen != null and screen.palette.size() != 16:
		_fail("problem screen palette has %d colours" % screen.palette.size())


func _tables() -> void:
	var triggers := load(ROOT + "data/trigger_table.tres") as TriggerTable
	if triggers != null:
		for message in triggers.problems():
			_fail("trigger table: " + message)
	var zones := load(ROOT + "data/zones.tres") as ZoneTable
	if zones != null:
		if zones.zones.size() != 7:
			_fail("zones: %d, 7 expected" % zones.zones.size())
		for message in zones.default_edu_problems():
			_fail("zones: " + message)
	var tileset := load(ROOT + "data/neptune_tileset.tres") as TileSet
	if tileset == null or tileset.get_source_count() != 7:
		_fail("the tile set does not have 7 sources")


func _problem_types() -> void:
	for t in 34:
		var type := load(ROOT + "data/problems/problem_type_%02d.tres" % t) as ProblemType
		if type == null:
			_fail("problem type %d does not load" % t)
			continue
		for level in 4:
			if type.record_count(level) == 0 and not (t == 3 and level == 2):    # (type 3 has no record at level 2 on purpose: a test of the empty level)
				_fail("problem type %d has no record at level %d" % [t, level])
				continue
			for n in type.record_count(level):
				var instance := ProblemInstance.build(type, level, n)
				if instance == null or instance.prompt == "":
					_fail("problem type %d level %d record %d has no prompt" % [t, level, n])
				elif TextTemplate.has_unfilled_slot(instance.prompt):
					_fail("problem type %d level %d record %d: unfilled slot in the prompt: %s" % [t, level, n, instance.prompt])
				if instance != null:
					_answer_and_diagram(type, level, n, instance)
		for path in type.art_files:
			if not ResourceLoader.exists(path):
				_fail("problem type %d: art file %s is missing" % [t, path])


## The stored answer must be accepted, and the diagram of the record must build items.
func _answer_and_diagram(type: ProblemType, level: int, n: int, instance: ProblemInstance) -> void:
	var where := "problem type %d level %d record %d" % [type.id, level, n]
	if instance.input_kind == ProblemInstance.InputKind.DENOMINATIONS:
		if not AnswerChecker.check_selection(type, level, instance.record, instance.record.int_at(1)):
			_fail("%s: the stored selection does not add up to the target" % where)
	elif instance.expected != null and not instance.check(instance.expected):
		_fail("%s: the stored answer %s is not accepted" % [where, instance.expected.to_text()])
	var diagram := DiagramFactory.create(instance)
	if diagram == null or diagram.items.is_empty():
		_fail("%s: the diagram has no items" % where)
	if diagram != null:
		diagram.free()


func _sectors() -> void:
	for index in 5:
		var path := ROOT + "data/sectors/sector_%02d/sector_%02d.tres" % [index, index]
		var sector := load(path) as SectorData
		if sector == null:
			_fail("sector %d does not load" % index)
			continue
		for message in sector.header_problems():
			_fail("sector %d header: %s" % [index, message])
		for message in sector.resource_problems():
			_fail("sector %d: %s" % [index, message])
		for message in sector.compile():
			_fail("sector %d script: %s" % [index, message])
		for m in sector.screens.size():
			for message in sector.screens[m].validate():
				_fail("sector %d screen %d: %s" % [index, m, message])
	var campaign := load(ROOT + "data/campaigns/dev_tour.tres") as Campaign
	if campaign == null:
		_fail("dev_tour does not load")
	else:
		for message in campaign.problems():
			_fail("dev_tour: " + message)
