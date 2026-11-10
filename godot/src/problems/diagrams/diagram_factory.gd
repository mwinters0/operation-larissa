class_name DiagramFactory
extends RefCounted
## Creates the diagram control of a problem type from the "family" its spec names.
##
## Teaches: the factory pattern with a plain `match` on a string coming from data. Adding a family
## means a new subclass of `DiagramBase` and one line here.

## A set-up diagram for `problem`, ready to be added to the scene tree.
static func create(problem: ProblemInstance) -> DiagramBase:
	var diagram := _new_for(problem.type.diagram["family"])
	diagram.setup(problem)
	return diagram


static func _new_for(family: String) -> DiagramBase:
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
		"mod": return ModDiagram.new()           # a mod draws it (`ModProblems`); the plain picture of the data is what shows without the mod
	push_error("DiagramFactory: unknown diagram family '%s'" % family)
	return DiagramBase.new()
