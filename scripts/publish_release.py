"""Build and publish an AltStore update. Requires Python, xtool and authenticated gh.

On Windows, xtool and Swift run in WSL. GitHub credentials may come from Git's
credential manager. Existing workspace changes are included in the binary.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
REPO = "zwu5h/sumi"


def run(args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs).strip()


def api(path, body=None, method=None):
    args = ["gh", "api", path]
    if method:
        args += ["--method", method]
    if body is not None:
        args += ["--input", "-"]
    output = run(args, input=json.dumps(body) if body is not None else None)
    return json.loads(output) if output else None


def build_command(command):
    if sys.platform == "win32":
        directory = run(["wsl", "-e", "wslpath", "-a", str(ROOT)])
        command = ["wsl", "-e", "bash", "-lc", f"cd {shlex.quote(directory)} && {shlex.join(command)}"]
    subprocess.run(command, cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="New x.y.z version; default: increment patch")
    parser.add_argument("--resume-draft", action="store_true", help="Resume uploading the existing local version after a failed publication")
    args = parser.parse_args()
    if not os.environ.get("GH_TOKEN") and not os.environ.get("GITHUB_TOKEN"):
        # Never print credentials. Disable interactive credential-manager prompts.
        result = subprocess.run(["git", "credential", "fill"], cwd=ROOT,
                                input="protocol=https\nhost=github.com\n\n", text=True,
                                capture_output=True, env={**os.environ, "GCM_INTERACTIVE": "Never"})
        credentials = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
        if credentials.get("password"):
            os.environ["GH_TOKEN"] = credentials["password"]
    api("user")  # Fail before modifying files if authentication is unavailable.
    remote = api(f"repos/{REPO}/contents/altstore.json?ref=main")
    source = json.loads(base64.b64decode(remote["content"]))
    app = next(a for a in source["apps"] if a["bundleIdentifier"] == "com.sumi.reader")
    info_path = ROOT / "Info.plist"
    original = info_path.read_bytes()
    info = plistlib.loads(original)
    published = app["versions"]
    def version_tuple(value):
        if not re.fullmatch(r"\d+\.\d+\.\d+", value):
            raise ValueError("Expected an x.y.z version")
        return tuple(map(int, value.split(".")))
    latest = max(version_tuple(v["version"]) for v in published)
    current = max(latest, version_tuple(info["CFBundleShortVersionString"]))
    version = args.version or (info["CFBundleShortVersionString"] if args.resume_draft else f"{current[0]}.{current[1]}.{current[2] + 1}")
    if version_tuple(version) <= latest:
        raise ValueError("Release version must be newer than the published version")
    build = info["CFBundleVersion"] if args.resume_draft else str(max([int(info["CFBundleVersion"])] + [int(v.get("buildVersion", "0")) for v in published]) + 1)
    tag = f"v{version}"
    # Preserve the plist's existing formatting.
    text = original.decode("utf-8")
    for key, value in [("CFBundleShortVersionString", version), ("CFBundleVersion", build)]:
        text, count = re.subn(rf"(<key>{key}</key>\s*<string>)[^<]*(</string>)", lambda m: m[1] + value + m[2], text)
        if count != 1:
            raise ValueError(f"Missing or duplicated {key}")
    info_path.write_text(text, encoding="utf-8", newline="")
    if not args.resume_draft:
        build_command(["xtool", "dev", "build", "--configuration", "release", "--ipa"])
    ipa = ROOT / "xtool/Sumi.ipa"
    with zipfile.ZipFile(ipa) as archive:
        if archive.testzip() is not None:
            raise ValueError("Damaged IPA archive")
        package = plistlib.loads(archive.read("Payload/Sumi.app/Info.plist"))
    assert package["CFBundleShortVersionString"] == version
    assert package["CFBundleVersion"] == build
    assert package["CFBundleIdentifier"] == app["bundleIdentifier"]
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    # Stage metadata only after a successful build; retain previous downloads.
    app["versions"].insert(0, {
        "version": version, "buildVersion": build,
        "date": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
        "downloadURL": f"https://github.com/{REPO}/releases/download/{tag}/Sumi.ipa",
        "size": ipa.stat().st_size, "minOSVersion": package["MinimumOSVersion"],
    })
    source_text = json.dumps(source, indent=2, ensure_ascii=False) + "\n"
    with tempfile.TemporaryDirectory(prefix="sumi-release-") as directory:
        checksum = Path(directory) / "SHA256SUMS.txt"
        checksum.write_text(f"{digest}  Sumi.ipa\n", encoding="ascii")
        notes = Path(directory) / "notes.md"
        notes.write_text(f"Sumi {version} (build {build}) for iOS/iPadOS {package['MinimumOSVersion']}+.\n\n"
                         "Available as an update through the Sumi AltStore Classic source. "
                         "Unsigned IPA; AltStore signs it with your Apple Account.\n\n"
                         "Built from the local workspace, which may contain changes beyond the release tag. "
                         "IPA archive and version metadata verified; device testing not performed by this script.\n",
                         encoding="utf-8")
        if not args.resume_draft:
            run(["gh", "release", "create", tag, str(ipa), str(checksum), "--repo", REPO,
                 "--draft", "--title", f"Sumi {version}", "--notes-file", str(notes)])
    # The releases/tags endpoint does not resolve unpublished draft tags.
    release = next(r for r in api(f"repos/{REPO}/releases?per_page=100") if r["tag_name"] == tag)
    asset = next(a for a in release["assets"] if a["name"] == "Sumi.ipa")
    assert asset["size"] == ipa.stat().st_size and asset["digest"] == f"sha256:{digest}"
    run(["gh", "release", "edit", tag, "--repo", REPO, "--draft=false", "--latest"])
    # Publish the source only after the IPA is available. Advance main without
    # committing unrelated local changes or changing the local index/checkout.
    head = api(f"repos/{REPO}/git/ref/heads/main")["object"]["sha"]
    snapshot = api(f"repos/{REPO}/contents/altstore.json?ref={head}")
    if snapshot["sha"] != remote["sha"]:
        raise RuntimeError("AltStore source changed during build; reconcile it before publishing")
    files = {"altstore.json": source_text, "Info.plist": text,
             "AGENTS.md": (ROOT / "AGENTS.md").read_text(encoding="utf-8"),
             "scripts/publish_release.py": Path(__file__).read_text(encoding="utf-8"),
             "docs/publishing.md": (ROOT / "docs/publishing.md").read_text(encoding="utf-8")}
    tree = api(f"repos/{REPO}/git/trees", {"base_tree": head, "tree": [
        {"path": name, "mode": "100644", "type": "blob", "content": content}
        for name, content in files.items()]})
    commit = api(f"repos/{REPO}/git/commits", {"message": f"Publish Sumi {version} AltStore update",
                 "tree": tree["sha"], "parents": [head]})
    api(f"repos/{REPO}/git/refs/heads/main", {"sha": commit["sha"], "force": False}, "PATCH")
    live = api(f"repos/{REPO}/contents/altstore.json?ref=main")
    assert json.loads(base64.b64decode(live["content"])) == source
    (ROOT / "altstore.json").write_text(source_text, encoding="utf-8")
    print(f"Published {version} (build {build}): {app['versions'][0]['downloadURL']}")


if __name__ == "__main__":
    main()
