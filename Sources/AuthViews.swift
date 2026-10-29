import SwiftUI

// MARK: - Sign in, create account, forgot password

struct AuthView: View {
    @EnvironmentObject private var account: AccountManager
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case create = "Create account"
        case forgot = "Forgot password"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var invite = ""
    @State private var resetCode = ""
    @State private var recoveryKey = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showServer = false

    var body: some View {
        NavigationStack {
            Group {
                if let key = account.pendingRecoveryKey {
                    RecoveryKeyView(key: key) {
                        account.pendingRecoveryKey = nil
                        dismiss()
                    }
                } else if account.pendingReset != nil {
                    resetRetry
                } else {
                    form
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .toolbar {
                if account.pendingRecoveryKey == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not now") {
                            account.cancelReset()
                            dismiss()
                        }
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(account.pendingRecoveryKey != nil)
        .onChange(of: account.state) { _, new in
            if new == .signedIn && account.pendingRecoveryKey == nil { dismiss() }
        }
        .onAppear { error = account.notice }
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Inkwell").font(.system(size: 34, weight: .semibold, design: .serif))
                Text("Sign in to keep your notes safe and open them on the web. Notes are encrypted on this iPad before they are sent.")
                    .foregroundStyle(.secondary)

                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: mode) { error = nil }

                switch mode {
                case .signIn:
                    input("Email", text: $email, content: .username, keyboard: .emailAddress)
                    input("Password", text: $password, secure: true, content: .password)
                case .create:
                    Text("You need an invite code from the person who runs this service.").font(.footnote).foregroundStyle(.secondary)
                    input("Invite code", text: $invite)
                    input("Email", text: $email, content: .username, keyboard: .emailAddress)
                    input("Choose a password", text: $password, secure: true, content: .newPassword)
                    input("Type it again", text: $confirm, secure: true, content: .newPassword)
                    Text("This password also locks your notes. Nobody can reset it for you, but you will get a recovery key as a backup.")
                        .font(.footnote).foregroundStyle(.secondary)
                case .forgot:
                    Text("Ask the administrator for a reset code. You also need the recovery key you saved when you made your account.")
                        .font(.footnote).foregroundStyle(.secondary)
                    input("Email", text: $email, content: .username, keyboard: .emailAddress)
                    input("Reset code", text: $resetCode)
                    input("Recovery key", text: $recoveryKey)
                    input("New password", text: $password, secure: true, content: .newPassword)
                    input("Type it again", text: $confirm, secure: true, content: .newPassword)
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.callout)
                }

                Button(action: submit) {
                    Group {
                        if busy { ProgressView() } else { Text(buttonTitle) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy)

                DisclosureGroup("Server address", isExpanded: $showServer) {
                    input("Where your notes are stored", text: $account.serverURL, keyboard: .URL)
                        .padding(.top, 8)
                }
                .tint(.secondary)

                Text("The notes already on this iPad are added to your account when you sign in.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .onAppear { if account.serverURL.isEmpty { showServer = true } }
    }

    private var buttonTitle: String {
        switch mode {
        case .signIn: "Sign in"
        case .create: "Create account"
        case .forgot: "Reset password"
        }
    }

    private func submit() {
        error = nil
        Task {
            busy = true
            defer { busy = false }
            do {
                switch mode {
                case .signIn:
                    try await account.signIn(email: email, password: password)
                case .create:
                    try await account.register(invite: invite, email: email, password: password, confirm: confirm)
                case .forgot:
                    try await account.resetPassword(email: email, code: resetCode, recoveryKey: recoveryKey,
                                                    newPassword: password, confirm: confirm)
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: A reset was accepted but the recovery key didn't open the notes

    @State private var retryKey = ""

    private var resetRetry: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Recovery key").font(.system(size: 30, weight: .semibold, design: .serif))
                Text("Your new password is set, but that recovery key did not unlock your notes. Check it and try again.")
                    .foregroundStyle(.secondary)
                input("Recovery key", text: $retryKey)
                if let error { Text(error).foregroundStyle(.red).font(.callout) }
                Button {
                    error = nil
                    Task {
                        busy = true
                        defer { busy = false }
                        do { try await account.completeReset(recoveryKey: retryKey) } catch { self.error = error.localizedDescription }
                    }
                } label: {
                    Group { if busy { ProgressView() } else { Text("Try again") } }.frame(maxWidth: .infinity).frame(height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(busy)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func input(_ title: String, text: Binding<String>, secure: Bool = false,
                       content: UITextContentType? = nil, keyboard: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Group {
                if secure { SecureField("", text: text) } else { TextField("", text: text) }
            }
            .textContentType(content)
            .keyboardType(keyboard)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        }
    }
}

// MARK: - Recovery key

struct RecoveryKeyView: View {
    let key: String
    var onContinue: () -> Void
    @State private var saved = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Save your recovery key").font(.system(size: 30, weight: .semibold, design: .serif))
                Text("If you ever forget your password, this key is the only way to get your notes back. Not even the administrator can recover them without it.")
                Text(key)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
                    .accessibilityLabel("Recovery key")
                HStack(spacing: 12) {
                    Button {
                        // Kept off Universal Clipboard and cleared after two minutes.
                        UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: key]],
                                                      options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(.bordered)
                    ShareLink(item: key) { Label("Share or print", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }
                Text("Write it down or print it and keep it somewhere safe, away from this iPad. Do not store it only in a note in this app.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("I have saved my recovery key", isOn: $saved)
                Button(action: onContinue) {
                    Text("Continue").frame(maxWidth: .infinity).frame(height: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!saved)
            }
            .padding(24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
    }
}

// MARK: - Account (signed in)

struct AccountView: View {
    @EnvironmentObject private var account: AccountManager
    @EnvironmentObject private var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var new = ""
    @State private var confirm = ""
    @State private var message: String?
    @State private var problem: String?
    @State private var busy = false
    @State private var confirmSignOut = false
    @State private var confirmNewKey = false

    var body: some View {
        NavigationStack {
            Group {
                if let key = account.pendingRecoveryKey {
                    RecoveryKeyView(key: key) { account.pendingRecoveryKey = nil }
                } else {
                    form
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if account.pendingRecoveryKey == nil {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
            }
        }
        .interactiveDismissDisabled(account.pendingRecoveryKey != nil)
    }

    private var form: some View {
        Form {
            Section {
                LabeledContent("Signed in as", value: account.email)
                LabeledContent("Server", value: account.serverURL)
            }

            Section("Sync") {
                Label(sync.summary, systemImage: sync.icon)
                    .foregroundStyle({ if case .offline = sync.status { return Color.red } else { return Color.primary } }())
                Button("Sync now") { sync.syncNow() }
                if let usage = sync.storage {
                    LabeledContent("Storage used",
                                   value: "\(ByteCountFormatter.string(fromByteCount: Int64(usage.bytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(usage.limit), countStyle: .file))")
                }
            }

            Section("Change password") {
                SecureField("Current password", text: $current).textContentType(.password)
                SecureField("New password", text: $new).textContentType(.newPassword)
                SecureField("Type the new one again", text: $confirm).textContentType(.newPassword)
                Button("Change password", action: changePassword).disabled(busy || current.isEmpty || new.isEmpty)
                if let message { Text(message).foregroundStyle(.green) }
                if let problem { Text(problem).foregroundStyle(.red) }
            }

            Section("Recovery") {
                Text("Your recovery key can unlock your notes if you forget your password.").font(.footnote).foregroundStyle(.secondary)
                Button("Make a new recovery key") { confirmNewKey = true }.disabled(busy)
            }

            Section {
                Button("Sign out", role: .destructive) { confirmSignOut = true }
            } footer: {
                Text("Notes stay on this iPad. They stop syncing until you sign in again.")
            }
        }
        .confirmationDialog("Sign out of Inkwell?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                account.signOut()
                dismiss()
            }
        }
        .confirmationDialog("Replace your recovery key? The old one will stop working.", isPresented: $confirmNewKey, titleVisibility: .visible) {
            Button("Make a new key") {
                Task {
                    busy = true
                    defer { busy = false }
                    do { try await account.makeNewRecoveryKey() } catch { problem = error.localizedDescription }
                }
            }
        }
    }

    private func changePassword() {
        message = nil
        problem = nil
        Task {
            busy = true
            defer { busy = false }
            do {
                try await account.changePassword(current: current, new: new, confirm: confirm)
                current = ""; new = ""; confirm = ""
                message = "Password changed. Other devices will ask for the new password."
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
