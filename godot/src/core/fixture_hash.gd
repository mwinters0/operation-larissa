@tool
class_name FixtureHash
extends RefCounted
## SHA-256 of a record, in the form the committed fixtures keep it.
##
## Teaches: why a fixture commits HASHES and not bytes (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes"). A hash
## proves that an encoder gives back exactly the original record without the repository holding the original's content;
## the bytes behind it are written by the importer from your own copy of the game into the git-ignored folder
## `tests/fixtures/original/`, for the tests that want to name the first differing field. Hash a WHOLE record (one
## sector header, one screen, one script), never a single field: a hash of a one- or two-byte field can be reversed by
## trying every value.
##
## tools/import/common.py `sha256_hex` computes the same value in Python; the two must agree.
## `@tool` because the editor plugins (the screen editor, the Foe Script screen) compare a screen or a script with the hash.

## Folder of the files that hold original bytes (written by the importer, not committed).
const ORIGINAL_DIR := "res://tests/fixtures/original/"


## Lower-case hex SHA-256 of `bytes`.
static func sha256_hex(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()
