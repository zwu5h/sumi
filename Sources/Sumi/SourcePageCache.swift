import SwiftUI
import ImageIO

/// A reader-scoped buffer shared by visible pages and speculative downloads.
@MainActor
final class SourcePageCache: ObservableObject {
    private let images = NSCache<NSURL, UIImage>()
    private var requests: [URL: (id: UUID, task: Task<UIImage, Error>)] = [:]

    init() {
        images.countLimit = 8
        images.totalCostLimit = 64 * 1024 * 1024
    }

    func cachedImage(_ url: URL) -> UIImage? { images.object(forKey: url as NSURL) }

    func prefetch(_ pages: [URL], around page: Int, source: InstalledSource) {
        guard pages.indices.contains(page) else { return }
        let window = Set(pages[max(0, page - 1)...min(pages.count - 1, page + 3)])
        for url in Array(requests.keys) where !window.contains(url) {
            requests.removeValue(forKey: url)?.task.cancel()
        }
        // Start the visible page first, then the next three and the previous page.
        let order = [page] + Array((page + 1)..<min(pages.count, page + 4)) + (page > 0 ? [page - 1] : [])
        for index in order where cachedImage(pages[index]) == nil {
            _ = request(pages[index], source: source)
        }
    }

    func image(_ url: URL, source: InstalledSource) async throws -> UIImage {
        if let image = cachedImage(url) { return image }
        return try await request(url, source: source).value
    }

    func reset() {
        for request in requests.values { request.task.cancel() }
        requests.removeAll()
        images.removeAllObjects()
    }

    private func request(_ url: URL, source: InstalledSource) -> Task<UIImage, Error> {
        if let request = requests[url] { return request.task }
        let id = UUID()
        let task = Task { @MainActor in
            defer { if requests[url]?.id == id { requests.removeValue(forKey: url) } }
            let image = try await SourceImageDecoder.load(url, source: source, cover: false)
            try Task.checkCancellation()
            if let bitmap = image.cgImage {
                images.setObject(image, forKey: url as NSURL, cost: bitmap.bytesPerRow * bitmap.height)
            }
            return image
        }
        requests[url] = (id, task)
        return task
    }

    deinit { for request in requests.values { request.task.cancel() } }
}

enum SourceImageDecoder {
    static func load(_ url: URL, source: InstalledSource, cover: Bool) async throws -> UIImage {
        let data = try await SourceNetwork.get(url, hosts: source.manifest.hosts, limit: 20_000_000,
                                               imageReferer: source.manifest.imageReferer)
        try Task.checkCancellation()
        let decoded = await Task.detached(priority: .userInitiated) {
            guard let input = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  let maximum = SourceImageSizing.maximumPixelSize(width: width.doubleValue, height: height.doubleValue, cover: cover),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(input, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximum,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { return UIImage?.none }
            return UIImage(cgImage: thumbnail)
        }.value
        try Task.checkCancellation()
        guard let decoded else { throw SourceError.invalid("The source returned an unreadable image.") }
        return decoded
    }
}
