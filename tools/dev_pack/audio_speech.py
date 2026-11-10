"""Piper text-to-speech for the dev pack: one pinned English voice, downloaded once into a cache outside the repository.

The voice model is not committed (63 MB). `ensure_voice` downloads it from the URLs below into `~/.cache/neptune-dev-pack/`
(or $NEPTUNE_DEV_PACK_CACHE) and refuses a file whose SHA-256 differs from the pin. With the noise settings at 0 Piper says
the same words with the same samples every time on a machine, so regenerating the pack does not change its files.
"""
from __future__ import annotations

import hashlib
import os
import urllib.request
from importlib import metadata
from pathlib import Path

import numpy as np

VOICE_ID = "en_US-lessac-medium"
_BASE = "https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/"
VOICE_FILES = {
    VOICE_ID + ".onnx": (_BASE + VOICE_ID + ".onnx", "5efe09e69902187827af646e1a6e9d269dee769f9877d17b16b1b46eeaaf019f"),
    VOICE_ID + ".onnx.json": (_BASE + VOICE_ID + ".onnx.json", "efe19c417bed055f2d69908248c6ba650fa135bc868b0e6abb3da181dab690a0"),
}
SPEECH_RATE = 22050             # the voice's own rate


def cache_dir() -> Path:
    return Path(os.environ.get("NEPTUNE_DEV_PACK_CACHE") or Path.home() / ".cache" / "neptune-dev-pack")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while chunk := f.read(1 << 22):
            h.update(chunk)
    return h.hexdigest()


def ensure_voice(folder: Path | None = None) -> Path:
    """The path of the voice's .onnx file, downloaded and checked against the pinned SHA-256 first if need be."""
    folder = folder or cache_dir()
    folder.mkdir(parents=True, exist_ok=True)
    for name, (url, digest) in VOICE_FILES.items():
        path = folder / name
        if not path.exists():
            print("  downloading %s" % url)
            part = path.with_name(name + ".part")
            urllib.request.urlretrieve(url, part)
            part.rename(path)
        if sha256_file(path) != digest:
            raise RuntimeError("%s does not match its pinned SHA-256 (%s): delete it to download again" % (path, digest))
    return folder / (VOICE_ID + ".onnx")


def piper_version() -> str:
    return metadata.version("piper-tts")


class Speaker:
    """Says text. `say` returns float samples (-1..1) at SPEECH_RATE with the silence at both ends trimmed."""

    def __init__(self, folder: Path | None = None):
        from piper import PiperVoice, SynthesisConfig         # imported here: the parts of the generator without speech need no Piper
        self.voice = PiperVoice.load(ensure_voice(folder))
        self.config = SynthesisConfig(noise_scale=0.0, noise_w_scale=0.0)
        assert self.voice.config.sample_rate == SPEECH_RATE
        self._cache: dict[str, np.ndarray] = {}

    def say(self, text: str) -> np.ndarray:
        if text not in self._cache:
            raw = b"".join(chunk.audio_int16_bytes for chunk in self.voice.synthesize(text, self.config))
            self._cache[text] = trim(np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0)
        return self._cache[text]


def trim(samples: np.ndarray, threshold: float = 0.01, pad_seconds: float = 0.03) -> np.ndarray:
    """Cuts the quiet start and end, keeping `pad_seconds` of it."""
    loud = np.nonzero(np.abs(samples) > threshold)[0]
    if loud.size == 0:
        return samples
    pad = int(pad_seconds * SPEECH_RATE)
    return samples[max(0, loud[0] - pad):loud[-1] + 1 + pad]
