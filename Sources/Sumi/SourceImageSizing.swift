import Foundation

enum SourceImageSizing {
    /// ImageIO limits the longest edge. A fixed edge limit destroys the width of
    /// tall webtoon strips, so derive it from their width and decoded pixel cost.
    static func maximumPixelSize(width: Double, height: Double, cover: Bool) -> Int? {
        guard width.isFinite, height.isFinite, width > 0, height > 0,
              width <= 1_000_000, height <= 1_000_000 else { return nil }
        let scale = min(1, (cover ? 720 : 4096) / width,
                        sqrt((cover ? 1_000_000 : 32_000_000) / (width * height)))
        return max(1, Int((max(width, height) * scale).rounded(.down)))
    }
}
