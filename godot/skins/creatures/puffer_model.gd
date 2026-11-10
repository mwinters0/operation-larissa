class_name PufferModel
extends Node3D
## A puffer fish as a 3D model made of Godot's own primitive meshes (no model file): an ellipsoid body (`SphereMesh` scaled), a tail and
## fins (`PrismMesh`, flattened `SphereMesh`), eyes, blue dots, and spines (`CylinderMesh` with a point). One unit is one pixel of the
## original's 80 x 48 picture, the fish is about 70 x 44 units when it is puffed up, and it faces -X (to the left, like the original's
## picture, which `PufferRig3D` mirrors by turning the model round).
##
## `pose(...)` is the whole animation: how puffed up (0 slim .. 1 puffed), what time it is (the fins and the tail wave with it), how fast
## the fish swims (it waves faster) and which way it faces. Nothing here knows a rule or a skin: it is a model that is told a pose.
##
## Teaches: building a 3D scene from code with primitive meshes and `StandardMaterial3D`; non-uniform scale for an ellipsoid, and keeping the
## things that sit on the surface unscaled by placing them by hand (`_on_surface`) so they are not squashed with the body; a pivot node
## per moving part (the tail and the fin turn about their root, not their middle).

const YELLOW := Color(0.93, 0.82, 0.12)
const DARK_YELLOW := Color(0.75, 0.62, 0.08)
const GREEN := Color(0.2, 0.62, 0.18)
const BLUE := Color(0.38, 0.42, 0.88)

## The body's radii (x along the fish, y up, z through it), slim and puffed up. The picture is 80 x 48, so y stays under 24.
const SLIM := Vector3(27.0, 11.0, 10.0)
const PUFFED := Vector3(29.0, 21.5, 20.0)
## Where the middle of the body is on x, slim and puffed up (the tail stays at the back, the nose goes forward as it swells).
const SLIM_X := -8.0
const PUFFED_X := -5.0
## Spines are directions on the body (a fixed spread of points over the sphere, `_spine_directions`).
const SPINE_COUNT := 20

var _body: MeshInstance3D
var _tail_pivot: Node3D
var _fin_pivot: Node3D
var _bottom_fin: MeshInstance3D
var _top_fin: MeshInstance3D
var _eyes: Array[Node3D] = []                  # (one on each side of the head)
var _dots: Array[MeshInstance3D] = []
var _spines: Array[MeshInstance3D] = []
var _dot_directions: Array[Vector3] = []
var _spine_directions: Array[Vector3] = []
var _eye_direction := Vector3(-0.55, 0.3, 0.78).normalized()


func _init() -> void:
	_body = _mesh(SphereMesh.new(), YELLOW)
	var sphere := _body.mesh as SphereMesh
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 40
	sphere.rings = 20
	add_child(_body)
	_tail_pivot = Node3D.new()                  # the tail turns about its root, at the back of the body
	add_child(_tail_pivot)
	_tail_pivot.add_child(_flat_prism(26.0, 17.0, 2.0, GREEN))
	_fin_pivot = Node3D.new()                   # the side fin, at the root of it
	add_child(_fin_pivot)
	_fin_pivot.add_child(_blob(Vector3(11.0, 6.5, 1.6), GREEN, Vector3(-8.0, 0.0, 0.0)))
	_bottom_fin = _blob(Vector3(7.0, 3.0, 1.6), GREEN)
	add_child(_bottom_fin)
	_top_fin = _blob(Vector3(6.0, 4.0, 1.4), GREEN)
	add_child(_top_fin)
	for side in [1.0, -1.0]:                     # an eye on each side: white, a blue iris, a black pupil (each a flat ball, "out" is +Y)
		var eye := Node3D.new()
		eye.add_child(_blob(Vector3(8.0, 4.0, 8.0), Color(0.97, 0.97, 0.97)))
		eye.add_child(_blob(Vector3(5.4, 2.6, 5.4), BLUE, Vector3(0.0, 1.9, 0.0)))
		eye.add_child(_blob(Vector3(2.8, 1.8, 2.8), Color(0.05, 0.05, 0.1), Vector3(0.0, 3.4, 0.0)))
		add_child(eye)
		_eyes.append(eye)
	_spine_directions = _spread(SPINE_COUNT, 0.0)
	for direction in _spine_directions:
		var spine := _mesh(CylinderMesh.new(), DARK_YELLOW)
		var cone := spine.mesh as CylinderMesh
		cone.top_radius = 0.0
		cone.bottom_radius = 2.0
		cone.height = 9.0
		cone.radial_segments = 8
		add_child(spine)
		_spines.append(spine)
	for direction in _spread(14, 0.3):           # blue dots on the belly and the flanks
		_dot_directions.append(direction)
		var dot := _blob(Vector3.ONE, BLUE)
		add_child(dot)
		_dots.append(dot)
	pose(0.0, 0.0, 0.0, 0.0)


## Puts the model in a pose. `inflate`: 0 slim .. 1 puffed up. `time`: seconds (the waving). `swim`: 0 hovering .. 1 swimming hard.
## `heading`: the turn about the vertical axis in radians (0 = faces left; PI = faces right; a little more or less shows the near side).
func pose(inflate: float, time: float, swim: float, heading: float) -> void:
	var radii := SLIM.lerp(PUFFED, inflate)
	var centre := Vector3(lerpf(SLIM_X, PUFFED_X, inflate), 0.0, 0.0)
	_body.position = centre
	_body.scale = radii
	rotation.y = heading
	var wave := lerpf(5.0, 11.0, swim)           # (radians per second of the tail and the fin)
	# The tail: at the back of the body, wagging about two axes so it reads from the side as well.
	_tail_pivot.position = centre + Vector3(radii.x - 3.0, 0.0, 0.0)
	_tail_pivot.rotation = Vector3(0.0, sin(time * wave) * 0.55, sin(time * wave + 0.6) * lerpf(0.12, 0.25, swim))
	# The side fins: at the middle of the flank, beating.
	_fin_pivot.position = centre + _on_surface(Vector3(0.15, -0.15, 1.0), radii) + Vector3(0.0, 0.0, 0.5)
	_fin_pivot.rotation = Vector3(0.0, 0.0, sin(time * (wave + 2.0)) * 0.45)
	_bottom_fin.position = centre + _on_surface(Vector3(0.55, -1.0, 0.1), radii)
	_top_fin.position = centre + _on_surface(Vector3(0.35, 1.0, 0.0), radii)
	_top_fin.rotation.z = sin(time * wave) * 0.2
	for i in _eyes.size():
		var direction := Vector3(_eye_direction.x, _eye_direction.y, _eye_direction.z * (1.0 if i == 0 else -1.0))
		_eyes[i].position = centre + _on_surface(direction, radii)
		_look_outwards(_eyes[i], _normal(direction, radii), Vector3.ONE)
	for i in _dots.size():
		var surface := _on_surface(_dot_directions[i], radii)
		_dots[i].position = centre + surface
		_look_outwards(_dots[i], _normal(_dot_directions[i], radii), Vector3(2.2, 0.8, 2.2))
	# The spines grow out of the body as it puffs up: none at all while it is slim.
	var grown := clampf((inflate - 0.35) / 0.65, 0.0, 1.0)
	for i in _spines.size():
		var direction := _spine_directions[i]
		var spine := _spines[i]
		spine.visible = grown > 0.01
		spine.position = centre + _on_surface(direction, radii)
		_look_outwards(spine, _normal(direction, radii), Vector3.ONE * grown)


## The point of the ellipsoid with radii `radii` in `direction` (not normalised): where something that sits on the fish goes.
func _on_surface(direction: Vector3, radii: Vector3) -> Vector3:
	var unit := direction.normalized()
	# A point on the ellipsoid along `unit`: scale the unit vector so (x/rx)^2 + (y/ry)^2 + (z/rz)^2 = 1.
	var factor := 1.0 / sqrt(pow(unit.x / radii.x, 2.0) + pow(unit.y / radii.y, 2.0) + pow(unit.z / radii.z, 2.0))
	return unit * factor


## The direction the ellipsoid's surface faces at the point in `direction` (its normal is the point divided by the radii squared).
func _normal(direction: Vector3, radii: Vector3) -> Vector3:
	var point := _on_surface(direction, radii)
	return Vector3(point.x / (radii.x * radii.x), point.y / (radii.y * radii.y), point.z / (radii.z * radii.z)).normalized()


## Turns `node` so that its +Y (the tip of a cone, the "out" of a flat dot) points along `normal`, and sizes it by `size` (in its own axes).
func _look_outwards(node: Node3D, normal: Vector3, size: Vector3) -> void:
	var up := normal.normalized()
	var across := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var along := across.cross(up).normalized()
	node.basis = Basis(across, up, along) * Basis.from_scale(size)


## `count` directions spread evenly over a sphere (a Fibonacci spiral); `from_bottom` (0..1) leaves out that much of the top: 0 = all of it.
func _spread(count: int, from_bottom: float) -> Array[Vector3]:
	var directions: Array[Vector3] = []
	var golden := PI * (3.0 - sqrt(5.0))
	for i in count:
		var y := 1.0 - 2.0 * (i + 0.5) / count
		y = lerpf(y, -absf(y), from_bottom)                       # (towards the lower half)
		var ring := sqrt(maxf(0.0, 1.0 - y * y))
		directions.append(Vector3(cos(golden * i) * ring, y, sin(golden * i) * ring))
	return directions


# --- parts ---------------------------------------------------------------------------------------------

func _mesh(mesh: Mesh, colour: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.55
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	return instance


## A flattened ball: a `SphereMesh` of radius 1 scaled to `radii` and put `offset` away from its pivot.
func _blob(radii: Vector3, colour: Color, offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var blob := _mesh(SphereMesh.new(), colour)
	(blob.mesh as SphereMesh).radial_segments = 16
	(blob.mesh as SphereMesh).rings = 8
	blob.scale = radii
	blob.position = offset
	return blob


## A flat triangle that widens towards +X (a tail): a `PrismMesh` laid on its side, with its point at the pivot.
func _flat_prism(width: float, length: float, depth: float, colour: Color) -> MeshInstance3D:
	var prism := PrismMesh.new()
	prism.size = Vector3(width, length, depth)   # (x: the base, y: the height, z: the thickness)
	var instance := _mesh(prism, colour)
	instance.rotation.z = PI / 2.0              # the point (+Y) now looks along -X, at the body
	instance.position = Vector3(length / 2.0, 0.0, 0.0)
	return instance
