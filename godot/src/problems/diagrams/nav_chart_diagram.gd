class_name NavChartDiagram
extends DiagramBase
## Type 9, Navigation Chart: markers for the sub and for the station on a map of longitude and latitude.
##
## Teaches: mapping data coordinates to screen pixels with a linear formula whose constants come
## from the importer (the original computes `x = (trunc((180 - longitude) * 20) + 43) * 2`).


func _build() -> void:
	add_spec_items(spec["items"])
	var map: Dictionary = spec["map"]
	for marker: Dictionary in spec["markers"]:
		add_picture(marker["pic"], marker_position(map, record.value_at(marker["lon_field"]), record.value_at(marker["lat_field"])))


## Window position of the marker for (longitude, latitude); longitudes grow to the LEFT (degrees west).
static func marker_position(map: Dictionary, longitude: float, latitude: float) -> Vector2:
	var offset: Array = map["offset"]
	var zoom: int = map["zoom"]
	var x: int = (int((map["lon_origin"] - longitude) * map["lon_scale"]) + int(offset[0])) * zoom
	var y: int = (int((latitude - map["lat_origin"]) * map["lat_scale"]) + int(offset[1])) * zoom
	return Vector2(x, y)
