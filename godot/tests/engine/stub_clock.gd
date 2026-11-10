class_name StubClock
extends RefCounted
## Stands in for the `GameClock` a `MessageQueue` listens to and holds while a message is up. (A plain object: all the queue asks of a
## clock is a `tick` signal and `hold()` / `release()`.)

signal tick(count: int)
var holds: int = 0


func hold() -> void:
	holds += 1


func release() -> void:
	holds -= 1
