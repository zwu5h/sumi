# Sumi — a native manga reading room

A new SwiftUI app, built in the originally empty `C:\Dev\manga-reader` workspace. Requires iOS 17 or later. There are no third-party runtime dependencies.

## Build with xtool

On this Windows machine, Swift and xtool are installed inside WSL Ubuntu:

```powershell
wsl bash -lc 'cd /mnt/c/Dev/manga-reader && xtool dev build'
```

For an optimized, unsigned IPA:

```sh
xtool dev build --configuration release --ipa
python3 scripts/verify_build.py --expect-glass native --ipa
```

The output is in `xtool/`. Device installation requires signing and a connected iPhone; `xtool dev run` handles that with your configured developer account. The build itself does not install anything or change developer credentials.

The installed Swift 6.4.1 toolchain and iOS 27.1 SDK expose `glassEffect` and `GlassEffectContainer`. `Package.swift` checks the SDK's public SwiftUI interface before defining `LIQUID_GLASS`. At runtime, iOS 26+ uses those APIs; earlier versions use `.regularMaterial`. With an older SDK, the names are excluded from compilation entirely. A custom SDK location can be supplied through `SUMI_SDK_ROOT` (or `SDKROOT`).

To compile and validate only the material path:

```sh
SUMI_DISABLE_LIQUID_GLASS=1 xtool dev build
SUMI_DISABLE_LIQUID_GLASS=1 python3 scripts/verify_build.py --expect-glass fallback
```

## Experience

The November 4 redesign follows the accepted [Frutiger Aero reference](design/reference.png): abstract, softly blended sky-blue, aqua and mint backgrounds, blue accents, Avenir Next typography and luminous translucent glass. No scenic wallpaper is used. `DesignSystem.swift` draws the background with adaptive radial gradients and centralizes typography, materials, accessibility fallbacks and spacing. See [design notes](design/README.md). New installations default to light appearance; saved preferences remain respected.

Library and Discover have glass search fields inside their scroll content, so pulling down moves the search field with the collection. The library uses animated filter rails, a large reading cover and an adaptive cover grid. Discover lists installed sources and opens their catalogs. Details use full-width artwork, a faint artwork-derived backdrop, a title that moves into the navigation bar as the header leaves the viewport, and a floating reading action. Screens use concise functional headings; theme choices include visual previews. Reader controls are separate glass islands at the top and a width-limited page scrubber below. Controls stay visible while scrubbing, and chapter changes crossfade when Reduce Motion is off.

The generated Sumi logo uses glass manga pages forming an S against a medium aqua/mint background. It appears in Settings and as the launcher icon. The master asset is `Sources/Sumi/Resources/sumi-logo.png`; launcher sizes live in `design/AppIcons`. The built-in Imagegen edit prompt is saved in `design/sumi-logo-prompt.txt`.

Artwork headers grow with their text rather than clipping large Dynamic Type content. The theme selector becomes one column at accessibility sizes. Native `TabView` continues to own navigation, safe areas, selection and accessibility, using system Liquid Glass on supported systems.

- Library: cinematic featured artwork, adaptive artwork grid, native search, All/Reading/Unread/Completed filters, title sorting, PDF import, reading progress.
- Discover: installed sources, source-name search and repository management; manga details have a visible Save to library button.
- Details: artwork-derived backdrop, collapsing cover, metadata, chapter list, library bookmark, floating reading action.
- Reader: paged reading or continuous vertical scrolling (switch in the reader or Settings → Reading), right-to-left option for paged mode, PDFKit pinch zoom for imported PDFs, chapter chooser, page slider, saved position, four-second auto-hide controls, optional screen-awake mode.
- Updates: saved online titles; opening a title refreshes its chapter list.
- Downloads: locally imported PDFs, offline reading, confirmed deletion.
- Settings: light default, dark/system appearance, reader preferences, accessibility information.

The five-tab navigation uses the system `TabView`, including the system floating Liquid Glass presentation on supported iOS versions. Older systems retain their accessible native tab bar.

Search, filter rails, featured-card metadata, shelf cards and settings panels use glass with luminous borders. Native tabs retain platform behavior. Manga illustrations stay inside their artwork cards, and reader pages have no blur. Text uses system semantic styles, and layouts scroll at large text sizes. Reduce Transparency and increased contrast replace custom glass with solid surfaces and simplify the background; Reduce Motion disables custom spring and cover zoom animations. VoiceOver keeps reader controls visible. Tap targets are at least 44 points for reader controls.

Library's import picker accepts multiple PDFs. A batch shows file-count progress and the current filename, keeps successful documents when another fails, and reports failures by filename. Incomplete copies are cleaned up. Batch orchestration, persistence, cleanup, cancellation and overlapping requests are checked with `python3 scripts/test_library_import.py` using platform test doubles; PDFKit rendering still requires an iOS runtime.

The import progress panel includes Cancel. Cancellation keeps completed imports, cleans up the current unfinished copy and thumbnail, and skips the remaining files. If a file copy is already running, it finishes before cleanup; another batch can start after the panel disappears.

Reader controls overlay the page, so showing or hiding them leaves the reading area unchanged. Saved chapter and page indices are clamped to valid ranges, including when a document has fewer pages than its saved position. Reading position is also saved when the reader closes.

Reaching the last page of the last chapter marks a title as completed. Completed titles have their own library filter and a “Read again” action that starts at chapter one, page one. Opening a chapter directly still resumes its saved page.

The detail screen’s reading actions menu can mark a story as unread after confirmation. This clears its saved position while keeping library membership and any imported PDF. The Library’s featured story prioritizes the most recently read unfinished title still in your collection.

## Online sources

Settings → Sources & repositories and Discover → Browse your sources support adding
Sumi-format HTTPS repositories, reviewing and installing JavaScript extensions, searching
their catalogs and reading chapter images directly. Sources use declared host permissions,
explicit installation/update consent and SHA-256 download checks. Bookmarked online titles
and reading positions persist locally; the reader supports chapter selection, RTL, zoom,
page seeking and retries. Online pages are not downloaded for offline use.

See [source setup and API documentation](docs/sources.md) for the repository format,
static demo builder, verification steps and remaining App Review requirements. This uses
Sumi Source API v1; Paperback extensions cannot be installed unchanged.

## Architecture

| File | Responsibility |
| --- | --- |
| `SumiApp.swift` | App entry, appearance, native tabs |
| `DesignSystem.swift` | Color/spacing tokens, glass fallback, motion, artwork and reusable components |
| `LibraryStore.swift` | Models, local persistence, PDF import and deletion |
| `ReadingPosition.swift` | Saved reading position validation and progress calculations |
| `LibraryView.swift` | Collection, search, filtering and import |
| `MangaDetailView.swift` | Artwork header, metadata, chapters and reading launch |
| `ReaderView.swift` | Reader state, controls and PDFKit |
| `CollectionScreens.swift` | Discover, Updates, Downloads and Settings |
| `SourceModels.swift` | Repository format, source data and URL permissions |
| `SourceStore.swift` | Installation, integrity checks, persistence and source operations |
| `SourceRuntime.swift` | Isolated WebKit extension execution and bounded request bridge |
| `SourceNetwork.swift` | HTTPS requests, redirect permissions and response limits |
| `SourceViews.swift` | Repository manager, source catalog and remote image loading |
| `SourceReaderView.swift` | Online title details, chapter reading and saved position |

Imported PDFs and generated thumbnails live in the app Documents directory. Library membership, preferences and reading positions are persisted in UserDefaults. PDF imports validate that a document is readable, unlocked, and contains pages. Files never leave the device.

## Content scope and verification limits

The app starts with an empty library and contains no demo titles, covers or preview pages. Upgrading removes old bundled-demo bookmarks and reading positions while retaining imported PDFs and online manga. Import an unlocked PDF or install a source to read online. The original demo artwork lives only in `examples/sumi-originals/artwork` for development source fixtures. No third-party source or content catalog is bundled. Automatic release feeds, online offline-downloads and CBZ/CBR import are not implemented.

Build checks verify the arm64 executable, deployment target, bundle metadata, artwork resources and IPA packaging. This Linux/Windows host cannot run Apple's iOS Simulator, and no iPhone was connected during verification. On-device visual and interaction QA remains necessary before release.

The reading-position checks run on the host Swift toolchain without an iOS runtime:

```powershell
wsl bash -lc 'cd /mnt/c/Dev/manga-reader && python3 scripts/test_reading_position.py'
```

They cover persistence round trips, shorter documents, completed books, single-page documents, and invalid or extreme stored values.

Suggested device checks: import a multipage PDF, pinch to zoom, tap to reveal controls, swipe both reading directions, resume after relaunch, switch chapters, toggle all three themes, use accessibility text sizes, enable Reduce Motion/Transparency and VoiceOver, then delete a local document. Check iPhone portrait/landscape and iPad layouts. Signing and App Store assets are separate release steps.
