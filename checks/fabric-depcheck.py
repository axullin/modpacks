"""Approximate Fabric Loader's dependency resolution for a built mods directory.

Usage: fabric-depcheck.py <mods-dir> <loader-version> <minecraft-version> <java-major>

Reports, and exits non-zero on:
  MISSING   a mod depends on a mod id nothing provides
  VERSION   a dependency is present but outside the required range
  BREAKS    a mod declares it breaks with a version that is present
  BYTECODE  a mod ships classes newer than the target Java can load
            (Fabric does not catch this one, the game crashes at runtime)

Nested (jar-in-jar) mods whose Java requirement is not met are skipped,
like Fabric Loader does.
"""

import io
import json
import os
import re
import sys
import zipfile


def parse_version(v):
    v = v.split("+", 1)[0]
    core, _, pre = v.partition("-")
    nums = []
    for part in core.split("."):
        m = re.match(r"(\d+)", part)
        nums.append(int(m.group(1)) if m else 0)
    return nums, pre


def cmp(a, b):
    an, ap = parse_version(a)
    bn, bp = parse_version(b)
    n = max(len(an), len(bn))
    an += [0] * (n - len(an))
    bn += [0] * (n - len(bn))
    if an != bn:
        return -1 if an < bn else 1
    if ap == bp:
        return 0
    if not ap:
        return 1
    if not bp:
        return -1
    return -1 if ap < bp else 1


def matches_one(version, pred):
    pred = pred.strip()
    if pred in ("", "*"):
        return True
    for op in (">=", "<=", ">", "<", "=", "~", "^"):
        if pred.startswith(op):
            target = pred[len(op) :].strip()
            break
    else:
        op, target = "=", pred
    if any(p.lower() == "x" for p in target.split("+")[0].split(".")):
        prefix = [p for p in target.split("+")[0].split(".") if p.lower() != "x"]
        vn, _ = parse_version(version)
        return [str(n) for n in vn[: len(prefix)]] == prefix
    c = cmp(version, target)
    if op == ">=":
        return c >= 0
    if op == "<=":
        return c <= 0
    if op == ">":
        return c > 0
    if op == "<":
        return c < 0
    if op == "=":
        return c == 0
    if c < 0:
        return False
    vn, _ = parse_version(version)
    tn, _ = parse_version(target)
    if op == "~":
        return vn[:2] == (tn + [0, 0])[:2]
    return vn[:1] == tn[:1]


def matches(version, spec):
    specs = spec if isinstance(spec, list) else [spec]
    return any(all(matches_one(version, p) for p in str(s).split()) for s in specs)


def max_class_major(zf):
    best = 0
    for name in zf.namelist():
        # Multi-release jars keep newer classes here, older JVMs ignore them
        if not name.endswith(".class") or name.startswith("META-INF/versions/"):
            continue
        with zf.open(name) as f:
            head = f.read(8)
        if len(head) == 8 and head[:4] == b"\xca\xfe\xba\xbe":
            best = max(best, int.from_bytes(head[6:8], "big"))
    return best


def scan(data, label, nested_in, mods, entries):
    try:
        zf = zipfile.ZipFile(io.BytesIO(data))
        meta = json.loads(zf.read("fabric.mod.json").decode("utf-8", "replace"), strict=False)
    except (KeyError, zipfile.BadZipFile, json.JSONDecodeError):
        return
    entries.append(
        {
            "id": meta.get("id"),
            "version": str(meta.get("version", "0")),
            "provides": meta.get("provides", []),
            "depends": meta.get("depends", {}),
            "breaks": meta.get("breaks", {}),
            "label": label,
            "nested_in": nested_in,
            "class_major": max_class_major(zf),
        }
    )
    for nested in meta.get("jars", []):
        try:
            scan(zf.read(nested["file"]), nested["file"], nested_in or meta.get("id"), mods, entries)
        except KeyError:
            pass


def main():
    mods_dir, loader, minecraft, java = sys.argv[1:5]
    builtin = {"fabricloader": loader, "minecraft": minecraft, "java": java}

    entries = []
    for name in sorted(os.listdir(mods_dir)):
        if name.endswith(".jar"):
            with open(os.path.join(mods_dir, name), "rb") as f:
                scan(f.read(), name, None, {}, entries)

    # Fabric skips nested mods that cannot run on this Java
    entries = [
        e
        for e in entries
        if e["nested_in"] is None or "java" not in e["depends"] or matches(java, e["depends"]["java"])
    ]

    # Fabric picks the newest copy when several jars bundle the same mod
    mods = dict(builtin)
    for e in entries:
        for key in [e["id"], *e["provides"]]:
            if key not in builtin and (key not in mods or cmp(e["version"], mods[key]) > 0):
                mods[key] = e["version"]

    max_major = 44 + int(java)
    problems = set()
    for e in entries:
        where = e["id"] if e["nested_in"] is None else f"{e['id']} (nested in {e['nested_in']})"
        for dep, spec in e["depends"].items():
            if dep not in mods:
                if e["nested_in"] is None:
                    problems.add(f"MISSING   {where} needs {dep} {spec}")
            elif not matches(mods[dep], spec):
                problems.add(f"VERSION   {where} needs {dep} {spec}, have {mods[dep]}")
        for dep, spec in e["breaks"].items():
            if dep in mods and matches(mods[dep], spec):
                problems.add(f"BREAKS    {where} breaks with {dep} {spec}, have {mods[dep]}")
        if e["class_major"] > max_major:
            problems.add(
                f"BYTECODE  {where} ({e['label']}) needs Java {e['class_major'] - 44}, target is Java {java}"
            )

    print(f"{mods_dir}: {len(entries)} mods checked against loader {loader}, Minecraft {minecraft}, Java {java}")
    for p in sorted(problems):
        print(p)
    sys.exit(1 if problems else 0)


main()
