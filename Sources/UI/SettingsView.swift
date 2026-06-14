import SwiftUI

/// App settings: Adobe API client ID, Frame.io sign-in, and upload destination.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var clientID = FrameIOConfig.clientID

    var body: some View {
        Form {
            Section("Adobe / Frame.io API") {
                TextField("Adobe client ID", text: $clientID, prompt: Text("Client (API) ID from the Adobe Developer Console"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: clientID) { _, newValue in
                        FrameIOConfig.clientID = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                Text("Create a project in the Adobe Developer Console, add the Frame.io API, and register the redirect URI `spool://oauth-callback`. Paste the generated Client ID here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Connection") {
                if state.isSignedIn {
                    HStack {
                        Label("Connected to Frame.io", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Sign Out") { state.signOut() }
                    }
                } else {
                    Button {
                        Task { await state.signIn() }
                    } label: {
                        Label("Sign in with Adobe", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(!FrameIOConfig.isConfigured)
                }
            }

            if state.isSignedIn {
                Section("Upload destination") {
                    DestinationPickerView()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Lets the user drill Account → Workspace → Project and stores the resolved
/// destination (project root folder) on `AppState`.
private struct DestinationPickerView: View {
    @EnvironmentObject private var state: AppState

    @State private var accounts: [FrameIOAccount] = []
    @State private var workspaces: [FrameIOWorkspace] = []
    @State private var projects: [FrameIOProject] = []

    @State private var accountID: String?
    @State private var workspaceID: String?
    @State private var projectID: String?

    @State private var loadError: String?

    var body: some View {
        Group {
            if let destination = state.destination {
                Label("Uploading to \(destination.projectTitle)", systemImage: "folder.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Picker("Account", selection: $accountID) {
                Text("Select…").tag(String?.none)
                ForEach(accounts) { Text($0.title).tag(Optional($0.id)) }
            }
            .onChange(of: accountID) { _, id in Task { await loadWorkspaces(accountID: id) } }

            Picker("Workspace", selection: $workspaceID) {
                Text("Select…").tag(String?.none)
                ForEach(workspaces) { Text($0.title).tag(Optional($0.id)) }
            }
            .onChange(of: workspaceID) { _, id in Task { await loadProjects(workspaceID: id) } }
            .disabled(workspaces.isEmpty)

            Picker("Project", selection: $projectID) {
                Text("Select…").tag(String?.none)
                ForEach(projects) { Text($0.title).tag(Optional($0.id)) }
            }
            .onChange(of: projectID) { _, id in selectProject(id) }
            .disabled(projects.isEmpty)

            if let loadError = loadError {
                Text(loadError).font(.caption).foregroundStyle(.orange)
            }
        }
        .task { await loadAccounts() }
    }

    private func loadAccounts() async {
        do { accounts = try await state.client.listAccounts() }
        catch { loadError = error.localizedDescription }
    }

    private func loadWorkspaces(accountID: String?) async {
        workspaces = []; projects = []; workspaceID = nil; projectID = nil
        guard let accountID = accountID else { return }
        do { workspaces = try await state.client.listWorkspaces(accountID: accountID) }
        catch { loadError = error.localizedDescription }
    }

    private func loadProjects(workspaceID: String?) async {
        projects = []; projectID = nil
        guard let accountID = accountID, let workspaceID = workspaceID else { return }
        do { projects = try await state.client.listProjects(accountID: accountID, workspaceID: workspaceID) }
        catch { loadError = error.localizedDescription }
    }

    private func selectProject(_ id: String?) {
        guard
            let accountID = accountID,
            let account = accounts.first(where: { $0.id == accountID }),
            let project = projects.first(where: { $0.id == id }),
            let folderID = project.root_folder_id
        else { return }

        state.destination = UploadDestination(
            accountID: accountID,
            accountTitle: account.title,
            projectID: project.id,
            projectTitle: project.title,
            folderID: folderID,
            folderTitle: "\(project.title) (root)"
        )
    }
}
