import XCTest
@testable import Spool

final class ChunkPlanTests: XCTestCase {
    private func url(_ s: String, size: Int? = nil) -> CreateFileResponse.UploadURL {
        CreateFileResponse.UploadURL(url: s, size: size)
    }

    func testEvenDivisionTilesWholeFileWithoutGaps() {
        let urls = [url("https://s3/1"), url("https://s3/2"), url("https://s3/3")]
        let chunks = FrameIOUploader.planChunks(fileSize: 1000, uploadURLs: urls)

        XCTAssertEqual(chunks.count, 3)
        // Contiguous: each offset equals the previous offset+length.
        XCTAssertEqual(chunks[0].offset, 0)
        XCTAssertEqual(chunks[1].offset, chunks[0].length)
        XCTAssertEqual(chunks[2].offset, chunks[0].length + chunks[1].length)
        // Covers the whole file exactly.
        let total = chunks.reduce(0) { $0 + $1.length }
        XCTAssertEqual(total, 1000)
        // Remainder lands on the last chunk.
        XCTAssertEqual(chunks.last?.length, 1000 - 333 * 2)
    }

    func testHonorsExplicitPerURLSizes() {
        let urls = [url("https://s3/1", size: 600), url("https://s3/2", size: 400)]
        let chunks = FrameIOUploader.planChunks(fileSize: 1000, uploadURLs: urls)

        XCTAssertEqual(chunks.map(\.length), [600, 400])
        XCTAssertEqual(chunks.map(\.offset), [0, 600])
    }

    func testSingleURLGetsEntireFile() {
        let chunks = FrameIOUploader.planChunks(fileSize: 777, uploadURLs: [url("https://s3/1")])
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].offset, 0)
        XCTAssertEqual(chunks[0].length, 777)
    }

    func testEmptyURLListProducesNoChunks() {
        XCTAssertTrue(FrameIOUploader.planChunks(fileSize: 100, uploadURLs: []).isEmpty)
    }
}
