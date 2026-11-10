"""A shortcut to the voice transcription, which is the importer's "transcripts" step (deterministic,
pinned engine and model, compared with a committed hash fixture). This runs the same thing:

    uv run tools/extract/transcribe_voice.py [--compute-type float32] [--write-fixture]

Output: extracted/sounds/voice_transcripts.json. See tools/import/transcripts.py."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "import"))

import transcripts

if __name__ == "__main__":
    sys.exit(transcripts.main())
