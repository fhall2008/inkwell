import SwiftUI

/// A stamp drawn the way it will look on the page, tilt and all.
struct StampPreview: View {
    let stamp: CustomStamp

    var body: some View {
        let object = PageObject.stamp(from: stamp)
        ObjectContent(o: .constant(object), size: CGSize(width: object.width, height: object.height), editable: false, onChange: {})
            .opacity(stamp.opacity)
            .rotationEffect(.degrees(stamp.rotation))
            .scaleEffect(min(1, 220 / max(object.width, 1)))
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Stamp preview: \(stamp.text)")
    }
}

/// Make or change a custom stamp.
struct StampEditorSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    @State private var stamp: CustomStamp
    var onSaved: (CustomStamp) -> Void

    init(stamp: CustomStamp? = nil, onSaved: @escaping (CustomStamp) -> Void) {
        _stamp = State(initialValue: stamp ?? CustomStamp(name: "", text: "PAID"))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    StampPreview(stamp: stamp)
                        .frame(height: 130)
                        .background(Color.white)
                }

                Section("Text") {
                    TextField("Stamp text", text: $stamp.text, axis: .vertical).lineLimit(1...3)
                    TextField("Name in your list (optional)", text: $stamp.name)
                }

                Section("Look") {
                    ColorPicker("Colour", selection: Binding(get: { Color(hex: stamp.colorHex) }, set: { stamp.colorHex = $0.hex }),
                                supportsOpacity: false)
                    Stepper("Text size \(Int(stamp.fontSize))", value: $stamp.fontSize, in: 12...72, step: 2)
                    Toggle("Bold", isOn: $stamp.bold)
                    Picker("Border", selection: $stamp.border) {
                        ForEach(StampBorder.allCases) { Text($0.title).tag($0) }
                    }
                    slider("Tilt", value: $stamp.rotation, range: -45...45, step: 1, format: "\(Int(stamp.rotation))°")
                    slider("Opacity", value: $stamp.opacity, range: 0.1...1, step: 0.05, format: "\(Int(stamp.opacity * 100))%")
                }
            }
            .navigationTitle("Custom stamp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(stamp.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(format).foregroundStyle(.secondary).monospacedDigit() }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }

    private func save() {
        var saved = stamp
        saved.text = saved.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if saved.name.trimmingCharacters(in: .whitespaces).isEmpty { saved.name = saved.text.replacingOccurrences(of: "\n", with: " ") }
        store.saveStamp(saved)
        onSaved(saved)
        dismiss()
    }
}

/// "My stamps": tap one to put it on the page; make new ones; edit or remove old ones.
struct StampLibrarySheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var onInsert: (CustomStamp) -> Void

    @State private var editing: CustomStamp?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            Group {
                if store.customStamps.isEmpty {
                    ContentUnavailableView {
                        Label("No saved stamps yet", systemImage: "seal")
                    } description: {
                        Text("Make your own: choose the words, colour, border and tilt. Tap Make a stamp to start.")
                    } actions: {
                        Button("Make a stamp") { creating = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(store.customStamps) { stamp in
                            Button {
                                onInsert(stamp)
                                dismiss()
                            } label: {
                                HStack(spacing: 16) {
                                    StampPreview(stamp: stamp).frame(width: 150, height: 70)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(stamp.name).font(.headline)
                                        Text("Tap to place on the page").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.deleteStamp(stamp) } label: { Label("Delete", systemImage: "trash") }
                                Button { editing = stamp } label: { Label("Edit", systemImage: "pencil") }.tint(Theme.accent)
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = stamp }
                                Button("Delete", systemImage: "trash", role: .destructive) { store.deleteStamp(stamp) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My stamps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { creating = true } label: { Label("Make a stamp", systemImage: "plus") }
                }
            }
            .sheet(isPresented: $creating) { StampEditorSheet { _ in } }
            .sheet(item: $editing) { stamp in StampEditorSheet(stamp: stamp) { _ in } }
        }
    }
}
