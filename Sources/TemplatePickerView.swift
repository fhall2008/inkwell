import SwiftUI

struct TemplatePickerView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    let folderID: UUID?
    var onCreate: (Note) -> Void

    private enum Tab: Hashable {
        case category(TemplateCategory)
        case mine
    }

    private enum Choice: Hashable {
        case builtIn(TemplateKind)
        case custom(UUID)
    }

    @State private var tab: Tab = .category(.basic)
    @State private var choice: Choice = .builtIn(.ruled)

    private var builtIns: [TemplateKind] {
        guard case .category(let c) = tab else { return [] }
        return TemplateKind.allCases.filter { $0.category == c }
    }

    private var selectedName: String {
        switch choice {
        case .builtIn(let k): return k.title
        case .custom(let id): return store.customTemplates.first { $0.id == id }?.name ?? "Template"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Category", selection: $tab) {
                    ForEach(TemplateCategory.allCases) { Text($0.rawValue).tag(Tab.category($0)) }
                    Text("My templates").tag(Tab.mine)
                }
                .pickerStyle(.segmented)

                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 20)], spacing: 22) {
                        if tab == .mine {
                            ForEach(store.customTemplates) { t in
                                card(title: t.name, image: t.base.image, selected: choice == .custom(t.id))
                                    .onTapGesture { choice = .custom(t.id) }
                                    .contextMenu {
                                        Button("Delete template", systemImage: "trash", role: .destructive) {
                                            store.delete(t)
                                        }
                                    }
                            }
                        } else {
                            ForEach(builtIns) { kind in
                                card(title: kind.title, image: kind.image, selected: choice == .builtIn(kind))
                                    .onTapGesture { choice = .builtIn(kind) }
                            }
                        }
                    }
                    if tab == .mine && store.customTemplates.isEmpty {
                        ContentUnavailableView(
                            "No saved templates",
                            systemImage: "square.on.square",
                            description: Text("In any note, open the ••• menu and choose Save page as template.")
                        )
                    }
                }

                HStack {
                    Text("Selected: ").foregroundStyle(.secondary) + Text(selectedName).bold()
                    Spacer()
                    Button("Create note", action: create).buttonStyle(.borderedProminent).controlSize(.large)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(24)
            .background(Theme.paper)
            .navigationTitle("Choose a template")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func card(title: String, image: UIImage, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 220, alignment: .top)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Theme.accent : Theme.hairline, lineWidth: selected ? 3 : 1))
            Text(title).font(.headline)
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private func create() {
        let note: Note
        switch choice {
        case .builtIn(let kind):
            note = store.addNote(template: kind, folder: folderID)
        case .custom(let id):
            guard let t = store.customTemplates.first(where: { $0.id == id }) else { return }
            note = store.addNote(template: t.base, folder: folderID, drawing: t.drawing)
        }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onCreate(note) }
    }
}
