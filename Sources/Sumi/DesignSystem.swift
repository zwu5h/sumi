import SwiftUI

enum Design {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.84, blue: 1.0, alpha: 1)
            : UIColor(red: 0.0, green: 0.32, blue: 0.68, alpha: 1)
    })
    static let spacing: CGFloat = 24
    static let corner: CGFloat = 28
    static let coverCorner: CGFloat = 12
    static let readingWidth: CGFloat = 840
    static let contentWidth: CGFloat = 1080
    static func font(_ style: Font.TextStyle) -> Font {
        .system(style, design: .default, weight: style == .headline ? .semibold : .regular)
    }
    static let title = font(.largeTitle).weight(.bold)
    static let eyebrow = font(.caption2).weight(.semibold)
    static let section = font(.title2).weight(.semibold)
    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.055, green: 0.16, blue: 0.23) : Color(red: 0.88, green: 0.98, blue: 1)
    }
    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.025, green: 0.09, blue: 0.16) : Color(red: 0.73, green: 0.91, blue: 0.97)
    }
}

struct Motion {
    let reduced: Bool
    var standard: Animation? { reduced ? nil : .spring(response: 0.38, dampingFraction: 0.86) }
}

struct GlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat
    var interactive = false

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Design.background(scheme), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(.primary.opacity(0.3), lineWidth: 1))
        } else {
            #if LIQUID_GLASS
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular.interactive(interactive), in: RoundedRectangle(cornerRadius: radius))
                    .overlay(glassRim)
                    .shadow(color: Design.accent.opacity(0.12), radius: 16, y: 7)
            } else {
                fallback(content)
            }
            #else
            fallback(content)
            #endif
        }
    }

    private func fallback(_ content: Content) -> some View {
        content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius))
            .background(Design.surface(scheme).opacity(0.18), in: RoundedRectangle(cornerRadius: radius))
            .overlay(glassRim)
            .shadow(color: Design.accent.opacity(0.14), radius: 16, y: 7)
    }

    private var glassRim: some View {
        RoundedRectangle(cornerRadius: radius).strokeBorder(
            LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.45 : 0.95),
                                    .white.opacity(0.12), .cyan.opacity(0.25), .white.opacity(0.65)],
                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            .allowsHitTesting(false)
    }
}

extension View {
    func glassSurface(radius: CGFloat = Design.corner, interactive: Bool = false) -> some View {
        modifier(GlassSurface(radius: radius, interactive: interactive))
    }
    func pageBackground() -> some View { modifier(PageBackground()) }
}

private struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.hidden, for: .navigationBar)
            .background { AeroBackground().ignoresSafeArea() }
    }
}

/// Abstract, diffuse color only: manga illustrations belong inside their covers.
struct AeroBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        GeometryReader { proxy in
            let dark = scheme == .dark
            ZStack {
                Design.background(scheme)
                if !reduceTransparency && contrast != .increased {
                    RadialGradient(colors: [Color.cyan.opacity(dark ? 0.30 : 0.62), .clear],
                                   center: UnitPoint(x: 0.85, y: 0.06), startRadius: 0,
                                   endRadius: proxy.size.height * 0.78)
                    RadialGradient(colors: [Color(red: 0.33, green: 0.94, blue: 0.58).opacity(dark ? 0.20 : 0.55), .clear],
                                   center: UnitPoint(x: 0.03, y: 0.72), startRadius: 0,
                                   endRadius: proxy.size.height * 0.55)
                    RadialGradient(colors: [Color(red: 0.18, green: 0.60, blue: 1).opacity(dark ? 0.28 : 0.48), .clear],
                                   center: UnitPoint(x: 1, y: 0.95), startRadius: 0,
                                   endRadius: proxy.size.height * 0.60)
                    RadialGradient(colors: [.white.opacity(dark ? 0.06 : 0.75), .clear],
                                   center: UnitPoint(x: 0.34, y: 0.23), startRadius: 0,
                                   endRadius: proxy.size.height * 0.42)
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var body: some View {
        #if LIQUID_GLASS
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 16) { content() }
        } else { content() }
        #else
        content()
        #endif
    }
}

struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion(reduced: reduceMotion).standard, value: configuration.isPressed)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Design.section).tracking(-0.6).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(Design.font(.subheadline)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(Design.eyebrow).tracking(2)
            .foregroundStyle(Design.accent).fixedSize(horizontal: false, vertical: true)
    }
}

/// Glass belongs to the controls; editorial content rests directly on the canvas.
struct GlassSearch: View {
    @Binding var text: String
    var prompt = "Find a story"
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField(prompt, text: $text).focused($focused).submitLabel(.search)
                .autocorrectionDisabled().onSubmit { focused = false }
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44)
                }.accessibilityLabel("Clear search")
            }
        }.font(Design.font(.body)).padding(.leading, 18).padding(.trailing, text.isEmpty ? 18 : 2)
            .frame(minHeight: 52).glassSurface(radius: 28)
    }
}

struct SelectionRail: View {
    let items: [String]
    @Binding var selection: String
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Button {
                        withAnimation(Motion(reduced: reduced).standard) { selection = item }
                    } label: {
                        Text(item).font(Design.font(.subheadline).weight(selection == item ? .semibold : .regular))
                            .foregroundStyle(selection == item ? Design.accent : Color.primary)
                            .padding(.horizontal, 18).frame(minHeight: 44)
                            .background {
                                if selection == item {
                                    Capsule().fill(Design.accent.opacity(scheme == .dark ? 0.24 : 0.12))
                                        .overlay(Capsule().strokeBorder(.white.opacity(contrast == .increased ? 1 : 0.7), lineWidth: 1))
                                        .matchedGeometryEffect(id: "selection", in: indicator)
                                }
                            }.contentShape(Capsule())
                    }.buttonStyle(PressStyle()).accessibilityAddTraits(selection == item ? .isSelected : [])
                }
            }.padding(5)
        }.glassSurface(radius: 28)
    }
}

struct AppLogo: View {
    var size: CGFloat = 32
    var body: some View {
        Image("sumi-logo", bundle: .module).resizable().scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23))
            .accessibilityHidden(true)
    }
}

struct QuietPanel<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18, content: content).padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassSurface()
    }
}

struct CoverArt: View {
    let manga: Manga
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let remote = manga.remote {
                    SourceImage(url: remote.cover, sourceID: remote.sourceID, fill: true)
                } else if let url = manga.thumbnailURL, let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Design.accent.opacity(0.12))
                        .overlay { Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(Design.accent) }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.accessibilityHidden(true)
    }
}

struct SaveMangaButton: View {
    @EnvironmentObject private var library: LibraryStore
    let manga: Manga
    private var saved: Bool { library.savedIDs.contains(manga.id) }
    var body: some View {
        Button { library.toggleSaved(manga) } label: {
            Label(saved ? "Saved in library" : "Save to library", systemImage: saved ? "bookmark.fill" : "bookmark")
                .font(Design.font(.headline))
                .frame(maxWidth: .infinity, minHeight: 48)
        }.buttonStyle(.bordered)
            .accessibilityHint(saved ? "Removes this manga from your library" : "Adds this manga to your library")
    }
}

extension View {
    @ViewBuilder func coverTransitionSource(id: String, namespace: Namespace.ID, reducedMotion: Bool) -> some View {
        #if LIQUID_GLASS
        if #available(iOS 26.0, *), !reducedMotion {
            matchedTransitionSource(id: id, in: namespace)
        } else { self }
        #else
        self
        #endif
    }
    @ViewBuilder func coverNavigationTransition(id: String, namespace: Namespace.ID, reducedMotion: Bool) -> some View {
        #if LIQUID_GLASS
        if #available(iOS 26.0, *), !reducedMotion {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else { self }
        #else
        self
        #endif
    }
}

struct MangaTile: View {
    let manga: Manga
    let progress: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverArt(manga: manga).aspectRatio(0.67, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    if progress > 0 {
                        ProgressView(value: progress).tint(Design.accent).padding(8)
                            .accessibilityLabel("Reading progress")
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Design.coverCorner))
            VStack(alignment: .leading, spacing: 5) {
                Text(manga.title).font(Design.font(.subheadline).weight(.semibold)).foregroundStyle(.primary).lineLimit(2)
                Text(manga.author).font(Design.font(.caption)).foregroundStyle(.secondary).lineLimit(1)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
        }.glassSurface(radius: Design.coverCorner).accessibilityElement(children: .combine)
    }
}
