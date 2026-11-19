class_name PictureUse
extends RefCounted
## Which pictures a pack's DATA holds by key, and which rows of its `pictures.json` nothing asks for. A TEST helper for `test_picture_keys.gd` (the dev pack) and `tests/legacy/test_picture_keys_legacy.gd`
## (the legacy pack): the two packs are held to one rule.
##
## A KEY IS HELD by the data when a `.tres` of the pack has a `PictureRef` with it, a problem type lists it in `art_keys`, the closing crew in `pictures`, or a campaign in `finale_picture`. A ROW IS JUSTIFIED when something holds
## it, or the game asks for it by NAME (a `ui_picture` or `problem_art` name of the registry; a name the story data says: cutscene tracks, story pages, the Voyager's flight), or a picture nobody named (the original's pictures the game never draws: the importer keeps whole id ranges), or a screen asks for it by place (`background/bg_sNN_MM`), or it is an
## alias (it is another name of a row that is justified or not, whatever the target's own row is).
##
## Teaches: asking a data set what it names, as the engine would, and holding two packs of different content to the same rule.

const TIMELINES: Array[StringName] = [&"news_report", &"news_ambient", &"title_ship", &"title_reveal", &"expert_hoist", &"expert_deck", &"expert_wait"]


## key -> where it is held (a file of the pack, "problem type 3" ...), for every picture the pack's data holds by key.
static func held(pack: Pack) -> Dictionary:
	var found := {}
	for rel in pack.all_files():
		if rel.begins_with("data/") and rel.get_extension() == "tres":
			for key in PictureRef.keys_in_tres(pack.read_text(rel)):
				found[key] = rel
	for type_id in Catalog.problem_type_ids():
		var type := Catalog.problem_type_unskinned(type_id)
		if type != null:
			for key in type.art_keys:
				found[key] = "problem type %d" % type_id
	var crew := Catalog.closing_crew()
	if crew != null:
		for key in crew.pictures:
			found[key] = "the closing crew"
	for campaign in Catalog.campaigns():
		if not campaign.finale_picture.is_empty():
			found[campaign.finale_picture] = "campaign %s" % campaign.id
	return found


## The names the story data of the chain says (cutscene tracks, the story's pages, the Voyager's flight): any name or list of names a property holds.
static func story_names() -> Dictionary:
	var found := {}
	for timeline_name in TIMELINES:
		var timeline := Catalog.story_timeline(timeline_name)
		if timeline != null:
			for track in timeline.tracks:
				for value in track.values:
					if value is StringName or value is String:
						found[String(value)] = true
	for resource: Resource in [Catalog.story_script(&"story_script"), Catalog.voyager_closing_script()]:
		if resource != null:
			_names_in(resource, found)
	return found


static func _names_in(resource: Resource, found: Dictionary) -> void:
	for info in resource.get_property_list():
		if not (info.usage & PROPERTY_USAGE_STORAGE):
			continue
		var value: Variant = resource.get(info.name)
		if value is StringName:
			found[String(value)] = true
		elif value is Array:
			for item: Variant in value:
				if item is StringName:
					found[String(item)] = true
				elif item is Resource:
					_names_in(item, found)


## The keys held by the data that no row of the chain answers with a picture.
static func unanswered(pack: Pack) -> Array[String]:
	var lacking: Array[String] = []
	var keys := held(pack).keys()
	keys.sort()
	for key: String in keys:
		if not Pictures.has(key):
			lacking.append("%s (held by %s)" % [key, held(pack)[key]])
	return lacking


## The rows of the pack's table that nothing justifies (see the header).
static func unjustified(pack: Pack) -> Array[String]:
	var table := pack.picture_table()
	var in_data := held(pack)
	var told := story_names()
	var registry := NameRegistry.original()
	var rows: Array[String] = []
	for key in table.keys():
		var kind := key.get_slice("/", 0)
		var picture_name := key.get_slice("/", 1)
		if in_data.has(key) or table.aliases.has(key) or kind == "background":
			continue
		if (kind == "ui_picture" or kind == "problem_art") and registry.index_of(StringName(kind), picture_name) >= 0 and registry.is_named(StringName(kind), registry.index_of(StringName(kind), picture_name)):
			continue
		if kind == "ui_picture" and told.has(picture_name):
			continue
		if (kind == "ui_picture" or kind == "problem_art") and registry.index_of(StringName(kind), picture_name) >= 0:
			continue                                           # (a picture nobody named, `ui_1048`: the importer keeps every picture of its id ranges, also those the game never draws)
		rows.append(key)
	return rows
