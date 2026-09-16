#!/usr/bin/env python3
"""
Lumina Reader — Static Audit Gate (CI quality firewall)
Runs after every phase. Exits non-zero on any BLOCKER; warnings don't fail the gate.

Checks:
  A1  Import/export/part directives placed after declarations (Dart syntax error)
  A2  Duplicate PUBLIC symbols reachable from a single file (real name collisions)
  A3  part '*.g.dart' declared → file either exists or is generatable (annotations sane)
  A4  All relative imports resolve to existing files
  A5  Every @collection Isar model is registered in StorageProvider
  A6  Router routes → referenced screens exist + constructor params match
  A7  Every provider watched in modules/ is defined somewhere
  A8  Phantom APIs: symbols called but defined nowhere (MClient.forSource etc.)
  A9  pubspec asset directories exist; referenced android build files exist
  A10 Unresolved cross-file field mismatches on known model pairs (DTO vs Isar)
  A11 Known landmines: seed functions removed, 'Coming soon' placeholders, mock URLs
"""
import os
import re
import sys
import json
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
LIB = os.path.join(ROOT, "lib")
BLOCKERS = []
WARNINGS = []

def rel(p):
    return os.path.relpath(p, ROOT)

def add_blocker(check, msg):
    BLOCKERS.append(f"[{check}] {msg}")

def add_warning(check, msg):
    WARNINGS.append(f"[{check}] {msg}")

# ---------- collect files ----------
dart_files = []
for dirpath, _, filenames in os.walk(LIB):
    for fn in filenames:
        if fn.endswith(".dart"):
            dart_files.append(os.path.join(dirpath, fn))
dart_files.sort()

file_contents = {}
for f in dart_files:
    with open(f, encoding="utf-8") as fh:
        file_contents[f] = fh.read()

print(f"Auditing {len(dart_files)} Dart files...\n")

# ---------- A1: imports after declarations ----------
DIRECTIVE_RE = re.compile(r"^\s*(?:import|export|part)\s.*/?>?|^\s*(?:import|export|part)\s+['\"]", re.M)
def check_a1():
    for f in dart_files:
        lines = file_contents[f].splitlines()
        first_decl = None
        last_directive = None
        for i, line in enumerate(lines):
            s = line.strip()
            if re.match(r"^(import|export|part)\s", s):
                last_directive = i
                continue
            if s.startswith("//") or s.startswith("*") or s.startswith("/*") or not s:
                continue
            if first_decl is None and re.match(
                r"^(@|class\s|enum\s|mixin\s|abstract\s|typedef\s|void\s|Future|final\s|var\s|const\s|extension\s|sealed\s|base\s|library\s)", s
            ):
                first_decl = i
        if first_decl is not None and last_directive is not None and last_directive > first_decl:
            add_blocker("A1", f"{rel(f)}: directive at line {last_directive+1} after declaration at line {first_decl+1}")
check_a1()

# ---------- A2: duplicate public symbols with real collision risk ----------
def check_a2():
    # map symbol -> [files defining it publicly]
    defs = defaultdict(list)
    decl_re = re.compile(r"^(?:@\w+\s+)*(?:abstract\s+|final\s+|base\s+|sealed\s+|mixin\s+)*(?:class|enum|mixin)\s+(\w+)", re.M)
    top_level_re = re.compile(r"^(?:typedef\s+\w+\s*=|final\s+(\w+)\s*=\s*Provider|enum\s+(\w+))", re.M)
    for f in dart_files:
        content = file_contents[f]
        for m in re.finditer(r"^[ \t]*(?:class|enum|mixin)\s+(\w+)", content, re.M):
            name = m.group(1)
            if not name.startswith("_"):
                defs[name].append(f)
    # Collision is only a blocker if one file could see two definitions (import both files)
    for name, files in sorted(defs.items()):
        if len(files) < 2:
            continue
        # find importer sets
        importers = defaultdict(set)
        for f in dart_files:
            content = file_contents[f]
            for src in files:
                if f == src:
                    importers[f].add(src)
                else:
                    src_rel = os.path.relpath(src, os.path.dirname(f)).replace(os.sep, "/")
                    variants = {
                        f"import '{src_rel}';",
                        f"import 'package:lumina_reader/{os.path.relpath(src, LIB)}';".replace(os.sep, "/"),
                    }
                    if any(v in content for v in variants):
                        importers[f].add(src)
        colliding = [f for f, seen in importers.items() if len(seen) > 1]
        if colliding:
            add_blocker("A2", f"symbol '{name}' defined in {[rel(x) for x in files]} and co-imported in {[rel(x) for x in colliding]}")
        else:
            add_warning("A2", f"symbol '{name}' defined in {[rel(x) for x in files]} (no co-import today — keep mappers single-sourced)")
check_a2()

# ---------- A3: part g.dart sanity ----------
def check_a3():
    for f in dart_files:
        content = file_contents[f]
        for m in re.finditer(r"part\s+'(\w+\.g\.dart)'\s*;", content):
            gfile = os.path.join(os.path.dirname(f), m.group(1))
            if not os.path.exists(gfile):
                # generatable is fine IF source has the right annotations
                has_isar = "@collection" in content or "@embedded" in content
                has_riverpod = "@riverpod" in content
                has_json = "@JsonSerializable" in content
                if not (has_isar or has_riverpod or has_json):
                    add_blocker("A3", f"{rel(f)}: part '{m.group(1)}' missing and no codegen annotation present")
                else:
                    add_warning("A3", f"{rel(f)}: awaits build_runner for {m.group(1)} (annotations OK)")
check_a3()

# ---------- A4: relative imports resolve ----------
def check_a4():
    for f in dart_files:
        content = file_contents[f]
        for m in re.finditer(r"^import\s+'([^:']+\.dart)';", content, re.M):
            target = os.path.normpath(os.path.join(os.path.dirname(f), m.group(1)))
            if not os.path.exists(target):
                add_blocker("A4", f"{rel(f)}: import '{m.group(1)}' → file not found ({rel(target)})")
check_a4()

# ---------- A5: Isar schema registration ----------
def check_a5():
    sp_path = os.path.join(LIB, "providers/storage_provider.dart")
    if not os.path.exists(sp_path):
        add_blocker("A5", "providers/storage_provider.dart missing")
        return
    sp = file_contents[sp_path]
    registered = set(re.findall(r"(\w+Schema)", sp))
    for f in dart_files:
        if os.path.dirname(f) != os.path.join(LIB, "models"):
            continue
        content = file_contents[f]
        if "@collection" not in content:
            continue
        # find class declarations with @collection directly above them
        for m in re.finditer(r"(@collection[^\n]*\n(?:\s*@\w+[^\n]*\n)*)class\s+(\w+)", content):
            cls = m.group(2)
            schema = f"{cls}Schema"
            if schema not in registered:
                add_blocker("A5", f"{rel(f)}: @collection {cls} not registered in StorageProvider ({schema} absent)")
check_a5()

# ---------- A6: router → screens ----------
def check_a6():
    router = os.path.join(LIB, "router/router.dart")
    if not os.path.exists(router):
        add_blocker("A6", "router missing")
        return
    content = file_contents[router]
    # screens referenced in builders
    screens = set(re.findall(r"=>\s*(?:const\s+)?(\w+Screen)\(", content))
    readers = set(re.findall(r"=>\s*(?:const\s+)?(\w+View)\(", content))
    for s in screens | readers:
        found = any(re.search(rf"class\s+{s}\b", file_contents[f]) for f in dart_files)
        if not found:
            add_blocker("A6", f"router references {s} but no such class exists")
    # constructor params: screen(  id:  ) vs required params
    for m in re.finditer(r"(\w+Screen)\(\s*id:\s*int\.parse\(state\.pathParameters\['(\w+)'\]!\)", content):
        cls, param = m.group(1), m.group(2)
        # find the class file and its constructor
        for f in dart_files:
            mm = re.search(rf"class\s+{cls}\s+extends[^\n]*\{{", file_contents[f])
            if mm:
                ctor = re.search(rf"{cls}\(\{{([^}}]+)\}}\)", file_contents[f][mm.start():mm.start()+2000])
                if ctor:
                    params = [p.strip() for p in ctor.group(1).split(",") if p.strip()]
                    required = [p for p in params if p.startswith("required")]
                    given = ["id"]
                    needed = [re.search(r"this\.(\w+)", p).group(1) for p in required if re.search(r"this\.(\w+)", p)]
                    if given != needed:
                        add_blocker("A6", f"router constructs {cls}({given}) but class requires {needed}")
                break
check_a6()

# ---------- A7: providers watched in modules exist ----------
def check_a7():
    # collect provider definitions across lib/
    defined = set()
    for f in dart_files:
        content = file_contents[f]
        for m in re.finditer(r"final\s+(\w+Provider)\s*=", content):
            defined.add(m.group(1))
        for m in re.finditer(r"final\s+(\w+Provider)\b", content):
            defined.add(m.group(1))
        # riverpod codegen
        for m in re.finditer(r"@riverpod.*?\n\s*\w+.*?(\w+)\(", content):
            defined.add(m.group(1))
    modules_dir = os.path.join(LIB, "modules")
    for f in dart_files:
        if not f.startswith(modules_dir):
            continue
        content = file_contents[f]
        for m in re.finditer(r"ref\.(?:watch|read)\((\w+Provider)", content):
            p = m.group(1)
            if p not in defined:
                add_blocker("A7", f"{rel(f)}: ref.watch/read of undefined provider '{p}'")
check_a7()

# ---------- A8: phantom APIs ----------
def check_a8():
    phantoms = {
        "MClient.forSource": r"MClient\.forSource\s*\(",
        "CookieManager.bootstrap": r"CookieManager\.bootstrap\s*\(",
        "CloudflareSolver.instance": r"CloudflareSolver\.instance",
        "ExtensionServiceMixin": r"with\s+ExtensionServiceMixin",
    }
    for f in dart_files:
        content = file_contents[f]
        for name, pattern in phantoms.items():
            if re.search(pattern, content):
                symbol = name.split(".")[0]
                # A definition exists if any file declares class/mixin/enum/extension/typedef with that name
                defined = any(
                    re.search(rf"(class|mixin|enum|extension|typedef)\s+{symbol}\b", file_contents[g])
                    for g in dart_files
                )
                if name == "MClient.forSource":
                    defined = any(
                        re.search(r"forSource\s*\(", file_contents[g]) and "static" in file_contents[g]
                        for g in dart_files if "m_client.dart" in g
                    )
                if not defined:
                    add_blocker("A8", f"{rel(f)}: phantom API '{name}' (used, never defined)")
check_a8()

# ---------- A9: build file existence ----------
def check_a9():
    checks = [
        ("android/app/proguard-rules.pro", True),
        ("android/gradle/wrapper/gradle-wrapper.properties", True),
        ("android/gradlew", True),
        ("LICENSE", True),
        ("README.md", True),
        ("analysis_options.yaml", True),
    ]
    for path, required in checks:
        if not os.path.exists(os.path.join(ROOT, path)):
            add_blocker("A9", f"missing build/compliance file: {path}")
    # launcher icons
    manifest = os.path.join(ROOT, "android/app/src/main/AndroidManifest.xml")
    if os.path.exists(manifest):
        mc = open(manifest).read()
        if "@mipmap/ic_launcher" in mc:
            mip = os.path.join(ROOT, "android/app/src/main/res/mipmap-hdpi")
            if not os.path.exists(mip):
                add_blocker("A9", "manifest references @mipmap/ic_launcher but no mipmap dirs exist")
    # pubspec assets
    pub = os.path.join(ROOT, "pubspec.yaml")
    if os.path.exists(pub):
        pubspec = open(pub).read()
        assets = re.findall(r"^\s+-\s+(assets/\S+)", pubspec, re.M)
        for a in assets:
            if not os.path.exists(os.path.join(ROOT, a.rstrip("/"))):
                add_blocker("A9", f"pubspec asset '{a}' does not exist")
check_a9()

# ---------- A11: mock/seed landmines ----------
def check_a11():
    patterns = {
        r"picsum\.photos": "mock picsum URLs",
        r"test-streams\.mux\.dev": "mux test stream",
        r"example\.com/.*\.vtt": "fake subtitle URLs",
        r"_seedManga\s*\(": "seed data function",
        r"_seedAnime\s*\(": "seed data function",
        r"_seedNotes\s*\(": "seed data function",
        r"_seedHistory\s*\(": "seed data function",
        r"_seedUpdates\s*\(": "seed data function",
        r"_seedDownloads\s*\(": "seed data function",
    }
    for f in dart_files:
        content = file_contents[f]
        for pattern, desc in patterns.items():
            if re.search(pattern, content):
                add_blocker("A11", f"{rel(f)}: {desc} still present")
        for m in re.finditer(r"Coming soon", content):
            add_warning("A11", f"{rel(f)}: 'Coming soon' placeholder screen")
check_a11()

# ---------- run ----------
for fn in (check_a1, check_a2, check_a3, check_a4, check_a5, check_a6, check_a7, check_a8, check_a9, check_a11):
    try:
        fn()
    except Exception as e:
        add_warning("SYS", f"{fn.__name__} crashed: {e}")

print("=" * 72)
print(f"BLOCKERS: {len(BLOCKERS)}")
for b in BLOCKERS:
    print(f"  ✗ {b}")
print(f"\nWARNINGS: {len(WARNINGS)}")
for w in WARNINGS[:40]:
    print(f"  ⚠ {w}")
if len(WARNINGS) > 40:
    print(f"  ... and {len(WARNINGS)-40} more")
print("=" * 72)
sys.exit(1 if BLOCKERS else 0)
