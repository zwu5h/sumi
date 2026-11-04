"""Build a static Sumi demo repository from this project's original artwork.

Host the output directory on any static HTTPS host. No backend is needed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
from urllib.parse import urlsplit


def build(base_url: str, output: Path):
    root = Path(__file__).resolve().parents[1]
    base_url = base_url.rstrip("/")
    parts = urlsplit(base_url)
    if (parts.scheme != "https" or not parts.hostname or "." not in parts.hostname
            or parts.username or parts.password or parts.query or parts.fragment
            or parts.port not in (None, 443)):
        raise ValueError("Use the public HTTPS URL of the directory, without a query or fragment")
    output.mkdir(parents=True, exist_ok=True)
    code = (root / "examples/sumi-originals/source.js").read_text(encoding="utf-8")
    code = code.replace("__SUMI_BASE_URL__", json.dumps(base_url))
    code_bytes = code.encode("utf-8")
    (output / "source.js").write_bytes(code_bytes)
    catalog = []
    for title_id, title, artwork in [
        ("moon", "Under a Paper Moon", "moonlit"),
        ("rain", "The Sound of Rain", "rain"),
        ("night", "Where the Night Ends", "night"),
    ]:
        filename = artwork + ".png"
        shutil.copyfile(root / "examples/sumi-originals/artwork" / filename, output / filename)
        catalog.append({
            "id": title_id, "title": title, "author": "Sumi Studio",
            "synopsis": "An original Sumi illustration for testing online sources. This demo contains one illustrated page, not a full comic.",
            "genre": "Original illustration", "cover": base_url + "/" + filename,
            "chapters": [{"id": title_id + "-preview", "title": "Original illustration",
                          "credit": "Sumi Studio", "pages": [base_url + "/" + filename]}],
        })
    (output / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    index = {
        "schemaVersion": 1, "name": "Sumi original illustrations",
        "extensions": [{
            "id": "studio.sumi.originals", "name": "Sumi originals", "version": "1.0.0",
            "apiVersion": 1, "script": base_url + "/source.js",
            "sha256": hashlib.sha256(code_bytes).hexdigest(), "hosts": [parts.hostname],
            "website": base_url + "/", "author": "Sumi Studio",
        }],
    }
    (output / "repository.json").write_text(json.dumps(index, indent=2) + "\n", encoding="utf-8")
    (output / "index.html").write_text(
        '<!doctype html><meta charset="utf-8"><title>Sumi original illustrations</title>'
        '<h1>Sumi original illustrations</h1><p>A test source containing original Sumi artwork.</p>'
        '<p><a href="repository.json">Sumi source repository</a></p>', encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.base_url, args.output)
    print("Repository built. Host this directory, then add: " + args.base_url.rstrip("/") + "/repository.json")
