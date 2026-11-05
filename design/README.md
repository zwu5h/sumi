# Sumi design reference

The accepted visual reference is [reference.png](reference.png), copied from
`sumi-frutiger-aero-blurred-v2.png` on November 4, 2026.

Use soft, abstract Frutiger Aero color fields: sky blue, aqua, cyan, mint and fresh
green with diffuse white highlights. The page background contains no recognizable
landscape or wallpaper image. Illustrations remain inside manga covers.

Controls and cards use translucent glass, thin luminous rims and restrained blue
shadows. Selected controls use blue; there are no terracotta accents. Light is the
default for a new installation; existing appearance preferences remain respected.
Dark appearance uses the same colors at lower luminance. Reduce Transparency and
increased contrast retain opaque accessible surfaces.

The reference is a design artifact, not a bitmap displayed behind app controls.
The app draws its adaptive background and interactive controls using SwiftUI.
The app bundles no demo titles or artwork; covers come from imported PDFs or sources.

The image-generation prompts are saved alongside the reference for reproducibility.

UI typography uses the iOS system font, San Francisco, with semantic Dynamic Type
scaling. Decorative slogans and duplicate screen headings have been removed.
Library and Discover search fields belong to the scroll content, including bounce.

The app logo is generated with built-in Imagegen: glass manga pages forming an S,
on a medium aqua/mint background. The dark-blue and near-white drafts were rejected.
The final prompt is in `sumi-logo-prompt.txt`, the 1024px master in
`../Sources/Sumi/Resources/sumi-logo.png`, and launcher sizes in `AppIcons/`.
