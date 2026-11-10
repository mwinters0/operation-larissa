"""Writes docs/data/problem_fields.json: per-field meaning, answer rule and text-slot mapping for the 34
stored problem types.  Every entry was read from the decompiled ONWIN32.EXE (see tools/analysis/ghidra/ and
docs/port/DESIGN.md section 5.4); items tagged "I" are inferences (diagram code not followed to the end).

Notation
  L            educational level 0..3 (the table's level index = Player+0x0E)
  fN           field N of the record, in file order (kinds in problem_layouts32.json / problem_records.json)
  prompt/hint/solution/success   index into the type's text bundle (BNDL real id = text_bundle_real_id)
  slots        {k: source}: value substituted for template marker \\x08 + (0xD0+k)  == "{k}" in NEP_text.json dumps
               num(fN) = CompactNumber text (decimals keep their stored exp digits, fractions print "w n/d")
               int(fN) = decimal integer, str(ID) = EXE string-table string ID (see ONWIN32_strings.json)
  answer       field the typed answer is compared against; cmp = exact | near(tol, relative) | close(tol, absolute)
"""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]

EXACT = {"mode": "exact"}
def near(t, levels): return {"mode": "near", "tolerance": t, "levels": levels}
def close(t, levels): return {"mode": "close", "tolerance": t, "levels": levels}

T = {}
def add(t, name, fields, answer, cmp, prompt, hint, solution, success, slots, notes="", conf="V"):
    T[t] = dict(name=name, fields=fields, answer=answer, compare=cmp,
                text=dict(prompt=prompt, hint=hint, solution=solution, success=success),
                slots=slots, notes=notes, confidence=conf)

add(0, "Combination Lock",
    ["wheel_set (0 whole 2..9 | 5 quarter-steps | 8 tenths | 11 hundredths; selects operand wheel table @0x441e9c and answer wheel table @0x44201c)",
     "stage1 program byte 0 = operand slot (0-7)", "s1 op code (1 '+',2 '-',3 'x',4 '/', 0 '=' ends the expression)",
     "s1 operand slot", "s1 op", "s1 operand slot", "s1 op / or answer slot", "s1 answer slot or pad", "pad", "pad",
     "s1 intermediate result (num)", "s1 second intermediate (num)",
     "stage2 program (same grammar, 9 bytes: f12..f20)", "", "", "", "", "", "", "", "",
     "s2 intermediate (num)", "s2 second intermediate (num)"],
    "answer = label of ANSWER-wheel slot that follows the terminating '=' code (a 0 op byte)",
    {"mode": "wheel", "note": "no typed answer; see docs/port/DESIGN.md 3.7"},
    "0 (shown before the wheel)", "1 (after a miss: 'directed to ship')", "LockShowSolution (0x4223db) shows the worked solution (text 4..15 by wheel_set; not decoded)",
    "2 after stage 1 ('First number accepted'), 3 after stage 2 ('Lock opened')",
    {}, "Record = wheel_set byte, then TWO programs of 9 bytes each (f1-f9 and f12-f20) each followed by compact numbers (intermediate results for the solution text).", "V")

add(1, "Data Canister (access code sequence)",
    ["n0 sequence[0]", "n1 sequence[1]", "n2 sequence[2]", "n3 sequence[3]",
     "pattern kind: 0 +N, 1 -N, 2 xN, 3 /N, 4 increments grow by 1, >=5 grow by 2", "n5 step / ratio (kind>=4: first increment)", "n6 ANSWER = sequence[4]"],
    6, {"mode": "near", "tolerance": 0.03, "levels": [1], "otherwise": "exact"},
    "0", "L==0: f4+6 else min(f4,4)+1", "min(f4,4)+9", "special do_access_closing (0x417f56) (log entry)",
    {"hint": {"0": "num(f0)", "1": "num(f1)", "2": "num(f2)", "3": "num(f3)", "4": "int(round(f5))", "5": "int(f5)+d (f4>=4)", "6": "int(f5)+2d (f4>=4); d=1 if f4==4 else 2"},
     "solution": {"0": "num(f0)", "1": "num(f1)", "2": "num(f2)", "3": "num(f3)", "4": "num(f6)", "5": "num(f5) (f4<4) else int(f5)", "6": "5+d", "7": "5+2d", "8": "5+3d"}},
    "")

add(2, "Speed Graph", ["u8 speed log 1", "speed 2", "speed 3", "speed 4", "speed 5", "speed 6", "u8 sum of the six", "n7 ANSWER average (num)"],
    7, close(0.01, "all"), "0", "1", "2", "3",
    {"solution": {"0": "int(f0)", "1": "int(f1)", "2": "int(f2)", "3": "int(f3)", "4": "int(f4)", "5": "int(f5)", "6": "int(f6)", "7": "num(f7)"}},
    "Diagram plots f0..f5 [I].")

add(3, "Sonar", ["u8 distance (miles)", "u8 speed (MPH)", "n2 ANSWER hours (used when L==0)", "n3 ANSWER minutes (used when L>0; junk at L0)"],
    "L==0: 2 else 3", EXACT, "0", "L+1", "L+5", "9",
    {"prompt": {"0": "int(f0)", "1": "int(f1)", "2": "str(11210 'hours') if L==0 else str(11211 'minutes')"},
     "solution": {"0": "int(f0)", "1": "int(f1)", "2": "num(f2)", "3": "num(f3)"}}, "")

add(4, "Water Pressure", ["w0 depth (feet)", "w1 ANSWER psi (L0, exact)", "w2 lower bound (L>0)", "w3 upper bound (L>0)"],
    "L==0: 1; else any value strictly between f2 and f3", {"mode": "range", "levels": "L>0 accept f2 < ans < f3 (exclusive), L0 exact f1"},
    "0", "1", "2", "3", {"prompt": {"0": "int(f0)"}, "solution": {"0": "int(f0)", "1": "int(f1)"}},
    "Practice mode divides f1..f3 by 5. Pressure graph drawn from f0 [I].")

add(5, "Power Supply", ["n0 speed (MPH)", "n1 hours (1 at L0)", "n2 kJ per hour", "n3 ANSWER total kJ", "f4-f8: unused padding / authoring leftovers (junk beyond L0)"],
    3, EXACT, "L!=0", "(L!=0)+2", "(L!=0)+4", "6",
    {"prompt": {"0": "num(f0)", "1": "num(f1)", "2": "num(f4)", "3": "num(f5)"}, "solution": {"0": "num(f0)", "1": "num(f1)", "4": "num(f2)", "5": "num(f3)"}}, "")

add(6, "Sounder", ["n0 echo time (s)", "n1 total path = 5000*f0", "n2 ANSWER depth = f1/2"], 2, EXACT, "0", "1", "2", "3",
    {"solution": {"0": "num(f0)", "1": "num(f1)", "2": "num(f2)"}}, "Practice mode re-randomises f0/f1 (rand 0x4388c4).")

add(7, "Capsule Piece Inventory", ["n0..n4 five piece masses (grams, or oz at L2)", "n5 their total", "n6 ANSWER (g / kg / lb)"], 6, EXACT,
    "L0:0; L1: 0 if practice else 2; L2: 1; L3: 1 if practice else 2", "prompt+3", "prompt+6", "9 + (L in {1,3})",
    {"solution": {"0": "num(f5)", "1": "num(f6)"}}, "L0 grams, L1 kg (divide 1000), L2 pounds from ounces (divide 16).")

add(8, "Depth Gauge", ["u8 conversion kind: 0 ft->in, 1 ft->yd, 2 fathom->ft, 3 m->km, 4 ft->fathom", "n1 given depth", "n2 ANSWER"], 2, EXACT,
    "0", "f0+1", "f0+6", "11",
    {"prompt": {"0": "str(11036 + f0): inches, yards, feet, kilometers, fathoms"}, "solution": {"0": "num(f1)", "1": "num(f2)"}},
    "Practice L0 remaps record index.")

add(9, "Navigation Chart", ["u8 0=longitude 1=latitude", "n1 sub lon", "n2 sub lat", "n3 station lon", "n4 station lat", "n5 ANSWER difference"], 5,
    {"mode": "close", "tolerance": {"L1": 0.5, "L2": 0.2}, "otherwise": "exact"},
    "0", "1", "2", "3",
    {"prompt": {"0": "'' at L0 else str(11047 'approximate ')", "1": "str(11048 'longitude') if f0==0 else str(11049 'latitude')"},
     "solution": {"0": "str(11050 'D') at L0 else str(11051 'Approximate D')", "1": "longitude/latitude word", "2": "num(f3) (lon) | num(f4) (lat)", "3": "num(f1) (lon) | num(f2) (lat)", "4": "num(f5)"}}, "")

add(10, "Heat Sensor", ["n0 eruption temperature", "n1 current temperature", "n2 rate (deg/s)", "n3 difference f0-f1", "n4 ANSWER seconds"], 4, EXACT,
    "0", "1", "2", "3", {"solution": {"0": "num(f0)", "1": "num(f1)", "2": "num(f3)", "3": "num(f2)", "4": "num(f4)"}}, "")

add(11, "Radio-Telephone", ["w0 contacts", "u8 period 0 hour/1 day/2 week", "u8 answer unit 0 minutes/1 hours/2 seconds", "w3 ANSWER (integer)"], 3,
    close(0.3, [1, 2]), "0", "1", "solution = f1==0 ? (f2==0 ? 2 : 4) : f1==1 ? 3 : 5", "6",
    {"prompt": {"0": "int(f0)", "1": "str(11172+f1)", "2": "str(11175+f2)"}, "hint": {"3": "str(11178+f1) (an hour/a day/a week)"}, "solution": {"0": "int(f0)", "1": "int(f3)"}}, "")

add(12, "Temperature (refrigerator)", ["i8 current F", "u8 change amount", "i8 ANSWER new F"], 2, EXACT, "1 if f2<f0 else 0", "prompt+2", "prompt+4", "6",
    {"prompt": {"0": "int(f1)"}, "solution": {"0": "int(f0)", "1": "int(f1)", "2": "int(f2)"}}, "f0 and f2 are SIGNED bytes (e.g. 246 == -10). Practice mode clamps to <16 by subtracting 5.")

add(13, "Temperature conversion", ["n0 given", "n1 ANSWER (may be a negative mixed number: whole and numerator both negative)", "u8 direction 0 F->C, 1 C->F"], 1, close(0.01, "all"), "f2", "f2+2", "f2+4", "6",
    {"solution": {"0": "num(f0)", "1": "num(f1)"}}, "")

add(14, "Closed-Circuit Monitor (barnacles)", ["u8 total barnacles", "u8 unhealthy barnacles", "n2 ANSWER fraction f1/f0 (L1, kind 1) or percent (other levels, kind 0)", "n3 decimal ratio f1/f0 (percent hint)"], 2,
    {"mode": "exact", "kind_rule": "L1: answer must be typed as a fraction (kind 1)"}, "L!=1 ? 1 : 0", "prompt+2", "prompt+4", "6",
    {"solution": {"0": "int(f1)", "1": "int(f0)", "2": "num(f2)", "3": "num(f3)"}}, "Solution text shows f1 / f0.")

add(15, "Scale (rounding)", ["n0 mass", "u8 rounding place 1 ten, 2 hundred, 3 tenth, 4 hundredth, 5 thousandth", "n2 ANSWER rounded"], 2, EXACT,
    "f1-1", "f1+4", "f1+9", "15", {"solution": {"0": "num(f0)", "1": "num(f2)"}}, "")

add(16, "Distance Traveled Chart", ["w0 speed A", "w1 speed B (0 = single leg)", "f2-f5 diagram/unused", "n6 time A", "n7 time B", "n8 dist A = f0*f6", "n9 dist B", "n10 ANSWER total"], 10, EXACT,
    "0", "(L>1)+1", "(L>1)+3", "5",
    {"solution": {"0": "int(f0)", "3": "num(f6)", "4": "num(f8)", "5": "int(f1)", "8": "num(f7)", "9": "num(f9)", "10": "num(f10)"}},
    "Field order in the file is f0..f5 words then f6..f10 numbers.", "V (f2-f5 meaning I)")

add(17, "Food Supply Pie Chart", ["u8 slice selection (0..2: which food(s) the question names)", "n1 ANSWER (fraction kind 1 or percent kind 0)"], 1,
    {"mode": "exact", "kind_rule": "answer kind must equal stored f1 kind", "tolerance_L2": 0.7},
    "(f1 fraction or L!=3 ? 0 : 1) + L - 1", "prompt+3", "prompt+7", "12",
    {"prompt": {"0": "food name from text idx 13+pie-slice A", "1": "food name idx 13+slice B"}, "hint": {"2": "'fraction'/'percent' words"}, "solution": {"2": "num(f1)"}},
    "Pie slice sizes are random at draw time, not stored [I].", "I for slice semantics")

add(18, "Oil Gauge", ["u8 gauge variant", "w1 max gallons", "n2 fraction of tank left", "n3 ANSWER gallons"], 3, EXACT, "0", "1", "2", "3",
    {"solution": {"0": "num(f2)", "1": "int(f1)", "2": "num(f3)"}}, "")

add(19, "Window Crack (ruler)", ["u8 ruler 0 inch, 1 quarter-inch(L0..), 2 cm, 3 mm (selects unit word 17+f0)", "n1 end A", "n2 end B", "f3-f5 unused (0)", "n6 ANSWER length"], 6, EXACT,
    "ruler(L,f0): L0: f0==0?0:1; L1: 2; L2: f0==3?3:4; L3: f0==3?5:6", "same", "same+9", "16",
    {"prompt": {"0": "str(text idx 17+f0): inch / quarter inch / centimeter / millimeter"}, "solution": {"0": "num(f1)", "1": "num(f2)", "5": "num(f6)"}}, "")

add(20, "Toxicity Graph", ["w0 yesterday PPM", "w1 today PPM", "w2 difference", "n3 ratio", "n4 ANSWER"], 4, EXACT,
    "(f1<f0)*2 + (L!=0)  [0 dec ppm, 1 dec %, 2 inc ppm, 3 inc %]", "prompt+4", "prompt+8", "12",
    {"solution": {"0": "int(f0)", "1": "int(f1)", "2": "int(f2)", "3": "num(f3)", "4": "num(f4)"}}, "")

add(21, "Water Tank", ["w0 liters", "w1 milliliters", "w2 gallons (0 => liters given)", "w3 quarts", "w4 pints", "w5 cups", "w6 ANSWER days"], 6, EXACT,
    "L0: f2==0?1:0; L1: f2==0?3:2; L2: 4; L3: 5", "prompt+6", "prompt+12", "18",
    {"solution": {"0": "int(f0)", "1": "int(f1)", "2": "int(f2)", "3": "int(f3)", "4": "int(f4)", "5": "int(f5)", "6": "int(f6)"}}, "")

add(22, "Heading Indicator", ["w0 turn (degrees)", "w1 present heading", "u8 direction 0 port 1 starboard", "w3 ANSWER new heading"], 3, EXACT,
    "f2", "L*2+f2", "L*2+f2+4", "10", {"prompt": {"0": "int(f0)", "1": "int(f3)", "2": "int(f1)"}}, "Some solution entries (idx 6,7) are empty strings in NEP.DLL.")

add(23, "Side Ballast", ["u8 percent", "w1 total weight (lb)", "u8 side 0 starboard? 1 port (solution word str(11182) if f2==0 else str(11181))", "n3 decimal fraction of total", "n4 ANSWER pounds"], 4, EXACT,
    "f2", "f2+2", "4", "5", {"prompt": {"0": "int(f0)", "1": "int(f1)"}, "hint": {"0": "int(f0)", "1": "num(f3)"}, "solution": {"0": "side word", "1": "int(f1)", "2": "int(f0)", "3": "num(f4)"}}, "")

add(24, "Clock", ["u8 distance (miles; 0 for the 'left station' variant)", "u8 speed (MPH)", "n2 hours", "w3 present time hhmm", "w4 ANSWER time hhmm"], 4, EXACT,
    "(L==3 and f0!=0) ? 1 : 0", "prompt+2", "prompt+4", "6",
    {"prompt": {"0": "num(f2)", "1": "int(f3)", "2": "int(f0)", "3": "int(f1)", "5": "'0' if f3<1000 else ''"}, "solution": {"0": "num(f2)", "1": "int(f3)", "2": "int(f4)", "3": "int(f0)", "4": "int(f1)", "5": "zero pad f3", "6": "zero pad f4"}}, "")

add(25, "Toxicity Level Graph", ["w0..w6 seven hourly readings (PPM, 10-minute spacing)", "w7 reading asked about (L0) / intervals above normal (L>0)", "w8 ANSWER", "u8 question 0 =1000h / minutes, 1 =1100h"], 8, EXACT,
    "f9 + (L!=0)*2", "prompt+3", "prompt+6", "9", {"solution": {"0": "int(f7)", "1": "int(f8)"}}, "Normal level is 1200 PPM.")

add(26, "Speed Indicator (fast->slow)", ["u8 current speed", "n1 reduction (fraction, or percent at L2)", "u8 amount removed", "u8 ANSWER new speed"], 3,
    near(0.03, [1, 3]), "L==2", "(L==2)+2", "(L==2)+4", "6",
    {"prompt": {"0": "num(f1)"}, "solution": {"0": "int(f0)", "1": "num(f1)", "2": "int(f2)", "3": "int(f3)"}}, "")

add(27, "Speed Indicator (slow->fast)", ["u8 current speed", "n1 increase factor", "n2 unused", "u8 amount added", "u8 ANSWER new speed"], 4,
    near(0.03, [1, 3]), "(L==3 and f1.kind!=0) + (L>1)", "prompt+3", "(L==3 and f1.kind!=0) + (L>1) + 6", "9",
    {"prompt": {"0": "num(f1)"}, "solution": {"0": "int(f0)", "1": "num(f1)", "3": "int(f3)", "4": "int(f4)"}}, "")

for t, nm in ((28, "Ballast (increase)"), (29, "Ballast (decrease)")):
    add(t, nm, ["w0 target amount (lb or cents)", "w1 bitmask of one valid solution (bit i = denomination i, 10 denominations)"], "sum of selected denominations == f0",
        {"mode": "sum", "denominations": {"L0": [1, 1, 1, 1, 5, 5, 10, 25, 25, 25], "L2 (decimal display .01 .05 .10 .25)": [1, 1, 1, 1, 5, 5, 10, 25, 25, 25], "L1,L3 (powers of two)": [1, 2, 4, 8, 16, 32, 64, 128, 256, 512]}},
        "0", "1", "2", "4", {"prompt": {"0": "int(f0) (L2: shown as f0/100 decimal)"}, "solution": {"0": "'=' amount", "2..11": "denominations of f1 mask"}},
        "Denomination set by BallastMode (0x448694): L0 ->0 (cents), L1 ->2 (binary), L2 ->1 (dollars .01..), L3 ->2.")

add(30, "Food Storage", ["u8 length", "u8 width", "u8 height", "w3 stacked volume (L>=2)", "f4-f7 unused", "w8 ANSWER boxes", "u8 extra boxes (L3)", "u8 flag 1 = add extras"], 8, EXACT,
    "L==2", "(L==0?0:L-1)+f10+2", "(L==0?0:L-1)+f10+6", "10",
    {"solution": {"0": "int(f0)", "1": "int(f1)", "2": "int(f2)", "3": "int(f3)", "8": "int(f8)", "9": "int(f9)"}}, "Storage compartment holds 6 x 8 x 4 = 192 boxes (solution text 7).")

add(31, "Search Grid (area/perimeter)", ["u8 shape code", "u8 dim 1", "u8 dim 2", "u8 area 1", "u8 dim 3", "u8 dim 4", "u8 area 2", "u8 unused", "u8 ANSWER", "u8 variant 0..9 (text selector)"], 8, EXACT,
    "f9", "f9+10", "f9+20", "30", {"solution": {"0": "int(f0)", "1": "int(f2)", "2": "int(f1)", "3": "int(f3)", "4": "int(f5)", "5": "int(f4)", "6": "int(f6)", "7": "int(f7)", "8": "int(f8)"}},
    "Total search area is 100 sq km (text 21).", "V text slots / I shapes")

for t, nm in ((32, "Search Grid (fraction/decimal of grid) A"), (33, "Search Grid (fraction/decimal of grid) B")):
    add(t, nm, ["u8 shaded squares", "u8 total squares", "n2 unreduced fraction (junk if already reduced)", "n3 ANSWER (fraction kind 1 or decimal kind 0)"], 3,
        {"mode": "exact", "kind_rule": "answer kind must equal stored f3 kind"}, "f3.kind==1", "prompt+2", "prompt+4", "7",
        {"solution": {"0": "int(f0)", "1": "int(f1)", "2": "num(f2)", "3": "num(f3)"}}, "Types 32 and 33 share all code.")

out = {"_doc": (__doc__ or "").strip(), "compare_primitives": {
    "NumberCmp": "equal iff |a-b| < 1e-10 after converting both to double (fractions == decimals)",
    "NumbersNear": "|expected-answer| <= |expected| * tol",
    "NumbersClose": "|expected-answer| <= tol",
    "kind": "0 = decimal (u8 exp digits, i32 raw -> raw/10^exp), 1 = mixed fraction (i8 whole, u8 num, u16 den -> whole+num/den)"},
    "types": {str(k): v for k, v in sorted(T.items())}}
(ROOT / "docs/data/problem_fields.json").write_text(json.dumps(out, indent=1, ensure_ascii=False))
print("wrote", len(T), "types")
