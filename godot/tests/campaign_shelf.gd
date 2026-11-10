class_name CampaignShelf
extends RefCounted
## A folder of campaigns for a test: those of the chain's packs (copied: the dev tour on dev, the original's two on legacy) and the made-up ones given, installed as `Catalog.campaigns_dir` so that
## everything that looks a campaign up by id (`PlayerProfile.campaign()`, the new-player dialog, the Hall of Fame) finds them. `remove`
## puts the project's own folder back. Each shelf has a folder of its own: a campaign file is cached by its path, so a new test must not
## reuse the path of an old one.
##
## Teaches: a test double for a directory, the way `Catalog.sectors_dir` is for the sectors, and why: the lookups are static and read the
## disk, so the honest way to give them other data is another folder, not a mock.

static var _count: int = 0

var dir: String


func _init(campaigns: Array[Campaign] = []) -> void:
	_count += 1
	dir = "user://test_campaigns_%d_%d" % [Time.get_ticks_msec(), _count]
	DirAccess.make_dir_recursive_absolute(dir)
	for each in Packs.chain():                                       # (the project's own campaigns, `res://data/campaigns`, are left out)
		var folder := each.path_of("data/campaigns")
		for entry in ResourceLoader.list_directory(folder):
			if entry.ends_with(".tres") and not FileAccess.file_exists("%s/%s" % [dir, entry]):
				DirAccess.copy_absolute("%s/%s" % [folder, entry], "%s/%s" % [dir, entry])
	for campaign in campaigns:
		ResourceSaver.save(campaign, "%s/%s.tres" % [dir, campaign.id])
	Catalog.campaigns_dir = dir
	Catalog.reload_campaigns()


## The project's own campaigns again, and the folder gone.
func remove() -> void:
	Catalog.campaigns_dir = Catalog.CAMPAIGNS_DIR
	Catalog.reload_campaigns()
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, file])
	DirAccess.remove_absolute(dir)


## A student's campaign whose sectors are numbers no sector file has (175-177, the end of batch D's range): enough for everything that only asks "is this sector in the
## list", never loads one. Its words are its own (no text names), and it has no recordings at all.
static func garden() -> Campaign:
	var garden := Campaign.new()
	garden.id = &"garden"
	garden.title = "Garden of Tests"
	garden.banner_index = 0
	garden.sectors = PackedInt32Array([175, 176])
	garden.finales = PackedInt32Array([177])
	garden.default_edu_levels = PackedInt32Array([0, 1])
	garden.log_series = 3
	garden.log_unlock_order = PackedInt32Array([2, 1])
	garden.finale_log_counts = PackedInt32Array([2])
	garden.log_texts = [&"The first note of the garden.", &"The second note of the garden."]
	garden.log_voices = [&"", &"no_such_group"]
	garden.supply_texts = [&"Mission control: the first bed is planted.", &"Mission control: the second bed is planted."]
	garden.supply_voices = [&"", &"no_such_group"]
	garden.finale_text = "The garden is in bloom. Well done, gardeners!"
	garden.finale_picture = "title_sky"
	return garden


## A student's campaign that can be PLAYED: it borrows the first two sectors and the finale of the campaign the chain starts with (a copy of them is
## what a student would really have), and has no closing scene, so its end is the generic finale.
static func orchard() -> Campaign:
	var first := Catalog.default_campaign()
	var orchard := Campaign.new()
	orchard.id = &"orchard"
	orchard.title = "Orchard"
	orchard.sectors = PackedInt32Array([first.sectors[0], first.sectors[1]])
	orchard.finales = PackedInt32Array([first.finales[0]])
	orchard.default_edu_levels = PackedInt32Array([0])
	orchard.log_unlock_order = PackedInt32Array([1, 2])
	orchard.finale_log_counts = PackedInt32Array([2])
	orchard.log_texts = [&"Apples.", &"Pears."]
	orchard.log_voices = [&"", &""]
	orchard.supply_texts = [&"Well picked.", &"Well picked again."]
	orchard.supply_voices = [&"", &""]
	orchard.finale_text = "The orchard is yours."
	orchard.finale_picture = "title_sky"
	return orchard
