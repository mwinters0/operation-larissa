class_name Main
extends Node
## The run scene's root: hands over to the opening sequence as soon as the game has started.
##
## Teaches: the project's main scene is just a scene like any other (Project Settings > Application > Run
## > Main Scene). `SceneRouter` (an autoload) does the switching with a fade, so this script has one line of
## real work. Scene flow of the whole game:
##
##     main -> [pack warning, when the chain is not whole] -> opening (title, story; skippable) -> sign-in -> game (sectors, finale, closing) -> Hall of Fame -> sign-in
##                                                    \-> practice mode -> sign-in
##
## The pack is chosen first (`Packs.start`: `--pack=<id>` after `--`, else the first pack found, and the packs it is laid over), before any screen asks for a sector
## or a picture. When the chain could not be made or lacks what the game needs, `Packs.fallback_reason()` says why and the game opens on the warning screen
## (`PackWarning`) before everything else: with `dev` at the bottom of the chain and a key to go on (`Packs.dev_fallback`, a debug build), or as a refusal that quits
## (`Packs.is_refused()`). `--pack=dev` is a choice, not a fallback, and opens on the title as usual.


func _ready() -> void:
	Packs.start()
	SceneRouter.go_to.call_deferred(first_scene())


## The scene the game opens on: the warning when the chain is not whole, else the opening sequence.
static func first_scene() -> String:
	return SceneRouter.PACK_WARNING if Packs.fallback_reason() != null else SceneRouter.OPENING
