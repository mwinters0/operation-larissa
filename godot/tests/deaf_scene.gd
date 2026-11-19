class_name DeafScene
extends RefCounted
## A closing scene that is deaf until its verb `listen`, for the tests of that mechanism: written into a scratch pack (`PackShelf`) over dev, which holds none (dev's one closing is not deaf). The scene stands on dev's closing stage and plays dev's film, then a
## wait that loops until a key: its first moment says `listen`, from which a key or a click ends the scene. `tests/engine/test_closing_scene.gd` (the mechanism, through the segment and through `Game`) and `test_opening_list.gd` (a part that drops Space) play it.
##
## Teaches: a test builds the scene shape it needs as data in a scratch pack instead of asking a shipped pack to hold it for the tests' sake: no file of dev exists only to be named.

## The scene and its second timeline, as the scratch pack names them.
const SCENE := &"zz_deaf_closing"
const WAIT := &"zz_deaf_wait"


## Writes the scene and its wait into `shelf` (the pack is mounted afterwards by the caller). The scene is a closing laid over the sector: no backdrop, the song `closing`, deaf until `listen`, played in turn: dev's film, then the wait.
static func write(shelf: PackShelf) -> void:
	var wait := CutsceneTimeline.made_in_code(48.0, "a wait for a key: the lamp blinks until one is pressed", true)
	wait.track(&"lamp", CutsceneTrack.PROP_PICTURE, [[0.0, &"deck_pod_0"], [12.0, &"deck_pod_1"], [24.0, &"deck_pod_2"], [36.0, &"deck_pod_1"]])
	wait.cue(0.0, CutsceneCue.EVENT, &"listen")
	shelf.write_json("data/story/%s.json" % WAIT, ResourceJson.new().data_of(wait))
	var scene := StoryScene.new()
	scene.stage = &"dev_closing_stage"
	scene.timelines = [&"dev_closing_film", WAIT]
	scene.backdrop = false
	scene.deaf_until_listen = true
	scene.song = &"closing"
	shelf.write_json("data/story/%s.json" % SCENE, ResourceJson.new().data_of(scene))
