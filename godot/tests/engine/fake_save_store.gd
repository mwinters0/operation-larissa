class_name FakeSaveStore
extends RefCounted
## The save store of the flow: it counts the saves and remembers what the player's record held at each one.

signal write_failed(path: String)
var watched: PlayerProfile
var saves: Array[Dictionary] = []
var hall: Array[PlayerProfile] = []


func save_roster() -> bool:
	saves.append({"progress": watched.progress, "pieces": watched.pieces_mask, "tries": watched.tries})
	return true


func add_to_hall(profile: PlayerProfile) -> void:
	hall.append(profile)


func post_write_error(queue: MessageQueue) -> MessageQueue.Message:
	return queue.post("Write Error", "The disk is full.")
