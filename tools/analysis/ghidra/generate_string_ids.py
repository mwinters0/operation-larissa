# @category Neptune
"""Write the string-id names into annotations_onwin32.json: the enum StringId, an equate at every call site that passes a
string-table id as a constant, and the id parameters typed with the enum (string_ids.py says what and why).

  headless:  ./run.sh generate_string_ids.py [--dir DIR] [--dry-run] [--list]
  GUI:       Script Manager > generate_string_ids.py

Then apply it: `./run.sh apply_annotations.py`. A call site passes its id as `PUSH imm`, or as `base + index` (an `ADD reg, imm` or
`LEA reg, [reg + imm]` right before the push: the strings of a family, such as the four "correct" phrases, are consecutive), and
that immediate is the constant to name. A site whose id is not a constant of its own (RunHelpTopic passes its parameter on) is
listed. --list prints, for every id, its name and call sites (never the strings).

Teaches: finding the constant argument of a call in the disassembly: arguments are pushed last first, so argument n is the
(n+1)th PUSH before the CALL; a computed one is the last instruction that wrote the pushed register.
"""
import argparse, json, sys
from pathlib import Path

import annotations as an
import nepghidra as ng
import program_annotations as ga
import string_ids as si

WRITERS = {"ADD", "MOV", "LEA"}      # the instructions that make `base + index` (or the constant itself) in the pushed register


def constant_of(push):
    """-> (value, operand index) of the constant that is pushed, or None."""
    scalar = push.getScalar(0)
    if scalar is not None:
        return int(scalar.getUnsignedValue()), 0
    return None


def computed_constant(push):
    """PUSH reg: the immediate of the last instruction before it that writes reg (ADD reg, imm / MOV reg, imm /
    LEA reg, [x + imm]); -> (value, operand index, instruction) or None."""
    reg = str(push.getRegister(0)) if push.getRegister(0) is not None else None
    p = push.getPrevious()
    for _ in range(12):
        if p is None or p.getFlowType().isCall() or p.getFlowType().isTerminal():
            return None
        if p.getNumOperands() and p.getRegister(0) is not None and str(p.getRegister(0)) == reg and p.getMnemonicString() in WRITERS:
            scalar = p.getScalar(1)
            if scalar is None and p.getMnemonicString() == "LEA":
                for o in p.getOpObjects(1):
                    if hasattr(o, "getUnsignedValue"):
                        scalar = o
            return (int(scalar.getUnsignedValue()), 1, p) if scalar is not None else None
        p = p.getPrevious()
    return None


def argument_site(listing, call_from, arg_index):
    """The instruction that holds the constant of argument `arg_index` of the call at call_from, as (value, address, operand),
    or None when there is none (the id is a variable)."""
    p = listing.getInstructionAt(call_from).getPrevious()
    pushes = -1
    for _ in range(40):
        if p is None or p.getFlowType().isCall() or p.getFlowType().isTerminal():
            return None
        if p.getMnemonicString() == "PUSH":
            pushes += 1
            if pushes == arg_index:
                break
        p = p.getPrevious()
    else:
        return None
    if p is None or pushes != arg_index:
        return None
    direct = constant_of(p)
    if direct is not None:
        return direct[0], ga.key(p.getAddress()), direct[1]
    computed = computed_constant(p)
    if computed is not None:
        return computed[0], ga.key(computed[2].getAddress()), computed[1]
    return None


def collect_sites(prog):
    """-> (sites [(value, address, operand)], open [(function, call address)], count of call sites)."""
    listing, refs, fm = prog.getListing(), prog.getReferenceManager(), prog.getFunctionManager()
    sites, open_sites, calls = set(), [], 0
    for entry, arg in si.ID_PARAMETERS.items():
        f = fm.getFunctionAt(prog.getAddressFactory().getAddress(entry))
        for r in refs.getReferencesTo(f.getEntryPoint()):
            if not r.getReferenceType().isCall():
                continue
            calls += 1
            site = argument_site(listing, r.getFromAddress(), arg)
            if site is None:
                caller = fm.getFunctionContaining(r.getFromAddress())
                open_sites.append((caller.getName() if caller else "?", ga.key(r.getFromAddress())))
            else:
                sites.add(site)
    return sorted(sites), open_sites, calls


def main(prog):
    ap = argparse.ArgumentParser(prog="generate_string_ids.py")
    ap.add_argument("--dir", type=Path, default=Path(__file__).resolve().parent)
    ap.add_argument("--dry-run", "-n", action="store_true")
    ap.add_argument("--list", action="store_true")
    args, _ = ap.parse_known_args(sys.argv[1:])
    ng.check_program(prog)
    names = si.load_names(args.dir / si.NAMES_FILE)
    sites, open_sites, calls = collect_sites(prog)
    unnamed = sorted({v for v, _, _ in sites} - set(names))
    path = args.dir / an.FILE
    doc = json.loads(path.read_text())
    fm = prog.getFunctionManager()
    signatures = {}
    for entry in si.ID_PARAMETERS:
        have = doc.get("functions", {}).get(entry, {}).get("signature")
        if have is None:
            have = ga.describe_signature(fm.getFunctionAt(prog.getAddressFactory().getAddress(entry)))
        signatures[entry] = have
    project_names = json.loads((args.dir / "names_onwin32.json").read_text())   # an ONWIN.MAP reference writes no name
    fn_names = {e: project_names[e].get("name") for e in si.ID_PARAMETERS if e in project_names}
    for e in si.ID_PARAMETERS:
        fn_names.setdefault(e, fm.getFunctionAt(prog.getAddressFactory().getAddress(e)).getName())
    new = si.with_ids(doc, names, sites, signatures, fn_names)
    text = an.dump(new)
    print("%d call sites, %d constant sites, %d distinct ids, %d without a constant of their own: %s"
          % (calls, len(sites), len({v for v, _, _ in sites}), len(open_sites), ", ".join("%s@%s" % o for o in open_sites)))
    if unnamed:
        print("ids with no name in %s (fallback STR_nnnn): %s" % (si.NAMES_FILE, unnamed))
    if args.list:
        for value in sorted({v for v, _, _ in sites}):
            print(value, si.name_of(names, value), [a + ":%d" % o for v, a, o in sites if v == value])
    if args.dry_run or text == path.read_text():
        print("nothing written" if args.dry_run else "%s is up to date" % an.FILE)
        return
    path.write_text(text)
    print("wrote", path)


ng.run(globals(), main)
