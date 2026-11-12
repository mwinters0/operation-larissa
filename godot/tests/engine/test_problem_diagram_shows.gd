class_name TestProblemDiagramShows
extends GdUnitTestSuite
## Teaches: "it is in the tree" is not "it is on the screen". Every problem's picture is drawn by a `ModDiagram` (`DiagramFactory.create`), a `Control` that clips its children to its own rectangle; a node that is
## 0 x 0 pixels shows nothing, however well its children are made, and no log line says so (the problem screen came up with its prompt and its calculator and a blank picture). So the test asks the geometry: for
## every type of the chain the diagram has the window's size, the plain picture it holds lies inside it, and a picture takes no mouse click from the calculator under it (the lock and the ballast panels are their own input).


func test_the_diagram_of_every_problem_type_is_as_big_as_the_window() -> void:
	var host := auto_free(Control.new()) as Control
	host.size = DiagramBase.WINDOW_SIZE
	add_child(host)
	var checked := 0
	for type_id in Catalog.problem_type_ids():
		for level in 4:
			var problem := ProblemFactory.make(type_id, level, null, 0)
			if problem == null:
				continue
			var diagram := DiagramFactory.create(problem)
			host.add_child(diagram)
			var made := "type %d level %d (%s)" % [type_id, level, diagram.get_script().get_global_name()]
			assert_vector(diagram.size).override_failure_message("%s: the diagram is %s, not the window" % [made, diagram.size]).is_equal(DiagramBase.WINDOW_SIZE)
			if diagram is ModDiagram:
				assert_int(diagram.mouse_filter).override_failure_message("%s: the diagram takes the mouse" % made).is_equal(Control.MOUSE_FILTER_IGNORE)
				var plain := diagram.get_child(0) as Control
				assert_bool(Rect2(Vector2.ZERO, diagram.size).encloses(Rect2(plain.position, plain.size))).override_failure_message("%s: the plain picture lies outside the diagram that clips it" % made).is_true()
			host.remove_child(diagram)
			diagram.free()
			checked += 1
			break                                                       # (one level of each type is enough: the diagram does not depend on it)
	assert_int(checked).is_greater(10)
