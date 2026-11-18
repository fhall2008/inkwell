import SwiftUI

// iOS 16 stand-ins for APIs that only exist on iOS 17+.

/// Same look as `Button(_:systemImage:role:action:)`, which needs iOS 17.
struct ActionButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) { Label(title, systemImage: systemImage) }
    }
}

/// Same look as `Menu(_:systemImage:content:)`, which needs iOS 17.
struct ActionMenu<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        Menu { content() } label: { Label(title, systemImage: systemImage) }
    }
}

/// Stand-in for `ContentUnavailableView`, which needs iOS 17.
struct EmptyState<Actions: View>: View {
    let title: String
    let systemImage: String
    var message: String?
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            actions().padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

extension EmptyState where Actions == EmptyView {
    init(_ title: String, systemImage: String, message: String? = nil) {
        self.init(title: title, systemImage: systemImage, message: message) { EmptyView() }
    }
}

extension UIImage {
    /// iOS 16 crashes when SwiftUI shows an image whose scale is below 1. Re-wrap the same pixels at scale 1.
    var unitScaled: UIImage { PageRenderer.unitScale(self) }
}
