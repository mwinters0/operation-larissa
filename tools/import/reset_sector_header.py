"""Reset the header of original sectors (start, neighbours, pieces) back to the ORIGINAL.

    uv run tools/import/reset_sector_header.py --all     # all 32 sectors
    uv run tools/import/reset_sector_header.py 3 7       # sectors 3 and 7

The header fields of the legacy pack's data/sectors/sector_NN/sector_NN.tres are the stored version designers edit (the Inspector,
or the screen editor for pieces): start_pos, start_frame, neighbors_left / right / up / down, pieces (the PieceData
sub-resources), stale_pieces and header_unused_3d / 40 / 41. This tool is the way back to the original. It reads the
original 0x72 header bytes that the importer wrote from YOUR copy of the game (godot/tests/fixtures/original/
sector_headers.json, git-ignored), decodes them with sector_header.py (the code the importer uses) and patches exactly those
fields into the existing .tres, in the importer's format. Everything else in the file stays as it is: the creatures and their
labels, the screens, the script, index / game / zone / music, the uids. The screens (reset_screens.py) and the creature
scripts (reset_foe_scripts.py) have their own tools, which this one never touches.

Two checks make sure the result is the original and not just something that looks like it:
  * the original bytes must hash to the SHA-256 committed in godot/tests/fixtures/sector_headers.json (a different release
    of the game, or a patched copy, is refused: the hashes do not come from your copy);
  * the file just written is read back, its fields are encoded to the 0x72 header bytes again, and those must hash to the
    same committed SHA-256 as well.

If the original bytes are missing, the tool stops with "run the importer on your copy of the game". (the legacy pack is not in version control, so there
is no restoring these files from it: this tool, or `import_all.py --only sectors`, is the way back to the original. This tool keeps your other
edits of the file: creature edits, a changed script label.)

Not the same as `import_all.py --only sectors`, which rewrites the WHOLE sector files from extracted/.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import sector_header
import tres
from common import PACK_DATA, ORIGINAL_SECTOR_COUNT, sector_file, sha256_hex

SECTOR_DIR = PACK_DATA / "sectors"
PIECE_SCRIPT = "res://src/resources/piece_data.gd"

HOW_TO_FIX = "run the importer on your copy of the game (uv run tools/import/import_all.py)"


def load_original_headers(raw_fixture: Path = sector_header.RAW_FIXTURE,
                          hash_fixture: Path = sector_header.HASH_FIXTURE) -> dict[int, tuple[bytes, str]]:
    """sector -> (the original 0x72 header bytes, their committed SHA-256). Refuses with the importer hint when the bytes
    are missing, and when they do not hash to the committed value."""
    if not raw_fixture.exists():
        raise ValueError("%s is missing. It holds the original sector headers and is written by the importer from your "
                         "copy of the game: %s." % (raw_fixture, HOW_TO_FIX))
    if not hash_fixture.exists():
        raise ValueError("%s is missing (it is committed): restore it with git." % hash_fixture)
    hashes = {e["index"]: e["header_sha256"] for e in json.loads(hash_fixture.read_text())["sectors"]}
    out = {}
    for entry in json.loads(raw_fixture.read_text())["sectors"]:
        raw = bytes.fromhex(entry["header_hex"])
        if entry["index"] not in hashes or sha256_hex(raw) != hashes[entry["index"]]:
            raise ValueError("sector %d: the header bytes in %s do not match the SHA-256 committed in %s. Your copy of the "
                             "game is a different version or patched, or the file was edited: %s."
                             % (entry["index"], raw_fixture.name, hash_fixture.name, HOW_TO_FIX))
        out[entry["index"]] = (raw, hashes[entry["index"]])
    return out


def refuse_new_sectors(sectors: list[int], known: list[int]) -> str:
    """"" when every sector has an original header, else the message that says which have not."""
    new = [n for n in sectors if n not in known]
    if not new:
        return ""
    return ("sector%s %s ha%s no original header: a new sector's .tres is its own source, so there is nothing to reset"
            % ("s" if len(new) > 1 else "", ", ".join(map(str, new)), "ve" if len(new) > 1 else "s"))


# ---- reading the fields back out of a .tres --------------------------------

def read_header(text: str) -> dict:
    """The header fields of a sector .tres in the form of sector_header.decode_header(), so that encode_header() can turn
    them into bytes. A property the file does not list has its default (Godot leaves default values out when it saves)."""
    blocks = tres.split_blocks(text)
    resource = tres.property_values(blocks[-1].split("\n"))
    subs = {tres.sub_resource_id(b): tres.property_values(b.split("\n")) for b in blocks if tres.sub_resource_id(b)}
    pieces = []
    for sub_id in re.findall(r'SubResource\("([^"]+)"\)', resource.get("pieces", "")):
        piece = subs[sub_id]
        pieces.append((int(piece.get("screen", "0")),) + tuple(tres.ints_in(piece.get("pos", "Vector2i(0, 0)"))))
    stale = tres.ints_in(resource.get("stale_pieces", ""))
    return {
        "start_pos": tuple(tres.ints_in(resource.get("start_pos", "Vector2i(0, 0)"))),
        "start_frame": int(resource.get("start_frame", "0")),
        "pieces": pieces,
        "stale_pieces": [tuple(stale[k:k + 4]) for k in range(0, len(stale), 4)],
        "header_unused_3d": int(resource.get("header_unused_3d", "0")),
        "header_unused_40": int(resource.get("header_unused_40", "0")),
        "header_unused_41": int(resource.get("header_unused_41", "0")),
        "neighbors": {side: tres.ints_in(resource.get("neighbors_" + side, "")) for side in sector_header.SIDES},
    }


def header_hash(text: str) -> str:
    """SHA-256 of the 0x72 header bytes that the fields of the .tres text encode to (ValueError if they cannot be encoded)."""
    return sha256_hex(sector_header.encode_header(read_header(text)))


# ---- writing them ----------------------------------------------------------

def _piece_block(sub_id: str, script_id: str, piece: tuple[int, int, int], k: int) -> str:
    screen, x, y = piece
    return "\n".join(['[sub_resource type="Resource" id="%s"]' % sub_id, 'script = ExtResource("%s")' % script_id,
                      "screen = %d" % screen, "pos = %s" % tres.vec2i(x, y), "is_canister = %s" % tres.b(k == 0)])


def patch_text(text: str, header: dict) -> str:
    """The .tres text with the header fields replaced by `header` (decode_header()'s dict); all else kept. The pieces are
    rewritten as [sub_resource] blocks in place (the ids of the old ones are reused, new ones get the next free number)."""
    blocks = tres.split_blocks(text)
    if not blocks[-1].startswith("[resource]"):
        raise ValueError("the last block is not [resource]")
    match = re.search(r'\[ext_resource [^\]]*path="%s" id="([^"]+)"\]' % re.escape(PIECE_SCRIPT), "\n".join(blocks))
    if not match:
        raise ValueError("the file does not use %s" % PIECE_SCRIPT)
    script_id = match.group(1)
    lines = blocks[-1].split("\n")

    # the pieces: sub_resource blocks, listed by the `pieces` line
    at = tres.property_line(lines, "pieces")
    old_ids = re.findall(r'SubResource\("([^"]+)"\)', lines[at]) if at is not None else []
    block_of = {i: k for k, b in enumerate(blocks) if (i := tres.sub_resource_id(b))}
    if any(i not in block_of for i in old_ids):
        raise ValueError("a piece in the `pieces` line has no [sub_resource] block")
    used = [int(m.group(1)) for i in block_of if (m := re.search(r"_(\d+)$", i))]
    free = iter(range(max(used, default=0) + 1, 10 ** 6))
    new_ids = old_ids[:len(header["pieces"])]
    new_ids += ["Piece_%d" % next(free) for _ in range(len(header["pieces"]) - len(new_ids))]
    new_blocks = [_piece_block(i, script_id, p, k) for k, (i, p) in enumerate(zip(new_ids, header["pieces"]))]

    # all the pieces go where the first old one was (they are one run in practice); with none before, in front of the first
    # other sub_resource, or of [resource]
    old_at = {block_of[i] for i in old_ids}
    insert_at = min(old_at) if old_at else next((k for k, b in enumerate(blocks) if tres.sub_resource_id(b)), len(blocks) - 1)
    out = []
    for k, block in enumerate(blocks[:-1]):
        if k == insert_at:
            out += new_blocks
        if k not in old_at:
            out.append(block)
    if insert_at == len(blocks) - 1:
        out += new_blocks
    out.append("\n".join(_patch_resource_lines(lines, header, script_id, new_ids)))
    return tres.join_blocks(out)


GROUP_A = ("start_pos", "start_frame", "neighbors_left", "neighbors_right", "neighbors_up", "neighbors_down", "pieces",
           "stale_pieces")
GROUP_B = ("header_unused_3d", "header_unused_40", "header_unused_41")


def _patch_resource_lines(lines: list[str], header: dict, script_id: str, piece_ids: list[str]) -> list[str]:
    """The lines of the [resource] block with the header properties set. A property the file lacks is inserted where the
    importer puts it (after the previous header property, or after zone; the header_unused_* at the end); stale_pieces is
    only there when there are stale entries."""
    values = {"start_pos": tres.vec2i(*header["start_pos"]), "start_frame": str(header["start_frame"]),
              "pieces": tres.array('ExtResource("%s")' % script_id, ['SubResource("%s")' % i for i in piece_ids]),
              "stale_pieces": tres.packed_ints(v for entry in header["stale_pieces"] for v in entry) if header["stale_pieces"] else None}
    for side in sector_header.SIDES:
        values["neighbors_" + side] = tres.packed_ints(header["neighbors"][side])
    for name in GROUP_B:
        values[name] = str(header[name])
    lines = list(lines)
    anchor = next((k for key in ("zone", "game", "index", "script") if (k := tres.property_line(lines, key)) is not None), 0)
    for key in GROUP_A + GROUP_B:
        at = tres.property_line(lines, key)
        value = values[key]
        if value is None:
            if at is not None:
                del lines[at]
            continue
        line = "%s = %s" % (key, value)
        if at is not None:
            lines[at] = line
        else:
            at = len(lines) if key in GROUP_B else anchor + 1
            lines.insert(at, line)
        if key in GROUP_A:
            anchor = at
    return lines


def reset_sector(path: Path, header_bytes: bytes, expected_hash: str) -> bool:
    """Reset one sector's header in place. True if the file changed. The text is checked against `expected_hash` before it
    is written and the file is read back and checked again after."""
    old = path.read_text()
    new = patch_text(old, sector_header.decode_header(header_bytes))
    if header_hash(new) != expected_hash:
        raise ValueError("%s: the patched fields do not encode to the committed header hash; nothing written" % path)
    if new == old:
        return False
    path.write_text(new)
    if header_hash(path.read_text()) != expected_hash:
        raise ValueError("%s: the file written does not encode to the committed header hash" % path)
    return True


def run(sectors: list[int], sector_dir: Path = SECTOR_DIR, raw_fixture: Path = sector_header.RAW_FIXTURE,
        hash_fixture: Path = sector_header.HASH_FIXTURE) -> None:
    problem = refuse_new_sectors(sectors, list(range(ORIGINAL_SECTOR_COUNT)))      # before anything is read
    if problem:
        raise ValueError(problem)
    originals = load_original_headers(raw_fixture, hash_fixture)
    problem = refuse_new_sectors(sectors, sorted(originals))
    if problem:
        raise ValueError(problem)
    for n in sectors:
        raw, expected = originals[n]
        changed = reset_sector(sector_file(n, "tres", sector_dir), raw, expected)
        print("  sector %2d: %s" % (n, "header reset to the original (hash checked)" if changed
                                    else "header already original, unchanged"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Reset sector headers to the original (see the module docstring).")
    parser.add_argument("sectors", nargs="*", type=int, help="sector numbers (of the original sectors)")
    parser.add_argument("--all", action="store_true", help="reset every sector")
    args = parser.parse_args()
    if args.all == bool(args.sectors):
        parser.error("name some sectors, or give --all (not both)")
    try:
        chosen = list(range(ORIGINAL_SECTOR_COUNT)) if args.all else sorted(set(args.sectors))
        run(chosen)
    except ValueError as error:
        parser.error(str(error))


if __name__ == "__main__":
    main()
