import SwiftUI

struct CaptureUploadSettingsView: View {
    @Environment(CaptureCoordinator.self) private var coordinator
    @State private var editing = false
    @State private var destination = CaptureUploadDestination()
    @State private var credential = CaptureUploadCredential()
    @State private var notice: String?

    var body: some View {
        Section {
            if editing {
                Group {
                    Picker("Destination", selection: $destination.kind) {
                        ForEach(CaptureUploadDestination.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .onChange(of: destination.kind) { credential = CaptureUploadCredential() }
                    TextField("Name", text: $destination.name)
                    if destination.kind == .s3 {
                        TextField("Endpoint", text: $destination.endpoint, prompt: Text("https://…"))
                        TextField("Bucket", text: $destination.bucket)
                        TextField("Region", text: $destination.region, prompt: Text("auto"))
                        TextField("Folder prefix", text: $destination.prefix)
                        TextField("Access key ID", text: $destination.accessKey)
                        SecureField("Secret access key", text: $credential.secret)
                        SecureField("Session token (optional)", text: $credential.sessionToken)
                        TextField("Public URL base (optional)", text: $destination.publicBase, prompt: Text("https://…"))
                    } else if destination.kind == .imgbb {
                        SecureField("API key", text: $credential.secret)
                    } else {
                        TextField("Desktop OAuth client ID", text: $destination.clientID)
                        SecureField("Client secret (optional)", text: $credential.clientSecret)
                    }
                }.disabled(coordinator.uploadConnecting)
                HStack {
                    Button("Cancel") { coordinator.uploadAuthorization?.cancel(); finish() }
                    if destination.kind == .drive {
                        Button(coordinator.uploadConnecting ? "Waiting for Google…" : "Connect Google Drive…") {
                            coordinator.connectUpload(destination, clientSecret: credential.clientSecret)
                        }.disabled(coordinator.uploadConnecting || (try? destination.validated()) == nil)
                    } else { Button("Save Destination") {
                        do { try coordinator.settings.saveUpload(destination, credential: credential); finish() } catch {
                            notice = error.localizedDescription
                        }
                    }.disabled(credential.secret.isEmpty) }
                }
            } else if let saved = coordinator.settings.uploadDestination {
                LabeledContent("Destination", value: saved.title)
                Button("Edit Destination…") {
                    do {
                        credential = try coordinator.settings.uploadCredential(for: saved)
                        destination = saved; editing = true; notice = nil
                    } catch { notice = error.localizedDescription }
                }
                Button("Remove Destination") {
                    do { try coordinator.settings.removeUpload(); finish() } catch { notice = error.localizedDescription }
                }
            } else {
                Button("Add Upload Destination…") { destination = CaptureUploadDestination(); editing = true; notice = nil }
            }
            if let notice = notice ?? coordinator.uploadNotice { Text(notice).foregroundStyle(Theme.Colors.textSecondary) }
        } header: {
            SettingsSectionHeader(.captureUploads)
        } footer: {
            Text(footer)
        }
        .onChange(of: coordinator.uploadConnecting) { _, connecting in
            if !connecting, coordinator.uploadNotice == nil,
                coordinator.settings.uploadDestination?.id == destination.id { finish() }
        }
        .onDisappear { coordinator.uploadAuthorization?.cancel(); finish() }
    }

    private var footer: String {
        switch editing ? destination.kind : coordinator.settings.uploadDestination?.kind {
        case .drive:
            "Connect using this fork’s Desktop OAuth client. New files stay private in My Drive; sharing is unchanged. "
                + "The app requests access only to files you create or open with it. Tokens stay in this Mac’s Keychain."
        case .imgbb:
            "imgbb uploads are public. Only the final image is uploaded when you choose Upload and Copy Link."
        default:
            "Uploads are manual and use the final image or video. Bucket permissions are unchanged. "
                + "A copied object URL may require access. Credentials stay in this Mac’s Keychain."
        }
    }

    private func finish() { credential = CaptureUploadCredential(); editing = false; notice = nil }
}
