"""Verify the generated static repository and its real JavaScript adapter in Node.

This does not substitute for WebKit or reader testing on an iPhone.
"""
from pathlib import Path
import subprocess
import tempfile
from build_source_repository import build

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="sumi-source-") as directory:
    output = Path(directory)
    build("https://sources.example.org/originals", output)
    subprocess.run(["node", str(root / "scripts/test_source_extension.mjs"), str(output)], check=True)
