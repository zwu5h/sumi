import Foundation

@main
struct ReadingPositionChecks {
    static func main() throws {
        let date = Date(timeIntervalSince1970: 1234)
        let saved = ReadingPosition(chapter: 3, page: 2, pageCount: 4, updatedAt: date)
        let decoded = try JSONDecoder().decode(ReadingPosition.self, from: JSONEncoder().encode(saved))
        precondition(decoded.chapter == 3 && decoded.page == 2 && decoded.pageCount == 4)
        precondition(decoded.updatedAt == date)
        precondition(!decoded.isComplete(chapterCount: 6))
        precondition(!ReadingPosition(chapter: 6, page: 2, pageCount: 4).isComplete(chapterCount: 6))
        precondition(!ReadingPosition(chapter: 5, page: 3, pageCount: 4).isComplete(chapterCount: 6))
        precondition(ReadingPosition(chapter: 6, page: 3, pageCount: 4).isComplete(chapterCount: 6))
        precondition(ReadingPosition(page: 0, pageCount: 1).isComplete(chapterCount: 1))
        // Completion uses page indices, avoiding floating-point rounding for very large books.
        precondition(!ReadingPosition(page: Int.max - 2, pageCount: Int.max).isComplete(chapterCount: 1))
        precondition(ReadingPosition(chapter: Int.max, page: Int.max, pageCount: 4).isComplete(chapterCount: 6))
        precondition(abs(decoded.progress(chapterCount: 6) - 2.75 / 6) < 0.000001)

        // A replaced document may have fewer pages than the saved copy.
        let shorter = saved.normalized(chapterCount: 6, actualPageCount: 2)
        precondition(shorter.page == 1 && shorter.pageCount == 2)
        precondition(shorter.updatedAt == date)

        // Persisted values cannot create invalid ranges or overflow progress math.
        for chapter in [Int.min, -1, 0, 1, 6, Int.max] {
            for page in [Int.min, -1, 0, 3, Int.max] {
                for count in [Int.min, 0, 1, 4, Int.max] {
                    for chapters in [0, 1, 6] {
                        let position = ReadingPosition(chapter: chapter, page: page, pageCount: count)
                        let normalized = position.normalized(chapterCount: chapters)
                        precondition((1...max(1, chapters)).contains(normalized.chapter))
                        precondition((0..<normalized.pageCount).contains(normalized.page))
                        let progress = position.progress(chapterCount: chapters)
                        precondition(progress.isFinite && (0...1).contains(progress))
                    }
                }
            }
        }
        precondition(ReadingPosition(chapter: 6, page: 3, pageCount: 4).progress(chapterCount: 6) == 1)
        precondition(ReadingPosition(page: 0, pageCount: 1).progress(chapterCount: 1) == 1)
        print("PASS: saved-position round trip, document resizing, completion, progress and invalid-value boundaries")
    }
}
