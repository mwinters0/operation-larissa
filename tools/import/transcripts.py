"""Deterministic voice transcripts: the 423 clips (NE1SOUND speech, NE0SOUND effects) -> text, the same on every machine.

    uv run tools/import/transcripts.py                       # what the importer's "transcripts" step does
    uv run tools/import/transcripts.py --write-fixture       # only to move the reference (see below)
    uv run tools/import/transcripts.py --compute-type float32
    uv run tools/import/transcripts.py --correct NE1SOUND_4000 "the right words"

The text is the game's speech, so it is NEVER committed. What is committed is
`godot/tests/fixtures/voice_transcripts.json`: provenance and ONE SHA-256 per clip transcript, no text. The step transcribes
every clip, hashes the machine text, and reports each clip whose hash differs from the fixture ("Fixtures commit hashes, not
bytes", docs/port/FIDELITY.md). To make the text the same everywhere, everything that can change it is pinned:

  * faster-whisper and CTranslate2 versions: `uv.lock` (checked at run time against FASTER_WHISPER / CTRANSLATE2 below;
    a test keeps the two in step),
  * the model: Systran/faster-whisper-small.en at the git revision MODEL_REVISION, every file verified by SHA-256
    (MODEL_FILES, the weights included) before it is loaded; nothing newer is ever fetched,
  * decoding: greedy (beam_size=1, best_of=1), temperature 0 only (no fallback to a hotter pass, which would be random),
  * CPU, `cpu_threads` = CPU_THREADS, one worker, one compute type.

Compute type. `int8` is the default: it is what the old step used and it is fast. Its risk: the int8 matrix kernels of
CTranslate2 are chosen at run time by instruction set (AVX2, AVX-512, VNNI ...) and may round differently, which would change
a few transcripts between two machines. `float32` has no such kernels but a different (slower, bigger) path. Switch with
`--compute-type float32` or $NEP_WHISPER_COMPUTE=float32, then write the fixture again with the same setting: the
fixture records which one it is for, and the step says so when you run the other. The two give different text for about
8% of the clips. Tried so far, on one machine (AMD Zen 5, AVX-512): int8 with CTranslate2 forced to AVX-512 and to AVX2
(CT2_FORCE_CPU_ISA) gave the same text for all 423 clips; float32 is not needed. OPEN ITEM: run it on a second machine
(another CPU vendor, no AVX-512/VNNI) before relying on int8; if clips differ there, move to float32 and rewrite the fixture.

Hand corrections (the machine is sometimes wrong) are the game's speech too, so they are not committed either. They live in
the user's own area, common.VOICE_CORRECTIONS (inside common.LEGACY_AREA, $NEP_LEGACY), as
    {"NE1SOUND_4000": {"machine_sha256": "<hash of the machine text this corrects>", "text": "the right words"}}
A correction is used only while the machine transcript still hashes to `machine_sha256`; when it does not (another model, a
changed setting) the correction is STALE: it is not used, and the step says so. `--correct` writes the entry for you.

Output, where the importer's audio step and the tests read it today: `extracted/sounds/voice_transcripts.json` (clip ->
text, corrections applied) and, beside it, `voice_transcripts_machine.json` (the same without corrections).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import wave
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common

# --- the pins ---------------------------------------------------------------------------------------------------------
FASTER_WHISPER = "1.2.1"          # must equal the locked version in uv.lock (test_transcripts.py checks)
CTRANSLATE2 = "4.8.4"
MODEL_REPO = "Systran/faster-whisper-small.en"
MODEL_REVISION = "d1d751a5f8271d482d14ca55d9e2deeebbae577f"
MODEL_FILES = {                     # SHA-256 of every file of that revision
    "config.json": "666a9605530ac1f61fa8177f3702b4dacec9966749e42610839fcc32661d5fae",
    "model.bin": "62b2a45b05ee59acb4a5341b33ee35e041395d378d418a18acfe4c9e768ee37a",           # the weights
    "tokenizer.json": "929c5252409436dce1b38a75d1abbcb5e132d170d8e324e4e04ed915fa2d22df",
    "vocabulary.txt": "ff77588746d3a2595d32ab5b69ffd7b95ce2441ac57533cb66fc3eb575a115cf",
}
CPU_THREADS = 4
DEFAULT_COMPUTE_TYPE = "int8"
COMPUTE_TYPES = ("int8", "float32")
# Everything passed to WhisperModel.transcribe (the rest is faster-whisper's default for the pinned version, listed
# in the fixture so a change shows up in review).
DECODING: dict[str, Any] = dict(language="en", beam_size=1, best_of=1, temperature=0.0, patience=1.0, length_penalty=1.0,
                                repetition_penalty=1.0, no_repeat_ngram_size=0, condition_on_previous_text=False,
                                vad_filter=False, word_timestamps=False)

# --- files ------------------------------------------------------------------------------------------------------------
FIXTURE = common.GODOT / "tests" / "fixtures" / "voice_transcripts.json"
SOUNDS = common.EXTRACTED / "sounds"
OUT = SOUNDS / "voice_transcripts.json"
OUT_MACHINE = SOUNDS / "voice_transcripts_machine.json"
SOURCE = "NE1SOUND.DLL resources 4000-4370 (speech) and NE0SOUND.DLL 8000-8051 (effects), as WAVs from tools/extract/extract_sounds.py"
COMMENT = (
    "Provenance and ONE SHA-256 per clip transcript (of the machine text, UTF-8, before any hand correction), written by "
    "tools/import/transcripts.py (`--write-fixture`), never hand-edited. It holds no text: the transcripts are the game's "
    "speech, made on your machine from your copy by the pinned engine in \"engine\" and compared with these hashes by the "
    "importer's \"transcripts\" step, which reports each clip that differs. Hand corrections are not here (they are the speech "
    "too): they live in the legacy pack's hand-data area (common.VOICE_CORRECTIONS), keyed by clip and by the hash of the machine text "
    "they correct. See docs/play/LEGACY.md.")


class EngineMismatch(RuntimeError):
    """The engine is not installed, or a downloaded model file is not the pinned one."""


def text_hash(text: str) -> str:
    """The hash of one machine transcript: SHA-256 of the text as UTF-8, exactly as the engine returned it."""
    return common.sha256_hex(text.encode("utf-8"))


def clip_names() -> list[str]:
    """The 423 clip names in transcription order: the speech first, then the effects."""
    return ["NE1SOUND_%d" % i for i in range(4000, 4371)] + ["NE0SOUND_%d" % i for i in range(8000, 8052)]


def clip_file(name: str, sounds: Path = SOUNDS) -> Path:
    return sounds / name.split("_")[0] / (name + ".wav")


# --- pure logic: the fixture, the corrections (tested without a model) ------------------------------------------------

def engine_description(compute_type: str, cpu_threads: int = CPU_THREADS) -> dict:
    return {"faster_whisper": FASTER_WHISPER, "ctranslate2": CTRANSLATE2, "model": MODEL_REPO, "model_revision": MODEL_REVISION,
            "model_files_sha256": MODEL_FILES, "device": "cpu", "compute_type": compute_type, "cpu_threads": cpu_threads,
            "num_workers": 1, "decoding": DECODING}


def fixture_document(machine: dict[str, str], compute_type: str) -> dict:
    return {"comment": COMMENT, "source": SOURCE, "engine": engine_description(compute_type),
            "clips": {name: text_hash(machine[name]) for name in sorted(machine)}}


class Comparison:
    """machine transcripts vs. the fixture: `changed` (hash differs), `new` (not in the fixture), `gone` (only in it)."""

    def __init__(self, changed: list[str], new: list[str], gone: list[str], engine_differs: list[str]):
        self.changed, self.new, self.gone, self.engine_differs = changed, new, gone, engine_differs

    @property
    def ok(self) -> bool:
        return not (self.changed or self.new or self.gone)


def compare_fixture(machine: dict[str, str], fixture: dict, compute_type: str) -> Comparison:
    hashes = fixture["clips"]
    changed = [n for n in sorted(machine) if n in hashes and text_hash(machine[n]) != hashes[n]]
    new = [n for n in sorted(machine) if n not in hashes]
    gone = [n for n in sorted(hashes) if n not in machine]
    ours, theirs = engine_description(compute_type), fixture.get("engine", {})
    differs = [k for k in ours if ours[k] != theirs.get(k)]
    return Comparison(changed, new, gone, differs)


class Corrections:
    """Hand corrections sorted by what the current machine transcripts say: `used`, `stale`, `unknown` (no such clip)."""

    def __init__(self, used: dict[str, str], stale: list[str], unknown: list[str]):
        self.used, self.stale, self.unknown = used, stale, unknown


def load_corrections(path: Path = common.VOICE_CORRECTIONS) -> dict[str, dict]:
    if not path.is_file():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("corrections", data) if isinstance(data, dict) else {}


def sort_corrections(machine: dict[str, str], corrections: dict[str, dict]) -> Corrections:
    used, stale, unknown = {}, [], []
    for name in sorted(corrections):
        entry = corrections[name]
        if name not in machine:
            unknown.append(name)
        elif entry.get("machine_sha256") != text_hash(machine[name]):
            stale.append(name)
        else:
            used[name] = entry["text"]
    return Corrections(used, stale, unknown)


def final_transcripts(machine: dict[str, str], corrections: Corrections) -> dict[str, str]:
    return {name: corrections.used.get(name, machine[name]) for name in machine}


def add_correction(path: Path, machine: dict[str, str], name: str, text: str) -> None:
    """Record `text` as the correction of clip `name`, keyed to the hash of its CURRENT machine transcript."""
    if name not in machine:
        raise KeyError("no clip %s (clips are named NE1SOUND_4000 ... NE0SOUND_8051)" % name)
    entries = load_corrections(path)
    entries[name] = {"machine_sha256": text_hash(machine[name]), "text": text}
    path.parent.mkdir(parents=True, exist_ok=True)
    document = {"comment": "Hand corrections of the machine voice transcripts (tools/import/transcripts.py). Not committed: "
                           "the text is the game's speech.", "corrections": dict(sorted(entries.items()))}
    path.write_text(json.dumps(document, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


# --- the engine -------------------------------------------------------------------------------------------------------

def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 22):
            h.update(chunk)
    return h.hexdigest()


def check_engine() -> None:
    """Refuse unless faster-whisper and CTranslate2 are installed."""
    try:
        import ctranslate2  # noqa: F401
        import faster_whisper  # noqa: F401
    except ImportError as error:
        raise EngineMismatch("faster-whisper is not installed (%s): run `uv sync --group transcribe`, or leave this step out "
                             "with --only" % error) from None


def engine_version_warning() -> str | None:
    """What differs when the installed faster-whisper / CTranslate2 are not the locked versions (a warning: the step goes on, and its
    text may then differ from the fixture); None when they are the pins or are not installed (check_engine refuses that)."""
    try:
        import ctranslate2
        import faster_whisper
    except ImportError:
        return None
    have = (faster_whisper.__version__, ctranslate2.__version__)
    if have == (FASTER_WHISPER, CTRANSLATE2):
        return None
    return ("faster-whisper %s / ctranslate2 %s are installed, the pins are %s / %s: transcripts may differ from the fixture; for the "
            "pins run `uv sync --group transcribe` (uv.lock holds them)" % (have + (FASTER_WHISPER, CTRANSLATE2)))


def fetch_model() -> Path:
    """The pinned model revision, downloaded once into the Hugging Face cache, every file verified by SHA-256."""
    from huggingface_hub import snapshot_download
    folder = Path(snapshot_download(MODEL_REPO, revision=MODEL_REVISION, allow_patterns=list(MODEL_FILES)))
    for name, want in MODEL_FILES.items():
        have = sha256_file(folder / name)
        if have != want:
            raise EngineMismatch("%s/%s of revision %s has SHA-256 %s, expected %s: delete the Hugging Face cache entry and "
                                 "run again" % (MODEL_REPO, name, MODEL_REVISION[:8], have, want))
    return folder


def load_samples(path: Path):
    """16 kHz float samples of a clip: resampled from the rate the original plays it at, 0.25 s of silence either side."""
    import numpy as np
    with wave.open(str(path)) as w:
        rate = w.getframerate()                      # the rate the original plays the clip at (see extract_sounds.py)
        x = (np.frombuffer(w.readframes(w.getnframes()), dtype=np.uint8).astype(np.float32) - 128) / 128
    n16 = int(len(x) * 16000 / rate)
    x = np.interp(np.linspace(0, len(x) - 1, n16), np.arange(len(x)), x).astype(np.float32)
    return np.concatenate([np.zeros(4000, np.float32), x, np.zeros(4000, np.float32)])


def transcribe(compute_type: str, names: list[str], sounds: Path = SOUNDS, progress=None) -> dict[str, str]:
    check_engine()
    differs = engine_version_warning()
    if differs:
        print("  WARNING: %s" % differs, file=sys.stderr)
    from faster_whisper import WhisperModel      # pyright: ignore[reportMissingImports]
    model = WhisperModel(str(fetch_model()), device="cpu", compute_type=compute_type, cpu_threads=CPU_THREADS, num_workers=1)
    out = {}
    for name in names:
        segments, _ = model.transcribe(load_samples(clip_file(name, sounds)), **DECODING)
        out[name] = " ".join(s.text.strip() for s in segments).strip()
        if progress:
            progress(name, out[name])
    return out


# --- the step ---------------------------------------------------------------------------------------------------------

def counter(total: int, every: int = 25):
    """A `progress` callback for `transcribe` that prints how many clips are done every `every` clips and at the end, so the
    several minutes of transcription show they are moving."""
    done = [0]

    def tick(name: str, text: str) -> None:
        done[0] += 1
        if done[0] % every == 0 or done[0] == total:
            print("  transcribed %d of %d clips" % (done[0], total), flush=True)
    return tick


def write_json(path: Path, data: dict) -> None:
    common.Stats.record(common.write_text(path, json.dumps(data, indent=1, ensure_ascii=False) + "\n"))


def run(compute_type: str | None = None, write_fixture: bool = False) -> int:
    """The importer's "transcripts" step. Returns 0, also when clips differ from the fixture (it only reports them)."""
    compute_type = compute_type or os.environ.get("NEP_WHISPER_COMPUTE") or DEFAULT_COMPUTE_TYPE
    if compute_type not in COMPUTE_TYPES:
        raise SystemExit("compute type must be one of %s, not %r" % (", ".join(COMPUTE_TYPES), compute_type))
    names = clip_names()
    missing = [n for n in names if not clip_file(n).is_file()]
    if missing:
        raise SystemExit("%d clips are missing in %s (first: %s): run tools/extract/extract_sounds.py first"
                         % (len(missing), SOUNDS, missing[0]))
    print("  transcribing %d clips: faster-whisper %s, ctranslate2 %s, %s@%s, greedy, %s, %d threads"
          % (len(names), FASTER_WHISPER, CTRANSLATE2, MODEL_REPO, MODEL_REVISION[:8], compute_type, CPU_THREADS))
    machine = transcribe(compute_type, names, progress=counter(len(names)))
    write_json(OUT_MACHINE, machine)

    if write_fixture:
        common.write_text(FIXTURE, json.dumps(fixture_document(machine, compute_type), indent=1) + "\n")
        print("  fixture written: %s (%d hashes)" % (FIXTURE.relative_to(common.ROOT), len(machine)))
    elif FIXTURE.is_file():
        report_comparison(compare_fixture(machine, json.loads(FIXTURE.read_text()), compute_type), len(machine))
    else:
        print("  no fixture (%s): nothing to compare with" % FIXTURE.relative_to(common.ROOT))

    corrections = sort_corrections(machine, load_corrections())
    for name in corrections.stale:
        print("  STALE correction %s: the machine transcript it corrects has changed, the correction is NOT used "
              "(set it again with --correct, or delete it from %s)" % (name, common.VOICE_CORRECTIONS))
    for name in corrections.unknown:
        print("  correction for unknown clip %s ignored" % name)
    print("  hand corrections: %d used, %d stale, %d unknown" % (len(corrections.used), len(corrections.stale),
                                                                   len(corrections.unknown)))
    write_json(OUT, final_transcripts(machine, corrections))
    return 0


def report_comparison(c: Comparison, total: int) -> None:
    for key in c.engine_differs:
        print("  note: engine setting %r differs from the fixture's, so differing clips below may be expected" % key)
    for name in c.changed:
        print("  DIFFERS from the fixture: %s" % name)
    for name in c.new:
        print("  NOT in the fixture: %s" % name)
    for name in c.gone:
        print("  in the fixture but not transcribed: %s" % name)
    if c.ok:
        print("  all %d transcripts match the fixture" % total)
    else:
        print("  %d of %d transcripts differ from the fixture (%d new, %d missing)"
              % (len(c.changed), total, len(c.new), len(c.gone)))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--compute-type", choices=COMPUTE_TYPES, help="default $NEP_WHISPER_COMPUTE, else " + DEFAULT_COMPUTE_TYPE)
    ap.add_argument("--write-fixture", action="store_true", help="write the fixture from this run (moves the reference)")
    ap.add_argument("--correct", nargs=2, metavar=("CLIP", "TEXT"), help="record a hand correction for CLIP")
    args = ap.parse_args(argv)
    if args.correct:
        if not OUT_MACHINE.is_file():
            raise SystemExit("no machine transcripts yet: run this tool once without --correct")
        add_correction(common.VOICE_CORRECTIONS, json.loads(OUT_MACHINE.read_text(encoding="utf-8")), *args.correct)
        print("correction for %s written to %s" % (args.correct[0], common.VOICE_CORRECTIONS))
        return 0
    try:
        return run(args.compute_type, args.write_fixture)
    except EngineMismatch as error:
        print("REFUSED: %s" % error)
        return 1


if __name__ == "__main__":
    sys.exit(main())
