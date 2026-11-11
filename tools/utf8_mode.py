"""Python's UTF-8 mode for the tools on Windows: `ensure()` runs the calling script again with PYTHONUTF8=1 when it is not in it.

Teaches: fixing a platform default in one place instead of at every call site. Python reads and writes text files, and its
standard streams when they are pipes, in the locale's encoding, which is UTF-8 on Linux and a code page such as cp1252 on
Windows. The tools read and write UTF-8 everywhere (the game's texts, the name registry, the tables, the .tres files) and print
characters outside any code page, so on Windows they need UTF-8 mode (PEP 540). An entry point calls `ensure()` before it does
anything else; on Linux and macOS, and when the mode is already on, it returns at once. The scripts the importer starts inherit
the environment, so they run in UTF-8 mode too. Line endings are a separate matter: a text file the tools write for the
legacy pack or for git is written with `newline="\\n"` (or as bytes), so Windows writes the same bytes as Linux.
"""
from __future__ import annotations

import os
import subprocess
import sys


def ensure() -> None:
    """On Windows outside UTF-8 mode: run this same command again in UTF-8 mode and exit with its exit code."""
    if os.name != "nt" or sys.flags.utf8_mode:
        return
    env = dict(os.environ, PYTHONUTF8="1")
    sys.exit(subprocess.run([sys.executable, *sys.orig_argv[1:]], env=env, check=False).returncode)
