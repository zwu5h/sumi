# Releases

When asked to publish a new Sumi version or IPA, use
`python scripts/publish_release.py` (or `--version x.y.z`). Every release must
remain available as an update in AltStore Classic: increase the embedded version
and build number, upload the IPA, and publish matching metadata as the first
entry of the public `altstore.json`. Do not consider a GitHub-only upload complete.
Keep `com.sumi.reader` and the existing source URL stable so installed apps can
update in place. See `docs/publishing.md` for prerequisites and the workflow.
