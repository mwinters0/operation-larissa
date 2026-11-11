"""Step 'sectors': sector_NN.tres, zones.tres, trigger_table.tres (from the tables of extracted/tables/)."""
# WARNING: re-running this step OVERWRITES edits to the creature scripts. The text in
# the legacy pack's data/sectors/sector_NN/sector_NN.foe (the script) and the foe start/hit/ink labels in sector_NN.tres are the STORED
# version that designers edit; this step is only for the first creation or a full reset, and it rewrites whole
# files from extracted/ (its tables/ too). To reset just the scripts, use tools/import/reset_foe_scripts.py
# (docs/create/FOE_SCRIPTING.md). The designers' label names and comments (godot/data/sectors/foe_annotations.json,
# foe_annotations.py) are NOT lost by this step: the text is written with them and the labels follow the renames.
# The same holds for the screens (the legacy pack's data/sectors/sector_NN/screen_MM.tres): they are the stored version designers
# edit (the screen editor, docs/create/SCREEN_EDITOR.md). To reset only them, use tools/import/reset_screens.py.
# And the header fields of sector_NN.tres (start, neighbours, pieces) and the creatures' record fields: reset_sector_header.py and
# reset_foe_scripts.py --records.
from __future__ import annotations

from pathlib import Path

from common import (PACK_DATA, TABLES, ORIGINAL_SECTOR_COUNT, ZONE_BANNER_IDS,
                    SCREENS, ZONE_DECO_COUNTS, ZONE_FOE_COUNTS, ZONE_TITLES, load_json, out_text, res_path, sector_file)
from pictures import ui_file
import foe_annotations
import foe_record
import foe_script
import ds_tables
import foe_names
import foe_text
from foe_names import sector_zone      # index into zones.tres: 0-4 normal zones, 5 = Voyager finale, 6 = Expert finale
import screen_record
import sector_header
import tres

# The fixtures of the original (docs/port/FIDELITY.md, "Fixtures commit hashes, not bytes") all have the same form: a committed file
# with provenance and SHA-256 hashes, and the original bytes in a git-ignored file. Sector headers: sector_header.py;
# creature records: foe_record.py; creature scripts: foe_script.py; screens: screen_record.py; trigger table and default
# educational levels: ds_tables.py (written here, with zones.tres and trigger_table.tres); sprite metadata: sprite_meta.py (step sprites).

SCRIPTS = "res://src/resources/"


def sector_game(i: int) -> int:
    """0 = Voyager, 1 = Expert."""
    return {30: 0, 31: 1}.get(i, i // 15)


def music_name(i: int) -> str:
    """The stem of the sector's MIDI song: SelectSectorMusic (0x43200f) plays `esect<n>` by `sector % 6` and the finale song (eend) in both finales."""
    return "eend" if i >= 30 else "esect%d" % (i % 6 + 1)


def finale_screen(i: int) -> int:
    """The screen where the closing sequence starts: DoAction hard-codes screen 2 for sector 30 and screen 10 for sector 31; -1 (the
    default, not written) for every other sector."""
    return {30: 2, 31: 10}.get(i, -1)


def build_screen_files(sec: dict) -> list[str]:
    """The text of sector_NN/screen_00.tres .. screen_11.tres, built from the original record bytes."""
    texts = []
    for k, sc in enumerate(sec["screens"]):
        screen = screen_record.decode_record(screen_record.original_record(sec, k))
        # The decoded lists in sectors.json (tools/analysis/neptune_data.py) and this decoder read the same bytes.
        assert screen["tiles"] == sc["tiles"] and screen["used"] == sc["used"], "record_hex and decoded fields disagree"
        assert [tuple(x) for x in sc["math_triggers"]] == screen["math_triggers"]
        assert [bytes.fromhex(h) for h in sc["anim_decos"]] == screen["anim_decos"]
        texts.append(screen_record.build_screen(screen, sec["index"], k))
    return texts


def build_sector(sec: dict, annotations: dict | None = None) -> tuple[str, str]:
    """(text of sector_NN.tres, text of sector_NN.foe). `annotations`: the sector's stored label names and comments."""
    t = tres.Tres("Resource", "SectorData", SCRIPTS + "sector_data.gd")
    ids = {n: t.ext_id("Script", SCRIPTS + n + ".gd") for n in
           ("piece_data", "foe_data", "screen_data")}

    # Each screen lives in its own file, sector_NN/screen_MM.tres (build_screen_files); the sector only points at them.
    screen_refs = [t.ext_ref("Resource", screen_record.screen_res_path(sec["index"], k)) for k in range(len(sec["screens"]))]

    # The header comes from the RAW sector resource, the same bytes as the screen records (sector_header.py), not from the
    # converted values in sectors.json.
    header = sector_header.decode_header(sector_header.original_resource(sec))
    pieces = [t.sub("Resource", [("screen", str(sc)), ("pos", tres.vec2i(x, y)), ("is_canister", tres.b(k == 0))],
                    script=SCRIPTS + "piece_data.gd", prefix="Piece")
              for k, (sc, x, y) in enumerate(header["pieces"])]

    # The creature records come from the RAW foe buffer too (foe_record.py), not from the converted values in sectors.json.
    foes = []
    records = foe_record.decode_records(sec)
    # The creatures name their entry points by label; the text has one label per offset (foe_text.py).
    labels = foe_text.entry_labels(foe_script.offsets_of(sec), (annotations or {}).get("labels"))
    for r, (start_label, hit_label, ink_label) in zip(records, labels):
        props = [
            ("dormant", tres.b(r["dormant"])), ("hidden", tres.b(r["hidden"])),
            ("screen", str(r["screen"])), ("pos", tres.vec2i(*r["pos"])), ("frame", str(r["frame"])),
            ("flip", tres.b(r["flip"])), ("frame_min", str(r["frame_min"])), ("frame_max", str(r["frame_max"])),
            ("damage", str(r["damage"])), ("start_label", tres.s(start_label)),
            ("hit_label", tres.s(hit_label)), ("ink_label", tres.s(ink_label))]
        if any(r["runtime_state"]):                # all zero in the 640 original records: stored only when not
            props.append(("runtime_state", tres.packed_bytes(r["runtime_state"])))
        foes.append(t.sub("Resource", props, script=SCRIPTS + "foe_data.gd", prefix="Foe"))

    # Foe buffer = count byte + n * 34-byte records + bytecode. Keep only the bytecode, as readable text.
    base, script = foe_script.script_of(sec)
    source = foe_text.disassemble(script, base, foe_text.entry_names(foe_script.offsets_of(sec)), annotations,
                                foe_names.Names.for_original_sector(sec["index"]))

    i = sec["index"]
    t.set("index", str(i))
    t.set("game", str(sector_game(i)))
    t.set("zone", str(sector_zone(i)))
    if finale_screen(i) >= 0:
        t.set("finale_screen", str(finale_screen(i)))
    t.set("start_pos", tres.vec2i(*header["start_pos"]))
    t.set("start_frame", str(header["start_frame"]))
    for side in sector_header.SIDES:
        t.set("neighbors_" + side, tres.packed_ints(header["neighbors"][side]))
    t.set("pieces", tres.array('ExtResource("%s")' % ids["piece_data"], pieces))
    if header["stale_pieces"]:                     # only sectors 6 and 22
        t.set("stale_pieces", tres.packed_ints(v for entry in header["stale_pieces"] for v in entry))
    t.set("screens", tres.array('ExtResource("%s")' % ids["screen_data"], screen_refs))
    t.set("foes", tres.array('ExtResource("%s")' % ids["foe_data"], foes))
    t.set("foe_script", t.ext_ref("Resource", res_path(sector_file(i, "foe"))))
    t.set("foe_script_base", str(base))
    t.set("music_name", tres.s(music_name(i)))
    t.set("header_unused_3d", str(header["header_unused_3d"]))
    t.set("header_unused_40", str(header["header_unused_40"]))
    t.set("header_unused_41", str(header["header_unused_41"]))
    return t.render(), source


def build_zones() -> str:
    t = tres.Tres("Resource", "ZoneTable", SCRIPTS + "zone_table.gd")
    zid = t.ext_id("Script", SCRIPTS + "zone_data.gd")
    zones = []
    edu = ds_tables.default_edu_levels()
    for z in range(7):
        art = min(z, 4)
        props = [("index", str(z)),
                 ("title", tres.s(ZONE_TITLES[z] if z < 5 else ("Voyager Finale" if z == 5 else "Expert Finale"))),
                 ("tile_zone", str(art)), ("tile_source_id", str(art)),
                 ("deco_count", str(ZONE_DECO_COUNTS[art])), ("foe_count", str(ZONE_FOE_COUNTS[z]))]
        if z < 5:
            banner = res_path(ui_file("hud", ZONE_BANNER_IDS[z]))
            props.append(("banner_texture", t.ext_ref("Texture2D", banner)))
        # The original keeps 10 levels, indexed game * 5 + zone (ds_tables.py). A finale has no row of its own: the game
        # uses the last zone's level (Progression.default_edu_level), so its entries are zone 4's.
        props.append(("default_edu_level_voyager", str(edu[art])))
        props.append(("default_edu_level_expert", str(edu[5 + art])))
        zones.append(t.sub("Resource", props, script=SCRIPTS + "zone_data.gd", prefix="Zone"))
    t.set("zones", tres.array('ExtResource("%s")' % zid, zones))
    return t.render()


def build_trigger_table() -> str:
    flat = ds_tables.trigger_table()          # the same 504 bytes the fixture hashes
    t = tres.Tres("Resource", "TriggerTable", SCRIPTS + "trigger_table.gd")
    t.set("table", tres.packed_bytes(flat))
    return t.render()


def owned_files() -> list[Path]:
    """The sector files this step generates: sector_NN.tres and .foe of the ORIGINAL sectors 0..ORIGINAL_SECTOR_COUNT-1, and
    their screen files sector_NN/screen_MM.tres. Nothing else in godot/data/sectors/ is the importer's (new sectors,
    foe_annotations.json, .uid files)."""
    files = [sector_file(i, ext) for i in range(ORIGINAL_SECTOR_COUNT) for ext in ("tres", "foe")]
    return files + [screen_record.screen_path(i, k) for i in range(ORIGINAL_SECTOR_COUNT) for k in range(SCREENS)]


def run() -> None:
    sectors = load_json(TABLES / "sectors.json")
    assert len(sectors) == ORIGINAL_SECTOR_COUNT
    store = foe_annotations.load()
    for sec in sectors:
        resource, source = build_sector(sec, foe_annotations.for_sector(store, sec["index"]))
        out_text(sector_file(sec["index"], "tres"), resource)
        out_text(sector_file(sec["index"], "foe"), source)
        for k, text in enumerate(build_screen_files(sec)):
            out_text(screen_record.screen_path(sec["index"], k), text)
    out_text(foe_script.HASH_FIXTURE, foe_script.build_hash_fixture(sectors))
    out_text(foe_script.RAW_FIXTURE, foe_script.build_raw_fixture(sectors))
    out_text(screen_record.HASH_FIXTURE, screen_record.build_hash_fixture(sectors))
    out_text(screen_record.RAW_FIXTURE, screen_record.build_raw_fixture(sectors))
    out_text(sector_header.HASH_FIXTURE, sector_header.build_hash_fixture(sectors))
    out_text(sector_header.RAW_FIXTURE, sector_header.build_raw_fixture(sectors))
    out_text(foe_record.HASH_FIXTURE, foe_record.build_hash_fixture(sectors))
    out_text(foe_record.RAW_FIXTURE, foe_record.build_raw_fixture(sectors))
    out_text(ds_tables.TRIGGER_HASH_FIXTURE, ds_tables.build_trigger_hash_fixture())
    out_text(ds_tables.TRIGGER_RAW_FIXTURE, ds_tables.build_trigger_raw_fixture())
    out_text(ds_tables.ZONES_HASH_FIXTURE, ds_tables.build_zones_hash_fixture())
    out_text(ds_tables.ZONES_RAW_FIXTURE, ds_tables.build_zones_raw_fixture())
    out_text(PACK_DATA / "zones.tres", build_zones())
    out_text(PACK_DATA / "trigger_table.tres", build_trigger_table())
    print("  sectors: 32 sector files + 32 creature scripts (.foe) + 384 screen files, zones, trigger table")
