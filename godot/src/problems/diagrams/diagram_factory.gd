class_name DiagramFactory
extends RefCounted
## Creates the diagram control of a problem type from the "family" its spec names: THE one place that decides which diagram draws a type. Every type whose answer the engine's own input does not take is wrapped in a `ModDiagram`, the one node
## that asks whether a mod draws the screen (`ModHost.problem_screen`, a type a pack adds with the family `mod` or an original type a running mod opted in to draw by number) and, whenever it does not, shows the diagram of the family
## (`plain`) it holds. The lock and the ballast panels (`takes_input`) are their own diagrams: the engine draws them, whatever a mod lists.
##
## Teaches: the factory pattern with a plain `match` on a string coming from data. Adding a family
## means a new subclass of `DiagramBase` and one line here.

## The families whose diagram is also the player's input (the lock's wheels, the ballast panel's buttons): the engine draws them, whatever a mod lists.
const INPUT_FAMILIES: Array[String] = ["lock", "ballast_panel"]


## A set-up diagram for `problem`, ready to be added to the scene tree.
static func create(problem: ProblemInstance) -> DiagramBase:
	if takes_input(family_of(problem.type)):
		return plain(problem)
	var diagram := ModDiagram.new()
	diagram.setup(problem)
	return diagram


## The set-up diagram the type's data names, whatever a mod does: what a `ModDiagram` shows and plays under (and instead of) its mod's layers, and the diagram of a lock or a ballast panel.
static func plain(problem: ProblemInstance) -> DiagramBase:
	var diagram := _new_for(family_of(problem.type), problem.type.id)
	diagram.setup(problem)
	return diagram


## The family the type's data names ("" when it names none: a type a pack adds with no `family` in its `diagram`; `_new_for` says what the player sees then).
static func family_of(type: ProblemType) -> String:
	return String(type.diagram.get("family", ""))


## Is a type of this diagram family answered through its diagram (the lock, the ballast panel), so that no mod draws it?
static func takes_input(family: String) -> bool:
	return INPUT_FAMILIES.has(family)


static func _new_for(family: String, type_id: int = -1) -> DiagramBase:
	match family:
		"items": return DiagramBase.new()
		"sonar": return SonarDiagram.new()
		"nav_chart": return NavChartDiagram.new()
		"barnacles": return BarnacleDiagram.new()
		"pie": return PieDiagram.new()
		"ruler": return RulerDiagram.new()
		"tank": return TankDiagram.new()
		"line_graph": return LineGraphDiagram.new()
		"storage_boxes": return StorageBoxesDiagram.new()
		"search_area": return SearchAreaDiagram.new()
		"search_grid": return SearchGridDiagram.new()
		"ballast_panel": return BallastPanelDiagram.new()
		"lock": return LockDiagram.new()
		"mod": return DiagramBase.new()          # a type a pack adds for a mod to draw (`ModProblems`): its plain picture is the generic `items` of the data
	TroubleLog.session.tell("[problems] problem type %d: its diagram %s, so its picture is the plain list of items of its data" % [
			type_id, "family '%s' is not one the game draws" % family if not family.is_empty() else "names no family"])
	return DiagramBase.new()
