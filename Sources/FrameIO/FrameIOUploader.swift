import Foundation

/// Uploads a finished local recording to Frame.io using the V4 "local upload" flow:
///
/// 1. `POST .../folders/{id}/files/local_upload` with `name` + `file_size`.
/// 2. The response contains an ordered list of presigned S3 `upload_urls`.
/// 3. `PUT` each contiguous chunk of the file to its URL, in order.
///
/// Progress is reported as a fraction in `[0, 1]` on the main actor.
@MainActor
final class FrameIOUploader {
    enum UploadError: LocalizedError {
        case noUploadURLs
        case fileUnreadable(String)
        case chunkFailed(Int, Int)

        var errorDescription: String? {
            switch self {
            case .noUploadURLs: return "Frame.io did not return any upload URLs."
            case .fileUnreadable(let p): return "Could not read recording at \(p)."
            case .chunkFailed(let index, let code): return "Upload chunk \(index) failed (HTTP \(code))."
            }
        }
    }

    /// A single contiguous byte range to PUT, paired with its destination URL.
    struct Chunk: Equatable {
        let index: Int
        let offset: Int
        let length: Int
        let url: URL
    }

    private let client: FrameIOClient
    private let session: URLSession

    init(client: FrameIOClient, session: URLSession = .shared) {
        self.client = client
        self.session = session
    }

    /// Upload `fileURL` into `destination`. Returns the Frame.io view link if provided.
    @discardableResult
    func upload(
        fileURL: URL,
        destination: UploadDestination,
        progress: @escaping (Double) -> Void
    ) async throws -> String? {
        let fileSize = try Self.fileSize(of: fileURL)
        let name = fileURL.lastPathComponent

        // 1. Create the placeholder file and get presigned URLs.
        let created = try await createFile(
            accountID: destination.accountID,
            folderID: destination.folderID,
            name: name,
            fileSize: fileSize
        )
        guard let uploadURLs = created.data.upload_urls, !uploadURLs.isEmpty else {
            throw UploadError.noUploadURLs
        }

        // 2. Plan contiguous chunks across the URLs.
        let chunks = Self.planChunks(fileSize: fileSize, uploadURLs: uploadURLs)

        // 3. PUT each chunk, reporting cumulative progress.
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var uploaded = 0
        for chunk in chunks {
            try handle.seek(toOffset: UInt64(chunk.offset))
            let data = try handle.read(upToCount: chunk.length) ?? Data()
            try await put(data: data, to: chunk.url, contentType: "application/octet-stream", index: chunk.index)
            uploaded += data.count
            let fraction = fileSize == 0 ? 1 : Double(uploaded) / Double(fileSize)
            progress(min(fraction, 1.0))
        }

        progress(1.0)
        Log.frameio.info("Upload complete: \(name, privacy: .public)")
        return created.data.viewLink
    }

    // MARK: - Create file

    private func createFile(
        accountID: String,
        folderID: String,
        name: String,
        fileSize: Int
    ) async throws -> CreateFileResponse {
        let body = CreateFileRequest(data: .init(name: name, file_size: fileSize))
        let encoded = try JSONEncoder().encode(body)
        let path = "/accounts/\(accountID)/folders/\(folderID)/files/local_upload"
        let data = try await client.send(path: path, method: "POST", body: encoded)
        return try JSONDecoder().decode(CreateFileResponse.self, from: data)
    }

    // MARK: - Chunk PUT

    private func put(data: Data, to url: URL, contentType: String, index: Int) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // S3 presigned PUTs for Frame.io expect a private ACL header.
        request.setValue("private", forHTTPHeaderField: "x-amz-acl")

        let (_, response) = try await session.upload(for: request, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UploadError.chunkFailed(index, code)
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Split `fileSize` bytes evenly across the provided upload URLs, honoring each
    /// URL's `size` hint when present. The chunks tile the file with no gaps/overlaps.
    static func planChunks(fileSize: Int, uploadURLs: [CreateFileResponse.UploadURL]) -> [Chunk] {
        guard !uploadURLs.isEmpty else { return [] }

        // If every URL carries an explicit size, honor those exactly.
        let sizes: [Int]
        if uploadURLs.allSatisfy({ ($0.size ?? 0) > 0 }) {
            sizes = uploadURLs.map { $0.size ?? 0 }
        } else {
            // Otherwise divide as evenly as possible, giving the remainder to the last.
            let count = uploadURLs.count
            let base = fileSize / count
            var computed = Array(repeating: base, count: count)
            computed[count - 1] += fileSize - base * count
            sizes = computed
        }

        var chunks: [Chunk] = []
        var offset = 0
        for (index, urlInfo) in uploadURLs.enumerated() {
            guard let url = URL(string: urlInfo.url) else { continue }
            let length = sizes[index]
            chunks.append(Chunk(index: index, offset: offset, length: length, url: url))
            offset += length
        }
        return chunks
    }

    static func fileSize(of url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw UploadError.fileUnreadable(url.path)
        }
        return size
    }
}
