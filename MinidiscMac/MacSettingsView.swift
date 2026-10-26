import SwiftUI

/// The Settings window. For now it only connects to a server, through the shared onboarding view
/// model and ServerService, which keeps the password in the keychain.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            Tab("Server", systemImage: "server.rack") {
                MacServerSettings()
            }
        }
        .frame(width: 480)
    }
}

private struct MacServerSettings: View {
    @Environment(\.appContainer) private var container
    @State private var viewModel: OnboardingViewModel?

    var body: some View {
        Form {
            if let container, !container.serverState.servers.isEmpty {
                Section {
                    Picker("Server", selection: activeServerBinding(container)) {
                        ForEach(container.serverState.servers, id: \.id) { server in
                            Text(server.displayName).tag(Optional(server.id))
                        }
                    }
                    if let server = container.serverState.activeServer {
                        LabeledContent("Connected as", value: server.username)
                        LabeledContent("Server URL", value: server.baseURL)
                        Button("Remove", role: .destructive) {
                            Task { try? await container.serverService.removeServer(id: server.id) }
                        }
                    }
                }
            }

            if let viewModel {
                Section("Add Server") {
                    @Bindable var viewModel = viewModel
                    TextField("Server URL", text: $viewModel.serverURL, prompt: Text(verbatim: "https://music.example.com"))
                    TextField("Username", text: $viewModel.username)
                        .textContentType(.username)
                    SecureField("Password", text: $viewModel.password)
                        .textContentType(.password)
                    if let error = viewModel.connectionError {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Connect & Save") {
                            Task { await connect(viewModel) }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canSubmit || viewModel.isLoading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            guard viewModel == nil, let container else { return }
            viewModel = OnboardingViewModel(serverService: container.serverService)
        }
    }

    private func connect(_ viewModel: OnboardingViewModel) async {
        await viewModel.addServer()
        guard viewModel.connectionError == nil else { return }
        viewModel.serverURL = ""
        viewModel.username = ""
        viewModel.password = ""
    }

    private func activeServerBinding(_ container: AppContainer) -> Binding<UUID?> {
        Binding {
            container.serverState.activeServer?.id
        } set: { id in
            guard let id else { return }
            Task { try? await container.serverService.setActiveServer(id: id) }
        }
    }
}
