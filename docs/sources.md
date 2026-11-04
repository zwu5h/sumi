# Sumi source extensions

Sumi supports user-added HTTPS repository indexes and separately installed JavaScript
sources. The app requests catalogs and chapter pages directly; it does not require a
Sumi backend. Repositories and scripts need static HTTPS hosting, which can be provided
by their authors. This follows Paperback's general extension model, but uses **Sumi
Source API v1**, not Paperback's SDK or repository format.

## Use in the app

1. Open Settings → Sources & repositories, or Discover → Browse your sources.
2. Add the full HTTPS URL of a `repository.json` file.
3. Select an extension, review its author, repository and allowed network hosts, then
   choose Trust and install.
4. Open the installed source and search. An empty query asks the extension for a
   browsing selection. Open a title, then a chapter to read it.
5. Bookmark a title to keep it in Library. Reading progress is saved locally. Refreshing
   a title remaps progress by chapter ID when the source's chapter order changes.

In a source catalog, open **Filters** to search and select tags, match all or any selected
tags, choose publication status and sort results. Apply combines these choices with the
title query; Cancel discards edits, and Clear filters restores the source defaults.
Only filters provided by the installed extension are shown. Existing MangaDex installations
need adapter version 1.1.0 or newer from the maintained `sumi-extensions` repository. Refreshing
the repository alone does not update an installed script; review and install its new version.

Content options come from the source, alongside its other filters. Sumi does not add
a separate NSFW switch or an additional content restriction. For example, MangaDex
provides content ratings and ToonTop provides content rating and edition options.
Tags retain the order supplied by the extension. Older saved NSFW preferences are
ignored; the source's defaults and selected filters determine the catalog.

Swipe an installed source to remove it. Removing a repository also removes its installed
extensions. Saved titles and progress remain, with an explicit reinstall error when the
source is unavailable. Refreshing an index never updates executable code silently:
select the new version and review its installation again. A different repository cannot
replace an already installed source with the same ID.
Installation checks script syntax and the three required method definitions in WebKit
before committing the extension; a failed update keeps the previously installed version.

Online pages require a connection. PDFs remain the supported offline format. Source
authentication, automatic update polling and Paperback SDK compatibility
are not implemented in v1.

## A repository without a backend

The included builder packages this project's original illustrations and a working
extension into a static directory. Replace the URL below with your actual hosting
directory, then upload the generated directory to that location:

```sh
python3 scripts/build_source_repository.py \
  --base-url https://YOUR-HOST.example/sumi-originals \
  --output /tmp/sumi-originals
```

Add `https://YOUR-HOST.example/sumi-originals/repository.json` in the app. The placeholder
above is not a live repository. The builder includes one illustrated page per original
sample title, not complete manga chapters. Regenerate the repository after changing
the hosting URL or script; the script's SHA-256 is generated automatically.

## Repository index

```json
{
  "schemaVersion": 1,
  "name": "My sources",
  "extensions": [{
    "id": "org.example.my-source",
    "name": "My source",
    "version": "1.0.0",
    "apiVersion": 1,
    "script": "https://sources.example.org/source.js",
    "sha256": "SHA256_OF_EXACT_SCRIPT_BYTES_AS_64_HEX_CHARACTERS",
    "hosts": ["api.example.org", "images.example.org"],
    "website": "https://example.org/",
    "author": "Source author"
  }]
}
```

URLs must be absolute HTTPS URLs. `hosts` lists exact lowercase domains or explicit
scoped subdomain permissions such as `*.mangadex.network`. A subdomain permission
matches descendants only, not the parent domain or similarly named domains, and is
explained at installation. Bare wildcards, literal IPs, credentials in URLs,
nonstandard ports and common local host suffixes are rejected. API requests and images,
including redirects, must stay on this list. Index
and script downloads can use their own host, and redirects must stay on that download
host. A checksum detects a mismatched download; it is **not** an author signature or
proof that a repository is trustworthy.

An optional `imageReferer` URL lets a source declare the public website reference
required by its image server, for example `"imageReferer": "https://toontop.io/"`.
It must use HTTPS and the same host as `website`, with no credentials, nonstandard
port, path beyond `/`, query or fragment. Installation shows this reference.
Sumi sends it as the `Referer` header for covers and chapter images only, preserving
it across redirects to permitted hosts. Script/index downloads and extension API
requests do not receive it. Existing manifests without it retain their previous
behavior. ToonTop requires a new app build containing this support; earlier builds
ignore the field and its images fail with HTTP 403.

## Source API v1

A ready-to-install [MangaDex repository](https://github.com/zwu5h/sumi-extensions) is maintained
separately from the app bundle, with German and English adapters. Its public index is
`https://raw.githubusercontent.com/zwu5h/sumi-extensions/main/repository.json`.
It requires the updated app with scoped subdomain permissions.

Publish a single UTF-8 JavaScript file defining `const source = { ... }`. Bundle your
dependencies into that file; runtime imports of external scripts are blocked. Each
method receives an input object and `api`. Methods may return values or promises.

```js
const source = {
  async search({ query }, api) {
    const response = await api.request(
      'https://api.example.org/titles?q=' + encodeURIComponent(query)
    );
    return response.json().map(item => ({
      id: item.id, title: item.title, author: item.author,
      synopsis: item.description, genre: item.genre,
      cover: item.coverURL // absolute HTTPS URL, or null
    }));
  },
  async chapters({ mangaID }, api) {
    // Return earliest-to-latest reading order, using stable, unique IDs.
    return [{ id: 'chapter-1', title: 'Chapter 1', credit: 'Creator / group' }];
  },
  async pages({ mangaID, chapterID }, api) {
    // URLs in reading order, with image hosts declared in the manifest.
    return ['https://images.example.org/chapter-1/page-1.png'];
  }
};
```

`api.request(url)` performs an HTTPS GET and resolves to `{text, json()}`. `text` is
a UTF-8 string; `json()` parses it. Authentication, arbitrary headers, request bodies,
cookies and shared browser credentials are not available. Non-2xx HTTP responses reject
the promise. HTML can be parsed with the WebKit DOM APIs (`DOMParser`). Return plain
JSON-serializable data. All title metadata fields shown above and chapter `credit`
must be present (an empty credit string is permitted).

Catalogs show **Load more** beside the title count and below the titles when the
extension returns another page. Changing the query, sorting or filters starts a
new catalog; failures while loading more keep the titles already visible.
ToonTop 1.2.0 supports native genres (including exclusions), publication
status, content rating, edition and additional source filters, together with
latest updates, recently added, followers, rating, chapter count and views
(today/week/month/all time). Refresh the repository and install the updated source.
The extension supplies the available sort options.

`search` receives `page: "1"` initially. A paginated extension can return
`{titles: [...], nextPage: "2"}` instead of the legacy title array. `nextPage` is an
opaque string passed back as `page` with the same query and filters; return `null`
or omit it at the end. Never repeat the requested cursor. A page with every title
hidden by content filters must still return its next cursor. Legacy arrays remain
supported and have no additional pages. To support older app builds, extensions can
return a legacy array when the input does not contain `page`.

Limits: 100 extensions per index, 200 titles per catalog page, 10,000 chapters per title,
500 pages per chapter, 30 network requests per invocation, 4 simultaneous requests,
4 MB text responses and 20 MB image downloads. Scripts have a 1 MB download limit;
indexes have a 500 KB limit. An invocation has a 35-second deadline. Images are
downsampled by width and a 32-megapixel decoded-image budget, preserving the width
of long webtoon strips. The paged reader loads only the current and adjacent pages.
MangaDex adapters prefer original chapter images and fall back to data-saver images
only when originals are absent (maintained adapter version 1.3.0).

## Optional catalog filters (API v1)

The optional `groups` array supports additional source-specific fields. Each group is
`{id: "type", name: "Type", options: [{id: "manhwa", name: "Manhwa"}], multiple: false}`.
Omitting `multiple` means single selection. An empty options array renders a text field.
The search input `filters` is a JSON object mapping group IDs to arrays of selected IDs
or the entered text. Empty arrays mean source default. Source adapters validate and apply
these values on the provider before pagination. `supportsExcludedTags: true` enables
tri-state tags (any/included/excluded), passed as the JSON array string `excludedTags`.
`tagModes` may restrict inclusion matching to `["AND"]`; its legacy default is AND/OR.
All input, including extra groups and exclusions, participates in search identity and
Load more, so stale pages cannot be appended after a filter changes.

Chapter history is stored separately from the most recent resume position. It is scoped
to the active profile and keyed by source chapter ID, including when chapters are reordered.
Resetting a title clears all its chapter positions. Existing data migrates only the known
chapter; no earlier chapters are assumed read.

Extensions may implement `async filters(input, api)` returning an object with `tags`,
`statuses` and `sortOrders` arrays. Each option is `{id: "stable-value", name: "Display name"}`;
return empty arrays (or omit them) for unsupported controls. IDs must be unique within each array.
There are at most 500 options per array; IDs have at most 500 characters and names 120.
Older extensions without this method remain searchable and show an unavailable-filters message.
The legacy boolean `supportsNSFW` is accepted for compatibility but does not add a
control. Declare source content options through `groups`, just like other filters.

`search` additionally receives string fields `tags` (a JSON-encoded array of selected IDs),
`tagMode` (`AND` or `OR`), `status` and `sort` (selected option IDs, or empty strings for
source defaults). Extensions apply these together with `query` to their full catalog,
before limiting results. Filter discovery runs independently from title searches, and
its failure can be retried without blocking the existing title search.

## Source content setting (API v1)

`search`, `chapters` and `pages` receive `allowNSFW: "true"` for compatibility with
older adapters, so they do not require a separate app-level unlock. Content filtering
belongs to the source's native filters and defaults. Extensions that ignore this
field retain their existing behavior.

## Execution and privacy

Each method runs in a fresh nonpersistent WKWebView. A restrictive document CSP blocks
direct web requests and external resources; the only supplied native message handler
is the host-checked GET bridge. Navigation away from the blank runtime document is
blocked. The runtime is closed on success, failure, cancellation, timeout or WebKit
process termination. Extensions receive their input arguments, not the library,
local PDFs, reading positions, account credentials or device permissions.

The source's server can see the user's IP address and whatever query or title/chapter
IDs are sent to it. Installation discloses the declared hosts before execution.
Third-party scripts remain untrusted code: the checks do not establish content rights
or guarantee that the author is honest. Local library records and installed source
code are persisted on the device. No analytics or Sumi service is introduced.

## Verification and App Review

```sh
python3 scripts/test_library_import.py
python3 scripts/test_reading_position.py
python3 scripts/test_source_repository.py
xtool dev build
python3 scripts/verify_build.py --expect-glass native
```

The first check also tests repository validation, host permissions, legacy library
migration and stable chapter IDs. The JS check uses the real generated adapter with
fixture responses, not iOS WebKit. On a device, test install → search → chapter list →
page images → pinch zoom → bookmark → relaunch/resume, plus update consent, removal,
offline errors, denied hosts/redirects and a deliberately nonterminating extension.

This implementation is not a claim of App Store approval. Before submission, disclose
the runtime and request bridge, provide an accessible original-content test repository,
and resolve Apple's classification of the extension system. If guideline 4.7 applies,
address its complete requirements, including the software index with universal links,
moderation/reporting, age controls, and prior permission where native platform APIs or
technologies are exposed. Those submission requirements are not implemented by merely
adding a source manager. Content/service rights and each provider's API terms remain
separate requirements. No MangaDex source or third-party content catalog is bundled.

References: [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/),
[Paperback App Store description](https://apps.apple.com/us/app/paperback-comic-manga-reader/id1626613373),
[Paperback's source models](https://github.com/Paperback-iOS/extensions-common).
