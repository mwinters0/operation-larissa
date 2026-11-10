class_name SpriteMeta
extends RefCounted
## Builds the combined sprite metadata table a zone's creatures use.
##
## A foe's frame number indexes: 28 common creatures, then 7 ink-burst frames,
## then the zone's own creatures (DESIGN section 9). This class concatenates
## the three SpriteMetaTable files in that order.

## Where the tables are in a pack (the first pack of the chain that provides a file answers, `Packs.resource`).
const DIR_REL := "data/sprite_meta/"

static var _zone_cache: Dictionary = {}


## Forget the tables read so far (`Catalog.packs_changed`: another pack is in use).
static func forget() -> void:
	_zone_cache = {}


static func for_zone(zone_index: int) -> SpriteMetaTable:
	if _zone_cache.has(zone_index):
		return _zone_cache[zone_index]
	var combined := SpriteMetaTable.new()
	for part: SpriteMetaTable in [
			Packs.resource(DIR_REL + "sprite_meta_common.tres"),
			Packs.resource(DIR_REL + "sprite_meta_ink.tres"),
			Packs.resource(DIR_REL + "sprite_meta_zone%d.tres" % zone_index)]:
		combined.sizes.append_array(part.sizes)
		combined.hit_rects.append_array(part.hit_rects)
		combined.hit_rects_flipped.append_array(part.hit_rects_flipped)
	_zone_cache[zone_index] = combined
	return combined
