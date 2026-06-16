import Foundation

// MARK: - OAuth token set

/// The token set returned by Adobe IMS, plus a computed absolute expiry so we know
/// when to refresh. Persisted to the Keychain as JSON.
struct OAuthTokenSet: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    /// Treat tokens as expired slightly early to avoid races on long uploads.
    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }

    init(accessToken: String, refreshToken: String?, expiresIn: TimeInterval) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = Date().addingTimeInterval(expiresIn)
    }
}

/// Raw IMS token endpoint response.
struct IMSTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double? // IMS returns ms in some flows; normalized in FrameIOAuth.
}

// MARK: - V4 resource DTOs
//
// The V4 API nests data under a top-level `data` key and paginates via `links`/
// `total`. These DTOs capture only the fields Spool needs (id + display name).

struct FrameIOList<T: Decodable>: Decodable {
    let data: [T]
}

struct FrameIOItem<T: Decodable>: Decodable {
    let data: T
}

struct FrameIOAccount: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    let display_name: String?

    var title: String { display_name ?? name ?? id }
}

struct FrameIOWorkspace: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?

    var title: String { name ?? id }
}

struct FrameIOProject: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?
    /// The project's root folder; new files default here.
    let root_folder_id: String?

    var title: String { name ?? id }
}

struct FrameIOFolder: Decodable, Identifiable, Hashable {
    let id: String
    let name: String?

    var title: String { name ?? id }
}

// MARK: - Upload create (local upload)

/// Request body for "Create File (local upload)".
///
/// V4 accepts only `name` + `file_size` here — sending `media_type` triggers a
/// `422 "Unexpected field: media_type"`. The MIME type is applied on the chunk PUT
/// instead (see `FrameIOUploader`).
struct CreateFileRequest: Encodable {
    struct Data: Encodable {
        let name: String
        let file_size: Int
    }
    let data: Data
}

/// Response from creating a file via local upload. The placeholder file id plus the
/// presigned S3 URLs that the bytes are PUT to (in order).
struct CreateFileResponse: Decodable {
    struct FileData: Decodable {
        let id: String
        let name: String?
        let upload_urls: [UploadURL]?
        /// Web link to view the asset once finalized (field name varies; both tried).
        let view_url: String?
        let view: String?

        var viewLink: String? { view_url ?? view }
    }

    struct UploadURL: Decodable {
        let url: String
        let size: Int?
    }

    let data: FileData
}

// MARK: - Share (public Loom-style link)

/// Request body to create a public share for the uploaded file.
struct CreateShareRequest: Encodable {
    struct Data: Encodable {
        let name: String
        /// "public" makes the link openable by anyone, no Frame.io account needed.
        let access: String
        /// Files to include in the share.
        let file_ids: [String]
    }
    let data: Data
}

/// Response from creating a share. The public URL field name varies across the V4
/// surface, so several candidates are decoded and the first non-nil one is used.
struct CreateShareResponse: Decodable {
    struct ShareData: Decodable {
        let id: String?
        let short_url: String?
        let url: String?
        let view_url: String?

        var link: String? { short_url ?? url ?? view_url }
    }
    let data: ShareData
}

// MARK: - Destination selection (persisted in UserDefaults)

/// The user's chosen upload destination, resolved down to a concrete folder id.
struct UploadDestination: Codable, Equatable {
    var accountID: String
    var accountTitle: String
    // Optional for backward-compatibility with destinations saved before workspace
    // was tracked; lets the Settings pickers fully restore the prior selection.
    var workspaceID: String?
    var workspaceTitle: String?
    var projectID: String
    var projectTitle: String
    var folderID: String
    var folderTitle: String
}
