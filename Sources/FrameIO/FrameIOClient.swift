import Foundation

/// Thin client over the Frame.io V4 REST API. Handles bearer-auth header injection
/// (via `FrameIOAuth`) and JSON decoding of the resource hierarchy Spool needs to
/// resolve an upload destination: Account → Workspace → Project → Folder.
@MainActor
final class FrameIOClient {
    enum ClientError: LocalizedError {
        case http(Int, String)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .http(let code, let body): return "Frame.io API error \(code): \(body)"
            case .decoding(let detail): return "Could not read Frame.io response: \(detail)"
            }
        }
    }

    private let auth: FrameIOAuth
    private let session: URLSession

    init(auth: FrameIOAuth, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    // MARK: - Resource fetches

    func listAccounts() async throws -> [FrameIOAccount] {
        try await getList("/accounts")
    }

    func listWorkspaces(accountID: String) async throws -> [FrameIOWorkspace] {
        try await getList("/accounts/\(accountID)/workspaces")
    }

    func listProjects(accountID: String, workspaceID: String) async throws -> [FrameIOProject] {
        try await getList("/accounts/\(accountID)/workspaces/\(workspaceID)/projects")
    }

    func listFolderChildren(accountID: String, folderID: String) async throws -> [FrameIOFolder] {
        try await getList("/accounts/\(accountID)/folders/\(folderID)/children")
    }

    // MARK: - Generic request helpers

    private func getList<T: Decodable>(_ path: String) async throws -> [T] {
        let data = try await send(path: path, method: "GET", body: nil)
        do {
            return try JSONDecoder().decode(FrameIOList<T>.self, from: data).data
        } catch {
            throw ClientError.decoding(String(describing: error))
        }
    }

    /// Perform an authenticated request and return the raw body, retrying once after a
    /// token refresh if the server reports 401.
    func send(path: String, method: String, body: Data?, contentType: String = "application/json") async throws -> Data {
        func makeRequest(token: String) -> URLRequest {
            let url = FrameIOConfig.apiBaseURL.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let body = body {
                request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                request.httpBody = body
            }
            return request
        }

        var token = try await auth.validAccessToken()
        var (data, response) = try await session.data(for: makeRequest(token: token))
        var http = response as? HTTPURLResponse

        if http?.statusCode == 401 {
            // Force a refresh and retry once.
            token = try await auth.validAccessToken()
            (data, response) = try await session.data(for: makeRequest(token: token))
            http = response as? HTTPURLResponse
        }

        guard let status = http?.statusCode else {
            throw ClientError.http(-1, "No HTTP response")
        }
        guard (200..<300).contains(status) else {
            throw ClientError.http(status, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
