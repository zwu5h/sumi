# Publish an AltStore update

Run from the repository with Python, GitHub CLI (`gh`) and xtool installed:

```sh
python scripts/publish_release.py
```

On Windows the script uses xtool in WSL and GitHub CLI on Windows. Authenticate
`gh` first, or use the existing Git credential manager login.

Each invocation increments the patch version and build number, builds the IPA,
checks its archive and embedded metadata, uploads a GitHub release and checksum,
then publishes the matching `altstore.json` on GitHub's main branch. Previous
versions stay in the source. Use `--version 1.1.0` to choose a specific newer version.
Review changes to app entitlements or privacy permissions before publishing and
update the source's `appPermissions` when needed.

The script publishes only release metadata, this script and this guide to main.
The binary is built from the local workspace. Commit and push application source
changes separately when an exact public source snapshot is needed. Existing local
changes and the Git index are preserved. If publication fails, inspect the draft or
published release before retrying; do not reuse a version already in the source.
If upload succeeded but a later publication step failed, use `--resume-draft`
with the existing local IPA to finish without changing its version or build.

## Install and update

Add this source once in AltStore Classic → Sources → +:

```text
https://raw.githubusercontent.com/zwu5h/sumi/main/altstore.json
```

After installing Sumi from this source, subsequent releases appear in AltStore's
My Apps updates. Update there; there is no need to download IPAs manually or delete
Sumi. AltServer must be reachable for signing and installation. Apple signing and
refresh requirements still apply. This source is for AltStore Classic.

AltStore compares the first compatible version entry with the installed version;
the source metadata must match the version and build embedded in the IPA.
See [AltStore's update documentation](https://faq.altstore.io/developers/updating-apps).
