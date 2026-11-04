"""Validate xtool's actual deliverable, without requiring an iOS runtime."""
from pathlib import Path
import argparse
import json
import plistlib
import struct
import subprocess
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--expect-glass", choices=["native", "fallback"], required=True)
parser.add_argument("--ipa", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
manifest = json.loads(subprocess.check_output(["swift", "package", "dump-package"], cwd=root))
settings = manifest["targets"][0].get("settings", [])
native = any(s.get("kind", {}).get("define", {}).get("_0") == "LIQUID_GLASS" for s in settings)
assert native == (args.expect_glass == "native"), f"Unexpected Liquid Glass configuration: {settings}"

app = root / "xtool" / "Sumi.app"
archive = None
if args.ipa:
    candidates = list((root / "xtool").glob("*.ipa"))
    assert candidates, "No IPA found"
    archive = zipfile.ZipFile(candidates[0])

def read_file(relative_path):
    if archive:
        return archive.read("Payload/Sumi.app/" + relative_path)
    return (app / relative_path).read_bytes()

info = plistlib.loads(read_file("Info.plist"))
assert info["CFBundleIdentifier"] == "com.sumi.reader"
assert info["CFBundleDisplayName"] == "Sumi"
assert info["MinimumOSVersion"] == "17.0", info.get("MinimumOSVersion")
binary = read_file(info["CFBundleExecutable"])
magic, cpu_type = struct.unpack_from("<II", binary)
assert magic == 0xFEEDFACF, "Expected a 64-bit Mach-O executable"
assert cpu_type == 0x100000C, "Expected an arm64 device build"
assert (b"glassEffect" in binary) == native, "Executable does not match expected Glass API path"
for artwork in ("sumi-logo",):
    content = read_file(f"Sumi_Sumi.bundle/{artwork}.png")
    assert content[:8] == b"\x89PNG\r\n\x1a\n" and len(content) > 10000
    assert content == (root / "Sources" / "Sumi" / "Resources" / f"{artwork}.png").read_bytes()
for retired in ("moonlit", "rain", "night"):
    if archive:
        assert f"Payload/Sumi.app/Sumi_Sumi.bundle/{retired}.png" not in archive.namelist()
    else:
        assert not (app / f"Sumi_Sumi.bundle/{retired}.png").exists()
assert info["CFBundleIconFile"] == "sumi-logo"
assert info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconFiles"] == ["AppIcon60x60"]
assert read_file("sumi-logo.png") == read_file("Sumi_Sumi.bundle/sumi-logo.png")
for name, size in [("AppIcon60x60@2x", 120), ("AppIcon60x60@3x", 180),
                   ("AppIcon76x76@1x", 76), ("AppIcon76x76@2x", 152), ("AppIcon83.5x83.5@2x", 167)]:
    data = read_file(name + ".png")
    assert struct.unpack_from(">II", data, 16) == (size, size), name
if archive:
    archive.close()
print(f"PASS: {args.expect_glass}, arm64 Mach-O, iOS 17 minimum, Info.plist, all bundled artwork" + (", IPA archive" if args.ipa else ""))
