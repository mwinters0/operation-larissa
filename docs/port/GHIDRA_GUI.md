# Browsing ONWIN32.EXE in the Ghidra GUI

Our decompilation work runs headless (see [`tools/analysis/ghidra/README.md`](../../tools/analysis/ghidra/README.md)). Its results live in three files in the repo:

* `tools/analysis/ghidra/names_onwin32.json`: function address -> `{name}`, or `{map}` for a name of ONWIN.MAP
* `tools/analysis/ghidra/labels_onwin32.json`: global address -> name, or `{name}`, or `{map}`

Any entry may also carry an `evidence` note: one line saying how we know what the function or global is. It is optional:
write it when there is something to say (a caller, a string, a table it indexes), leave it out where the name is self-evident
(a constant such as `float_99_0`).

`map` is the 16-bit address (`SSSS:OOOO`) of the ONWIN.MAP public the address is; the name is read from your ISO, never committed
(`extracted/tables/onwin_map.json`, made by the importer's `tables` step; see [`tools/analysis/ghidra/README.md`](../../tools/analysis/ghidra/README.md)).
* `tools/analysis/ghidra/annotations_onwin32.json`: everything else you add in the GUI: comments, types, signatures,
  variables, labels inside functions, equates, Note bookmarks (section 8)

This guide builds a Ghidra project with all of it applied, then opens it in the GUI so you can click around the code
instead of reading `dump_c.py` output, and add to it.

**The short way:** three mise tasks, each run by hand when you want it, with Ghidra closed (only one process can open
the project):

* `mise run ghidra:import` (section 2, the import): builds or updates the project from the JSON (`apply_problem_types.py`,
  `apply_names.py`, `apply_annotations.py`). It refuses when the project holds GUI work that is not in the JSON yet
  (section 7, "Export before you apply"): run `ghidra:export` first. Run it for a fresh project and after a `git pull`.
* `mise run ghidra:gui` (section 3): opens the project in the PyGhidra GUI as it is (`open_gui.py`), and returns when
  Ghidra closes. It checks and applies nothing, so it always opens.
* `mise run ghidra:export` (section 7): writes the GUI's names and annotations into the JSON.

**Why the project is not committed.** A Ghidra project holds a copy of the program's bytes, so it is made from the game,
and nothing made from the game is committed ([`../../AGENTS.md`](../../AGENTS.md)). It is also a binary database that git
cannot diff or merge and that a newer Ghidra upgrades in place. The repo keeps the work as text keyed by address instead,
and anyone rebuilds the project from their own ISO plus that text.

## 1. Requirements

Ghidra, a JDK and uv ([`../SETUP.md`](../SETUP.md)), and:

* the game's CD image at `NEPTUNE.ISO` (or `NEP_ISO`); `ONWINCD/ONWIN32.EXE` is copied out of it to `build/gamefiles/` for Ghidra
  (`tools/gamefiles.py`; `./run.sh` does it for you, or `uv run tools/gamefiles.py materialize ONWINCD/ONWIN32.EXE` prints the path)

Use that copy of the CD's file, never the patched copy under `prefix/`.

## 2. Build the project (headless)

```zsh
cd tools/analysis/ghidra
./run.sh apply_problem_types.py   # first run: imports + auto-analyses ONWIN32.EXE, adds the Prob00..Prob33 structs
./run.sh apply_names.py           # function names + evidence comments, global labels
./run.sh apply_annotations.py     # comments, types, signatures, variables ... (section 8)
```

The first `run.sh` builds a private `.venv` with PyGhidra (about a minute), and the import + analysis takes about 20 s.
The project lands in `tools/analysis/ghidra/ghidra-project/neptune/neptune.gpr` (PyGhidra nests it one directory
down), which git ignores. If you want it somewhere else, set `NEP_GHIDRA_PROJECT=/some/dir` for both commands; the
project is then `/some/dir/neptune/neptune.gpr`.

The scripts are safe to re-run: what is already there is left alone and nothing is duplicated.
Order matters only for which name Ghidra shows: `apply_problem_types.py` retypes the problem-record globals (and
labels them `g_prob00`..), `apply_names.py` then names everything else. Where both want the same address
(`0x00448cd4` is `g_prob00` and `LockRecord`) the JSON name is the primary label and `g_prob00` stays as a second one.

## 3. Open it in the GUI

`./run.sh open_gui.py` (in `tools/analysis/ghidra`) starts the PyGhidra GUI with the project already open; go on at step 2
below. Or start Ghidra with the **PyGhidra** launcher, not `ghidraRun`. `ghidraRun` browses the project fine, but only
`pyghidraRun` runs the Python scripts of sections 6 and 7:

```zsh
~/.local/bin/ghidra/ghidra_12.2_PUBLIC/support/pyghidraRun
```

(The first launch creates a Python virtual environment for Ghidra under `~/.config/ghidra/`; it needs `python3` on
`PATH` and installs from wheels shipped inside Ghidra, so it needs no network.)

1. In the Project window, choose **File > Open Project...** and select
   `tools/analysis/ghidra/ghidra-project/neptune/neptune.gpr`.
2. Double-click `ONWIN32.EXE` to open it in the CodeBrowser.
3. If Ghidra offers to analyse the program, choose **No**. Analysis already ran during the headless import, and running
   it again can rename or retype things.

## 4. Finding your way around

* **Symbol Tree** (left panel) > *Functions*: our names (`DoMathProblem`, `CheckAnswer`, `DoCombinationLock`,
  `DoAction`, ...). Functions still called `FUN_xxxxxxxx` are not identified yet.
* **Window > Functions** lists every function in a sortable table, and you can filter it by name.
* **G** (Go To) jumps to a name or an address, such as `PlaySoundEffect` or `0x425772`.
* The **Decompile** window (Window > Decompile) follows the cursor. Click any call to follow it.
* A named function with an `evidence` note carries it as a function comment, shown above the function in the Listing.
  Labelled globals with evidence get a plate comment.
* **Data Type Manager** > `ONWIN32.EXE` holds the problem-record structs (`Prob00`..`Prob33`), so fields show up as
  `g_prob03->f2_n`.
* **Search > For Strings** finds `LoadString` text and `.MID` file names.
* Right-click a function > **References > Show References to** lists its callers.

## 5. Reading tips

The tips for reading the decompiled code (timers, sound ids, the x87 instructions the decompiler drops) are in the
[README](../../tools/analysis/ghidra/README.md), "Reading the decompiler output".

## 6. Scripts in the GUI (set up once)

`apply_names.py`, `apply_problem_types.py`, `apply_annotations.py`, `export_names.py` and `export_annotations.py` also
run inside the GUI, on the program that is open in the CodeBrowser. They detect Ghidra's `currentProgram`, so they do
not start PyGhidra or open a project themselves. They need `nepghidra.py`, `annotations.py` and `program_annotations.py`
next to them, and the Script Manager must know the directory. Pick one:

* **Script directory (simplest).** Open **Window > Script Manager**, click the **Manage Script Directories** button
  (the list icon in the toolbar), click **Add** (the green plus), choose `tools/analysis/ghidra` and close the
  dialog. The scripts show up under the category *Neptune*. The directory also holds `.venv/`, `ghidra-project/` and
  the pure-Python tools, which Ghidra will list or scan too; ignore them. Only the five scripts above are meant to be
  run from the GUI.
* **Symlinks (cleaner list).** Ghidra always scans `~/ghidra_scripts`, so link just the needed files there:

  ```zsh
  mkdir -p ~/ghidra_scripts/neptune
  cd tools/analysis/ghidra
  ln -s $PWD/{nepghidra,annotations,program_annotations}.py ~/ghidra_scripts/neptune/
  ln -s $PWD/{apply_names,apply_problem_types,apply_annotations,export_names,export_annotations}.py ~/ghidra_scripts/neptune/
  ```

  (Click the **Refresh** button in the Script Manager afterwards.) The scripts resolve the symlinks, so they still read
  and write the JSON files in the repository.

Run a script by double-clicking it (or select it and press the green play button). Output appears in the Script
Manager console. The apply scripts and `export_annotations.py` change the open program (the export records what it
wrote): use **File > Save** afterwards (Ctrl+S) so the project keeps it. Running them twice is harmless.

## 7. Keeping your work in the repo: the round trip

The JSON files are the source of truth. The Ghidra project is a disposable build product.

1. **Work in the GUI.** Rename (select a function or label, press **L**), comment (**;** opens a dialog with a tab per
   kind), retype (**T**), edit a signature (right-click the function > *Edit Function Signature*), rename or retype
   variables in the Decompiler (**L**, **Ctrl+L**).
2. **Export** from the Script Manager: `export_names.py` for names, then `export_annotations.py` for everything else.
   Each prints what it found, with a diff of the files, then asks whether to write them. Answer *No* to look only. Then
   save the program (Ctrl+S). Or save, close Ghidra and run `mise run ghidra:export`, which runs both without asking.
   Headless equivalent (close the project in the GUI first):

   ```zsh
   cd tools/analysis/ghidra
   ./run.sh export_names.py --dry-run           # print the diff, write nothing
   ./run.sh export_names.py --check             # the same, and exit 1 when there is something to export
   ./run.sh export_names.py                     # write the JSON files
   ./run.sh export_annotations.py [--dry-run | --check]    # the same three for annotations
   ```

3. **Add evidence where it helps.** `export_names.py` appends a new name without an `evidence` note. Where the name is not
   self-evident, add one (in the JSON, or as the function's plate comment before you export). `git diff` shows which
   entries are yours.
4. **Commit** the JSON files.

`export_names.py` details: renamed entries keep their evidence; nothing is ever deleted from the JSON, and the formatting
(indent 1, `"0x%08x"` keys) is unchanged, so `git diff` shows only the real changes. Only user-defined names count:
Ghidra's own `FUN_`, `DAT_`, `LAB_`, `s_` names and the `g_probNN` labels are skipped. Where one address carries several
user-defined labels only the primary is exported.

Other things to know:

* **Export before you apply.** `apply_names.py` renames functions back to the JSON name, and `apply_annotations.py` writes
  the file's comments, types and variables over the project's, so GUI work that was not exported yet is lost.
  `mise run ghidra:import` checks both first and refuses. (`apply_names.py` lists the renames it overwrites; a GUI-renamed
  *label* is not removed: the JSON label is added as the primary one and the old name stays as a second label.)
* **Ghidra only lets one process open a project at a time.** Close the project in the GUI before you run a
  `./run.sh` script against it, or the script fails with a lock error. `export_annotations.py --baseline` is the one
  exception (section 8).
* GUI work is saved only in the project, so it is lost if the project is rebuilt unless it was exported and committed.
* Refer to identified functions by name + address in [`DESIGN.md`](DESIGN.md), e.g. `CheckAnswer (0x4xxxxx)`, not by a bare
  `FUN_` address.
* To start over, delete `tools/analysis/ghidra/ghidra-project/` and repeat step 2.

## 8. Annotations

**Which comment where.** Ghidra has five kinds of comment, and they differ in where they show:

| Kind | Listing (assembly) | Decompiler (C), by default | Use it for |
| --- | --- | --- | --- |
| EOL | after the instruction | hidden | a note on one instruction (`EDI = height`) |
| Pre | above the instruction | shown | what the C reader needs too |
| Plate | in a box above | hidden, except the function's own | a function header; a banner over a block of assembly |
| Post | below the instruction | hidden | "falls through to ...", a note after a call |
| Repeatable | at the address and at every reference to it | shown | a global: the note follows it everywhere it is used |

**Edit > Tool Options > Decompiler > Display** switches each kind on or off in the C. A label inside a function
(**L** on an instruction) names a block in the Listing; the C shows it only where a `goto` needs it.

**What `annotations_onwin32.json` keeps** (`tools/analysis/ghidra/annotations.py` describes the format):
comments of every kind; types you define (structs with bitfields, unions, enums, typedefs, function definitions); the
type you give a global, and Ghidra's data that you clear; function signatures you edit (with custom storage); local
variables you name or retype, stack or register; labels inside functions; equates; **Note** bookmarks. Types are written
as paths (`/int`, `/neptune/Prob00 *`), variables by their storage (`Stack[-0x8]:4`, `EAX:4@0x1f`).

It does not keep: names (`export_names.py`); the plate comment of a named function, or of a global label with
evidence, which *is* that entry's `evidence` (`export_annotations.py` writes your edit of it back into
`names_onwin32.json` / `labels_onwin32.json`); what `apply_problem_types.py` makes; functions you create (give one a name
and `export_names.py` keeps it, `apply_names.py` creates it); comments or types of Ghidra's own that you delete; parameter
comments.

**How the export tells your work from Ghidra's.** A fresh import of ONWIN32.EXE already holds about 11,000 comments, data
and types made by the importer and the analysis. The export compares the project with that *baseline*: a fresh import +
analysis of the same EXE made by the same Ghidra, cached in `ghidra-project/neptune/baseline_onwin32.json` (git-ignored:
it is made from the game). The first headless export makes it (about 30 s); in the GUI the export asks you to run
`./run.sh export_annotations.py --baseline`, which works while the GUI has the project open.

**Deletions and git pulls.** `apply_annotations.py` records in the program (*Options > Neptune*) what it applied. The
export is a three-way merge of that record, the project and the file: what you changed since the apply goes into the
file, a comment you deleted is deleted from it, and what the file gained in the meantime (someone else's work you pulled)
stays. When you and the file changed the same entry, yours is written and the other is printed as a conflict. Apply in
turn removes from the project what it applied before and the file no longer has.

**String ids.** A caption, prompt or message is loaded with `LoadStringResource(id, buffer, size)` and the help dialog with
`RunHelpTopic(first_item, string_id, logical_id)`, passing a number such as 0x2b66. `string_ids_onwin32.json` names every id of the
string table (`STR_...`; names only, the text is the game's and is never committed) and `./run.sh generate_string_ids.py` turns it
into the enum `StringId`, an equate at every instruction that holds such a constant and the typed id parameters in
`annotations_onwin32.json`; `apply_annotations.py` then shows the names in the decompiler and the Listing. A family of consecutive
strings (the four "correct" phrases) is `base + index`: the base constant is named after the family's first string. To rename an id,
edit the names file and run the generator again; to see a call site's name, read the decompiler's `STR_...`, not the number.

**Changing the tools.** `./run.sh check_annotations.py` makes one annotation of every kind in a throw-away project,
exports it, applies it to a second fresh project and exports again, which must find nothing (about 90 s). Run it after
changing `annotations.py` or `program_annotations.py`; `uv run pytest tools` tests the format and the merge.

## 9. The Win16 project

`ONWIN.EXE`, the 16-bit build, has a Ghidra project of its own (`tools/analysis/ghidra/ghidra-project16/`, git-ignored) and the same round
trip for names, with its own two files:

* `tools/analysis/ghidra/names_onwin16.json`: function map address (`SSSS:OOOO`, the NE segment number and the offset) -> `{name}`, or
  `{map}` for a name of ONWIN.MAP at another address
* `tools/analysis/ghidra/labels_onwin16.json`: global map address -> name, or `{name}`, or `{map}`

Only names you gave appear in them. The project derives the rest: a function is named after the ONWIN.MAP public at its address, else after
its Win32 counterpart (the function this build's `{"map": ...}` entries of `names_onwin32.json` point at, or a match of `matches_win32.json`
of tier A, B or pin), and carries a comment "Win32 0x... (how it is matched)" that says which. `win16_names.py` is that rule; apply and export
both use it, so a derived name is never exported as if you had typed it.

* `mise run ghidra16:import`: builds the project (`import_win16.py`: a function at every map public, then auto-analysis), then names it
  (`apply_names16.py`). It refuses while the project holds names that are not in the two files yet.
* `mise run ghidra16:gui`: opens it. Rename with **L** as in section 7; in the Script Manager `export_names16.py` shows the diff and asks.
* `mise run ghidra16:export`: with Ghidra closed, writes the names you gave into the two files.

There is no round trip for comments, types and signatures of this project; the Win32 project has one (section 8).

