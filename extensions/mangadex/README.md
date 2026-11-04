# MangaDex source repository for Sumi

Install this repository in **Settings → Sources & repositories → Add repository**:

```text
https://raw.githubusercontent.com/zwu5h/sumi/main/extensions/mangadex/repository.json
```

Choose **MangaDex · Deutsch** or **MangaDex · English**, review the hosts and choose
**Trust and install**. Open the source under Installed sources to browse or search.
Both can be installed at once. This repository is for Sumi, not Paperback.

Use a current Sumi build with scoped subdomain permissions. The first source-system
build rejected wildcard permissions; it must be updated before adding this repository.
Only `api.mangadex.org`, `uploads.mangadex.org` and subdomains of `mangadex.network`
are permitted. The installation screen explains the subdomain permission.

## What it supports

- Direct, anonymous access to MangaDex's documented public API; no Sumi backend.
- Language-specific browsing and search (up to 50 results), localized metadata and covers.
- MangaDex **Safe** titles, with the rating checked again before chapters and pages.
- All available feed pages in reading order, up to Sumi's 10,000-entry chapter limit.
- Chapter credits naming MangaDex and available scanlation groups or uploaders.
- Actual MangaDex@Home image-server URLs, using data-saver images when available.
- Exclusion of future, empty, unavailable and externally hosted chapters.
- Explicit errors for rate limits, access restrictions and unsupported responses.

There is no MangaDex account login or authorization bypass. If MangaDex requires an
account, restricts your connection, removes a chapter or applies limits, that restriction
still applies. API search results can include titles with no currently readable chapters.
MangaDex ratings are provider metadata, not a rights or suitability guarantee.

MangaDex@Home URLs expire (the API documents a 15-minute lifetime). If a page expires,
Retry refreshes the chapter's links while retaining the current page in the updated
Sumi reader. This extension does not implement offline downloads or account sync.

## Maintaining the repository

Edit `adapter.template.js`, increment the version in the builder when publishing a
behavior change, and regenerate:

```sh
python3 scripts/build_mangadex_repository.py
python3 scripts/build_mangadex_repository.py --check
node scripts/test_mangadex_source.mjs
# Optional: real API search, chapter lookup, page resolution and one image fetch.
node scripts/test_mangadex_source.mjs --live
```

Generated scripts live under `dist/` with a content hash in their filename. The manifest
also carries the full SHA-256. Keep old generated files when updating so cached indexes
and previously published versions continue to resolve. `.gitattributes` preserves LF
line endings for stable checksums. No third-party manga images are stored in this repo.

### Group removal requests

For a verified removal request, add the MangaDex group UUID to `blocked-groups.json`,
regenerate the repository, increment its version and publish the update. The adapter
excludes those groups from chapter feeds and rejects their chapters when resolving
pages. The current list is embedded in each installed version; existing users must
install the updated extension for a removal change to take effect. To request a change,
use [this repository's issues](https://github.com/zwu5h/sumi/issues).

## Attribution and terms

MangaDex provides the API and image delivery. Authors, artists and scanlation groups
retain their respective rights; this adapter does not grant rights to their works and
is not an official MangaDex app. Follow the [MangaDex API Acceptable Usage Policy](https://api.mangadex.org/docs/#acceptable-usage-policy),
including attribution, group removal requests and restrictions on ads/paid services.

Technical references: [API specification](https://api.mangadex.org/docs/static/api.yaml),
[rate limits](https://api.mangadex.org/docs/2-limitations/).
