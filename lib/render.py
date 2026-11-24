"""Render orca-autopilot templates into a project folder.

Usage: render.py <vars.json> <dest> <template-dir>... [--force] [--dry-run]

- `{{NAME}}` tokens in file contents and paths are replaced from vars.json.
- Later template dirs override earlier ones (base, then preset).
- An existing file with different content is left alone and the new version is
  written next to it as `<file>.oap-new`, unless --force (then it is backed up
  to `<file>.oap-bak.<timestamp>` and replaced).
"""

import json
import re
import shutil
import sys
import time
from pathlib import Path

TOKEN = re.compile(r"\{\{([A-Z0-9_]+)\}\}")


def substitute(text, values, origin):
    def repl(match):
        key = match.group(1)
        if key not in values:
            raise SystemExit(f"{origin}: unknown template variable {{{{{key}}}}}")
        return str(values[key])
    return TOKEN.sub(repl, text)


def collect(template_dirs):
    files = {}
    for root in template_dirs:
        root = Path(root)
        for path in sorted(root.rglob("*")):
            if path.is_file() and path.name not in (".DS_Store", ".oap-preset"):
                files[path.relative_to(root).as_posix()] = path
    return files


def main(argv):
    flags = {a for a in argv if a.startswith("--")}
    args = [a for a in argv if not a.startswith("--")]
    if len(args) < 3:
        raise SystemExit(__doc__)
    values = json.loads(Path(args[0]).read_text(encoding="utf-8"))
    dest = Path(args[1])
    force, dry = "--force" in flags, "--dry-run" in flags
    stamp = time.strftime("%Y%m%d%H%M%S")
    counts = {"created": 0, "unchanged": 0, "conflict": 0, "replaced": 0}
    for rel, src in collect(args[2:]).items():
        target = dest / substitute(rel, values, rel)
        raw = src.read_bytes()
        try:
            content = substitute(raw.decode("utf-8"), values, rel).encode("utf-8")
        except UnicodeDecodeError:
            content = raw
        shown = target.relative_to(dest).as_posix()
        if target.exists():
            if target.read_bytes() == content:
                counts["unchanged"] += 1
                continue
            if force:
                print(f"  replace  {shown}  (backup .oap-bak.{stamp})")
                counts["replaced"] += 1
                if not dry:
                    shutil.copy2(target, target.with_name(f"{target.name}.oap-bak.{stamp}"))
            else:
                print(f"  conflict {shown}  → {shown}.oap-new")
                counts["conflict"] += 1
                target = target.with_name(target.name + ".oap-new")
        else:
            print(f"  create   {shown}")
            counts["created"] += 1
        if not dry:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            if src.stat().st_mode & 0o111:
                target.chmod(target.stat().st_mode | 0o755)
    print("  " + ", ".join(f"{k} {v}" for k, v in counts.items()))
    return 3 if counts["conflict"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
