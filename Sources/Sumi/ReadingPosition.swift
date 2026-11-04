import Foundation

struct ReadingPosition: Codable {
    var chapter: Int = 1
    var page: Int = 0
    var pageCount: Int = 4
    var updatedAt = Date()

    var chapterProgress: Double {
        let value = normalized(chapterCount: max(1, chapter))
        return (Double(value.page) + 1) / Double(value.pageCount)
    }

    func isComplete(chapterCount: Int) -> Bool {
        let position = normalized(chapterCount: chapterCount)
        return position.chapter == max(1, chapterCount) && position.page == position.pageCount - 1
    }

    func normalized(chapterCount: Int, actualPageCount: Int? = nil) -> ReadingPosition {
        let count = max(1, actualPageCount ?? pageCount)
        return ReadingPosition(
            chapter: min(max(1, chapter), max(1, chapterCount)),
            page: min(max(0, page), count - 1),
            pageCount: count,
            updatedAt: updatedAt
        )
    }

    func progress(chapterCount: Int) -> Double {
        let position = normalized(chapterCount: chapterCount)
        let fraction = (Double(position.page) + 1) / Double(position.pageCount)
        return (Double(position.chapter - 1) + fraction) / Double(max(1, chapterCount))
    }
}
