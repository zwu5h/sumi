"""Generate the installable MangaDex repository and content-addressed scripts."""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / "extensions/mangadex"
BASE = "https://raw.githubusercontent.com/zwu5h/sumi/main/extensions/mangadex"


def generated_files():
    template = (DIRECTORY / "adapter.template.js").read_text(encoding="utf-8")
    blocked = json.loads((DIRECTORY / "blocked-groups.json").read_text(encoding="utf-8"))
    if (not isinstance(blocked, list) or len(blocked) != len(set(blocked)) or
            any(not isinstance(item, str) or not re.fullmatch(r"[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}", item) for item in blocked)):
        raise ValueError("blocked-groups.json must contain unique lowercase MangaDex group UUIDs")
    files = {}
    extensions = []
    for language, label in [("de", "Deutsch"), ("en", "English")]:
        code = template.replace("__SUMI_MANGADEX_LANGUAGE__", json.dumps(language))
        code = code.replace("__SUMI_MANGADEX_BLOCKED_GROUPS__", json.dumps(blocked))
        content = code.encode("utf-8")
        digest = hashlib.sha256(content).hexdigest()
        name = f"dist/mangadex-{language}-{digest[:16]}.js"
        files[name] = content
        extensions.append({
            "id": f"org.zwu5h.mangadex.{language}", "name": f"MangaDex · {label}",
            "version": "1.4.0", "apiVersion": 1, "script": f"{BASE}/{name}", "sha256": digest,
            "hosts": ["api.mangadex.org", "uploads.mangadex.org", "*.mangadex.network"],
            "website": "https://mangadex.org/", "author": "zwu5h · unofficial adapter",
        })
    files["repository.json"] = (json.dumps({
        "schemaVersion": 1, "name": "Sumi · MangaDex sources", "extensions": extensions,
    }, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    return files


def build(check=False):
    for name, content in generated_files().items():
        target = DIRECTORY / name
        if check:
            if not target.exists() or target.read_bytes() != content:
                raise ValueError(f"Regenerate {target.relative_to(ROOT)}")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build(args.check)
    print("MangaDex repository verified" if args.check else BASE + "/repository.json")
