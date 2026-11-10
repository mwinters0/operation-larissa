class_name SearchAreaDiagram
extends DiagramBase
## Type 31, Search Grid (area and perimeter): the searched region built from 20 x 16 cells.
##
## Teaches: porting a drawing routine that works with a moving cursor, and how to test a drawing by
## measuring it (the tests add up the cell areas and compare with the area stored in the record).
##
## Shape codes in the record (f0): 1 = a rectangle, 2 = a right triangle, 3 = two rectangles,
## 6 = a triangle with a rectangle below. Codes 4 and 5 (shapes on the right-hand side) exist in the
## original's code but no stored record uses them, so they are not implemented.
## The triangle has its right angle at the bottom left; `f1` is its height (rows), `f2` its width (columns).
## Triangles are built row by row from the bottom: whole cells plus "hypotenuse" cells that are half filled.

var _cursor: Vector2i = Vector2i.ZERO      # top-left corner of the next cell
var _columns: int = 0                      # width of the shape being built, in cells
var _rows: int = 0                         # height of the shape being built, in cells


func _build() -> void:
	add_spec_items(spec["items"])
	var origin := _origin()
	_columns = record.int_at(2)
	_rows = record.int_at(1)
	match record.int_at(0):
		1:
			_cursor = origin
			_add_rectangle()
		2:
			_add_triangle()
		3:
			_cursor = origin
			_add_rectangle()
			_columns = record.int_at(5)
			_rows = record.int_at(4)
			# the second rectangle goes right of the first if both fit next to each other, else below it
			if record.int_at(2) + record.int_at(5) < int(spec["max_columns"]):
				_cursor = Vector2i(origin.x + record.int_at(2) * _cell().x, origin.y)
			else:
				_cursor.x = origin.x
			_add_rectangle()
		6:
			_add_triangle()
			_cursor = Vector2i(origin.x, origin.y + record.int_at(1) * _cell().y)
			_columns = record.int_at(5)
			_rows = record.int_at(4)
			_add_rectangle()


## Area of everything drawn, in cells: whole cells count 1, hypotenuse pieces (half cells) count 1/2.
func area() -> float:
	var pics: Dictionary = spec["pics"]
	var half_pics: Array = [pics["diagonal"]] + pics["steep"] + pics["half"]
	var total := 0.0
	for item in items:
		if item.kind != DiagramItem.Kind.PICTURE:
			continue
		if item.pic == pics["full"]:
			total += 1.0
		elif item.pic in half_pics:
			total += 0.5
	return total


func _origin() -> Vector2i:
	return Vector2i(spec["origin"][0], spec["origin"][1])


func _cell() -> Vector2i:
	return Vector2i(spec["cell"][0], spec["cell"][1])


func _put(pic: int, at: Vector2i) -> void:
	add_picture(pic, Vector2(at))


## `_rows` rows of `_columns` whole cells, the first row starting at the cursor. The cursor ends below the rectangle.
func _add_rectangle() -> void:
	var cell := _cell()
	for row in _rows:
		for column in _columns:
			_put(spec["pics"]["full"], _cursor + Vector2i(column * cell.x, row * cell.y))
	_cursor.y += _rows * cell.y


## A right triangle: pick the routine by its slope like the original (width = height, width = 2 x height, other).
func _add_triangle() -> void:
	var origin := _origin()
	var cell := _cell()
	_cursor = Vector2i(origin.x, origin.y + (_rows - 1) * cell.y)    # the bottom row first
	if _columns == _rows:
		_add_triangle_rows(1, 0)
	elif _rows * 2 == _columns:
		_add_triangle_rows(2, 0)
	else:
		_add_triangle_rows(1, 2)


## Builds a triangle from the bottom row up. Each row has `columns - 1` (or `- 2`) whole cells and then the hypotenuse
## piece(s); the row above is `drop` cells shorter. `pair_rows` > 0 means the width only shrinks every second row
## (steep triangles: two rows per column, the two rows use different hypotenuse pieces).
func _add_triangle_rows(drop: int, pair_rows: int) -> void:
	var origin := _origin()
	var cell := _cell()
	var pics: Dictionary = spec["pics"]
	var column := 0
	var parity := 0
	while _columns > 0:
		if column < _columns - drop:
			_put(pics["full"], _cursor)
		else:
			if drop == 2:                               # slope 1/2: the hypotenuse is two pieces side by side
				_put(pics["half"][0], _cursor)
				_put(pics["half"][1], _cursor + Vector2i(cell.x, 0))
				_columns -= 2
			elif pair_rows > 0:                         # steep: two different pieces on every second row
				parity ^= 1
				_put(pics["steep"][0 if parity == 1 else 1], _cursor)
				if parity == 0:
					_columns -= 1
			else:                                       # 45 degrees: one piece per row
				_put(pics["diagonal"], _cursor)
				_columns -= 1
			_cursor = Vector2i(origin.x - cell.x, _cursor.y - cell.y)
			column = -1
		column += 1
		_cursor.x += cell.x
