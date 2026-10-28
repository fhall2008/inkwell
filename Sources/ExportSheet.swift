import SwiftUI

struct ExportSheet: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .pdf
    @State private var includeTemplate = true
    @State private var working = false
    @State private var shared: SharedFile?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(note.title) · \(note.pages.count) page\(note.pages.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(ExportFormat.allCases) { f in
                        Button { format = f } label: {
                            HStack(spacing: 14) {
                                Text(f.badge)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 36)
                                    .background(Color(f.badgeColor), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.headline).foregroundStyle(Theme.ink)
                                    Text(f.detail).font(.footnote).foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: format == f ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(format == f ? Theme.accent : .secondary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(.background, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(format == f ? Theme.accent : Theme.hairline, lineWidth: format == f ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(format == f ? .isSelected : [])
                    }
                }

                Toggle("Include page template lines and grid", isOn: $includeTemplate)
                    .disabled(format == .txt || format == .rtf || format == .backup)

                if let errorText { Text(errorText).foregroundStyle(.red).font(.footnote) }

                HStack(spacing: 12) {
                    Button(action: share) {
                        HStack {
                            if working { ProgressView() }
                            Text("Share or save to Files").frame(maxWidth: .infinity)
                        }
                        .frame(height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Print", action: printNote)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                .disabled(working)
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(Theme.paper)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .sheet(item: $shared) { ShareSheet(url: $0.url) }
        }
        .presentationDetents([.large])
    }

    private func share() {
        run(format) { shared = SharedFile(url: $0) }
    }

    private func printNote() {
        run(.pdf) { url in
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = note.title
            controller.printInfo = info
            controller.printingItem = url
            controller.present(animated: true)
        }
    }

    private func run(_ format: ExportFormat, then finish: @escaping (URL) -> Void) {
        working = true
        errorText = nil
        Task {
            do {
                let url = try await Exporter.export(note: note, format: format, includeTemplate: includeTemplate)
                finish(url)
            } catch {
                errorText = error.localizedDescription
            }
            working = false
        }
    }
}
