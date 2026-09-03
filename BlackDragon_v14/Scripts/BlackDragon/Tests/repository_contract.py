#!/usr/bin/env python3
"""Repository-hygiene contract for the canonical BlackDragon source tree."""

from pathlib import Path
import re
import sys


REPO = Path(__file__).resolve().parents[4]
PRODUCT = REPO / "BlackDragon_v14"
INCLUDE_ROOT = PRODUCT / "Include"
ENTRY = PRODUCT / "Experts" / "BlackDragon" / "BlackDragon.mq5"
WORKFLOW = REPO / ".github" / "workflows" / "verify-current.yml"

checks = 0
failures: list[str] = []


def check(name: str, condition: bool, detail: str = "") -> None:
    global checks
    checks += 1
    if not condition:
        failures.append(f"{name}: {detail}".rstrip(": "))


include_re = re.compile(r'^\s*#include\s*[<"]([^>"]+)[>"]', re.MULTILINE)


def resolve_include(owner: Path, token: str) -> Path | None:
    candidates: list[Path] = []
    if token.startswith("BlackDragon/"):
        candidates.append(INCLUDE_ROOT / token)
    else:
        candidates.extend((owner.parent / token, INCLUDE_ROOT / token))
    for candidate in candidates:
        if candidate.is_file():
            return candidate.resolve()
    return None


reachable: set[Path] = set()
missing: list[str] = []
pending = [ENTRY.resolve()]
while pending:
    path = pending.pop()
    if path in reachable:
        continue
    reachable.add(path)
    text = path.read_text(encoding="utf-8")
    for token in include_re.findall(text):
        child = resolve_include(path, token)
        if child is not None:
            pending.append(child)
        elif token.startswith("BlackDragon/") or token.endswith((".mqh", ".mq5")):
            missing.append(f"{path.relative_to(REPO)} -> {token}")

all_headers = {p.resolve() for p in (INCLUDE_ROOT / "BlackDragon").rglob("*.mqh")}
orphan_headers = sorted(str(p.relative_to(REPO)) for p in all_headers - reachable)
check("include graph has no missing project include", not missing, "; ".join(missing))
check("every MQL header is production-reachable", not orphan_headers,
      "; ".join(orphan_headers))

entry_text = ENTRY.read_text(encoding="utf-8")
config_text = (INCLUDE_ROOT / "BlackDragon" / "Config.mqh").read_text(encoding="utf-8")
property_match = re.search(r'#property\s+version\s+"([^"]+)"', entry_text)
define_match = re.search(r'#define\s+BD_VERSION\s+"([^"]+)"', config_text)
property_version = property_match.group(1) if property_match else ""
display_version = define_match.group(1) if define_match else ""
check("binary and canonical versions match",
      bool(property_version) and property_version == display_version,
      f"#property={property_version!r}, BD_VERSION={display_version!r}")

workflows = sorted((REPO / ".github" / "workflows").glob("*.yml"))
check("exactly one canonical workflow", workflows == [WORKFLOW],
      ", ".join(str(p.relative_to(REPO)) for p in workflows))

workflow_text = WORKFLOW.read_text(encoding="utf-8") if WORKFLOW.is_file() else ""
native_tests = sorted((PRODUCT / "Scripts" / "BlackDragon" / "Tests").glob("Run*.mq5"))
missing_native = [p.stem for p in native_tests if p.stem not in workflow_text]
check("every native Run*.mq5 suite is in canonical workflow", not missing_native,
      ", ".join(missing_native))

model_tests = sorted((PRODUCT / "Scripts" / "BlackDragon" / "Tests").glob("*.cpp"))
missing_models = [p.name for p in model_tests if p.name not in workflow_text]
check("every C++ model suite is in canonical workflow", not missing_models,
      ", ".join(missing_models))

forbidden = [
    REPO / "ci-result",
    PRODUCT / "vibecode-kit-v5.1.skill",
    PRODUCT / "GUIDE_SoTayVanHanh.html",
    PRODUCT / "Scripts" / "BlackDragon" / "Tests" / "bench.cpp",
    PRODUCT / "Include" / "BlackDragon" / "Pyramid" / "CorePyramidT177Anchor.mqh",
]
present_forbidden = [str(p.relative_to(REPO)) for p in forbidden if p.exists()]
check("known generated/stale/orphan paths stay absent", not present_forbidden,
      ", ".join(present_forbidden))

current_docs = PRODUCT / "docs" / "vibecode"
allowed_top_docs = {
    "PROJECT_STATE.yaml",
    "CURRENT_VERSION.md",
    "REPOSITORY_CLEANUP_AUDIT.md",
}
allowed_top_docs.update(p.name for p in current_docs.glob("T17_18_*"))
unexpected_docs = sorted(
    p.name for p in current_docs.iterdir()
    if p.is_file() and p.name not in allowed_top_docs
)
check("vibecode root contains current docs only", not unexpected_docs,
      ", ".join(unexpected_docs))
check("historical governance is archived",
      (current_docs / "archive" / "README.md").is_file())

print(f"Repository contract: {checks - len(failures)} passed, {len(failures)} failed")
for failure in failures:
    print(f"FAIL: {failure}")
if failures:
    sys.exit(1)
print("ALL GREEN — canonical source, tests, version and repository layout are coherent.")
