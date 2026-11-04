"""Run the reader's persistence and progress checks without an iOS runtime."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="sumi-position-") as directory:
    executable = Path(directory) / "reading-position-checks"
    subprocess.run([
        "swiftc", str(root / "Sources/Sumi/ReadingPosition.swift"),
        str(root / "Tests/ReadingPositionChecks.swift"), "-o", str(executable),
    ], check=True)
    subprocess.run([str(executable)], check=True)
