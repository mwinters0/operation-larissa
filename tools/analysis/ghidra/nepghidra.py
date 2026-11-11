"""Shared helpers for the Operation Neptune Ghidra scripts (PyGhidra).

Environment:
  GHIDRA_INSTALL_DIR   Ghidra install dir (default ~/.local/bin/ghidra/ghidra_12.2_PUBLIC)
  NEP_GHIDRA_PROJECT   directory holding the Ghidra project (default ./ghidra-project)
  NEP_GHIDRA_PROJECT16 directory holding the Win16 project (default ./ghidra-project16; ONWIN.EXE and ONWIN.MAP come from the CD image)
  NEP_ONWIN32          path to ONWIN32.EXE (default: ONWINCD/ONWIN32.EXE from the CD image NEPTUNE.ISO, copied
                       to build/gamefiles/ by tools/gamefiles.py materialize(); NEP_ISO names another image)
"""
import os, sys, json, contextlib
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
os.environ.setdefault("GHIDRA_INSTALL_DIR", str(Path.home() / ".local/bin/ghidra/ghidra_12.2_PUBLIC"))
PROJECT_DIR = Path(os.environ.get("NEP_GHIDRA_PROJECT", Path.cwd() / "ghidra-project"))


def exe_path():
    """ONWIN32.EXE as a real file for Ghidra to import: $NEP_ONWIN32, else the copy made from the CD image."""
    if os.environ.get("NEP_ONWIN32"):
        return Path(os.environ["NEP_ONWIN32"])
    sys.path.insert(0, str(REPO / "tools"))      # imported here, not at the top: needs pycdlib, and the Ghidra GUI has none
    import gamefiles
    return gamefiles.materialize("ONWINCD/ONWIN32.EXE")


NAMES_JSON = Path(__file__).resolve().with_name("names_onwin32.json")   # resolve(): works through a symlinked script dir

LABELS_JSON = NAMES_JSON.with_name("labels_onwin32.json")

# Headless (./run.sh): the JVM is not running yet, so start it. Inside the Ghidra GUI (launched with
# support/pyghidraRun) the JVM is already up and Ghidra owns the project: do not start anything.
try:
    import jpype
    _JVM_UP = jpype.isJVMStarted()
except ImportError:
    _JVM_UP = False
if not _JVM_UP:
    import pyghidra
    pyghidra.start()
# pyghidra.start() drops this directory from sys.path; the scripts import their sibling modules after it
if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.append(str(Path(__file__).resolve().parent))


def in_script_manager(g):
    """True when the calling script runs inside Ghidra (GUI Script Manager / pyghidra.ghidra_script).

    Pass the caller's globals(): a PyGhidra script's globals hold Ghidra's `currentProgram` etc."""
    return "__this__" in g


def run(g, fn, win16=False):
    """Call fn(program). In Ghidra the program is `currentProgram`; headless it is ONWIN32.EXE from the project (win16: ONWIN.EXE from
    its project, ghidra-project16)."""
    if in_script_manager(g):
        prog = g["currentProgram"]
        if prog is None:
            raise RuntimeError("no program open: open %s in the CodeBrowser first" % ("ONWIN.EXE" if win16 else "ONWIN32.EXE"))
        return fn(prog)
    with (open_program16() if win16 else open_program()) as api:
        return fn(api.getCurrentProgram())


def check_program(prog):
    if "ONWIN32" not in prog.getName().upper():
        raise RuntimeError("these scripts are for ONWIN32.EXE, but the open program is %r" % prog.getName())


def check_program16(prog):
    if prog.getName().upper() != "ONWIN.EXE" or str(prog.getLanguageID()) != "x86:LE:16:Protected Mode":
        raise RuntimeError("these scripts are for ONWIN.EXE (the Win16 project), but the open program is %r" % prog.getName())


@contextlib.contextmanager
def open_program(analyze=True):
    """Open (importing + analysing on first use) ONWIN32.EXE; yields a FlatProgramAPI."""
    import pyghidra
    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    with pyghidra.open_program(str(exe_path()), project_location=str(PROJECT_DIR),
                               project_name="neptune", analyze=analyze) as api:
        yield api


PROJECT16_DIR = Path(os.environ.get("NEP_GHIDRA_PROJECT16", Path.cwd() / "ghidra-project16"))
PROJECT16_NAME = "neptune16"


def win16_paths():
    """(ONWIN.EXE, ONWIN.MAP) as real files for Ghidra and the importer: copies made from the CD image (NEP_ISO names another)."""
    sys.path.insert(0, str(REPO / "tools"))
    import gamefiles
    return gamefiles.materialize("ONWINCD/ONWIN.EXE"), gamefiles.materialize("ONWINCD/ONWIN.MAP")


@contextlib.contextmanager
def open_program16(analyze=False):
    """Open the Win16 build (ONWIN.EXE, 16-bit NE) in its own project, ghidra-project16 (import_win16.py makes it); yields a FlatProgramAPI.

    Not the Win32 project: a Ghidra project is locked while open, and the two builds are two programs."""
    import pyghidra
    PROJECT16_DIR.mkdir(parents=True, exist_ok=True)
    with pyghidra.open_program(str(win16_paths()[0]), project_location=str(PROJECT16_DIR),
                               project_name=PROJECT16_NAME, analyze=analyze) as api:
        yield api


class Decompiler:
    def __init__(self, api, timeout=60):
        from ghidra.app.decompiler import DecompInterface
        from ghidra.util.task import ConsoleTaskMonitor
        self.api = api
        self.mon = ConsoleTaskMonitor()
        self.timeout = timeout
        self.di = DecompInterface()
        self.di.openProgram(api.getCurrentProgram())

    def c(self, func):
        r = self.di.decompileFunction(func, self.timeout, self.mon)
        if r.decompileCompleted():
            return r.getDecompiledFunction().getC()
        return "// decompile failed: %s\n" % r.getErrorMessage()


def functions(api):
    fm = api.getCurrentProgram().getFunctionManager()
    return [f for f in fm.getFunctions(True) if not f.isThunk()]


def addr(api, a):
    return api.toAddr(a if isinstance(a, int) else int(a, 16))


def load_names():
    """names_onwin32.json with every name: the ONWIN.MAP references resolved (map_names.py)."""
    import map_names
    return map_names.resolve(json.loads(NAMES_JSON.read_text()), map_names.symbols()) if NAMES_JSON.exists() else {}


def load_labels():
    """labels_onwin32.json with every name, as load_names()."""
    import map_names
    return map_names.resolve(json.loads(LABELS_JSON.read_text()), map_names.symbols()) if LABELS_JSON.exists() else {}


def set_label(prog, address, name, evidence=None, primary=True):
    """Give `address` the global label `name` (and the plate comment `evidence`, if any).

    Safe to repeat: returns "kept" when that label is already there, else "created". Several scripts may
    label one address (g_prob00 and LockRecord share 0x00448cd4), so other labels are never removed or renamed;
    `primary` says whether the label becomes the one Ghidra shows (and the decompiler prints).
    SymbolTable.createLabel itself returns an identical existing label rather than a duplicate; the explicit
    check keeps that independent of the Ghidra version."""
    from ghidra.program.model.symbol import SourceType, SymbolType
    st = prog.getSymbolTable()
    same = [s for s in st.getSymbols(address)
            if s.getSymbolType() == SymbolType.LABEL and s.getParentNamespace().isGlobal() and s.getName() == name]
    if same:
        sym, how = same[0], "kept"
        if sym.getSource() != SourceType.USER_DEFINED:
            sym.setSource(SourceType.USER_DEFINED)
    else:
        sym, how = st.createLabel(address, name, SourceType.USER_DEFINED), "created"
    if primary and not sym.isPrimary():
        sym.setPrimary()
    if evidence:
        prog.getListing().setComment(address, 3, evidence)   # CodeUnit.PLATE_COMMENT
    return how
