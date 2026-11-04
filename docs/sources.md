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

Swipe an installed source to remove it. Removing a repository also removes its installed
extensions. Saved titles and progress remain, with an explicit reinstall error when the
source is unavailable. Refreshing an index never updates executable code silently:
select the new version and review its installation again. A different repository cannot
replace an already installed source with the same ID.
Installation checks script syntax and the three required method definitions in WebKit
before committing the extension; a failed update keeps the previously installed version.

Online pages require a connection. PDFs remain the supported offline format. Source
authentication, automatic update polling, pagination and Paperback SDK compatibility
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

URLs must be absolute HTTPS URLs. `hosts` lists exact lowercase domains; wildcards,
literal IPs, credentials in URLs, nonstandard ports and common local host suffixes are
rejected. API requests and images, including redirects, must stay on this list. Index
and script downloads can use their own host, and redirects must stay on that download
host. A checksum detects a mismatched download; it is **not** an author signature or
proof that a repository is trustworthy.

## Source API v1

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

Limits: 100 extensions per index, 200 titles per search, 10,000 chapters per title,
500 pages per chapter, 30 network requests per invocation, 4 simultaneous requests,
4 MB text responses and 20 MB image downloads. Scripts have a 1 MB download limit;
indexes have a 500 KB limit. An invocation has a 35-second deadline. Images are
downsampled before display, and the reader loads only the current and adjacent pages.

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
