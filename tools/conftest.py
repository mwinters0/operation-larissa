"""pytest setup for tools/: the tests that need the legacy pack skip without it.

The legacy pack is the original game as the importer writes it from the user's own ISO (docs/play/LEGACY.md); none of it is committed, so a fresh
checkout has the importer's code and its tests but not what they check. A test marked `@pytest.mark.legacy` reads the importer's
outputs (the generated files under godot/, the tables dumped to docs/data/, the fixtures of the original bytes, extracted/) and is
skipped with `common.RUN_THE_IMPORTER` while any of them is missing; with the importer's output present it runs as always.

The two groups of the Python suite, as `tools/run_tests.sh` has them for Godot: `uv run pytest tools -m "not legacy"` is the engine group (it needs no
importer output and no legacy pack, and reads no ISO-derived table: the dev pack's generator and its tests are in it), `uv run pytest tools -m legacy` the
legacy group, and `uv run pytest tools` both (the legacy tests skip without the legacy pack).
"""
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent / "import"))

import common


def pytest_configure(config):
    config.addinivalue_line("markers", "legacy: needs the legacy pack, the original game made by the importer from your ISO (skipped without it)")


def pytest_collection_modifyitems(config, items):
    missing = common.legacy_missing()
    if not missing:
        return
    skip = pytest.mark.skip(reason="%s (missing: %s%s)" % (common.RUN_THE_IMPORTER, missing[0],
                                                           " and %d more" % (len(missing) - 1) if len(missing) > 1 else ""))
    for item in items:
        if "legacy" in item.keywords:
            item.add_marker(skip)
