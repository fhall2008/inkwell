import SwiftUI
import PencilKit
import PhotosUI

/// Shared tool picker so one palette follows whichever page you are writing on.
/// PencilKit gives Apple Pencil Pro squeeze, barrel roll and haptics for free through PKToolPicker.
@MainActor
final class InkSession {
    static let shared = InkSession()
    let picker = PKToolPicker()
    weak var canvas: PKCanvasView?

    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }

    func hide() {
        if let canvas { picker.setVisible(false, forFirstResponder: canvas) }
    }
}

struct InkCanvas: UIViewRepresentable {
    @Binding var data: Data
    let allowsInput: Bool
    var onActivate: () -> Void
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light   // keep ink colours true on white paper
        canvas.drawingPolicy = .default              // follows Settings > Apple Pencil > Only Draw with Apple Pencil
        canvas.isScrollEnabled = false
        canvas.delegate = context.coordinator
        context.coordinator.canvas = canvas

        let picker = InkSession.shared.picker
        picker.addObserver(canvas)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.activate))
        tap.cancelsTouchesInView = false
        canvas.addGestureRecognizer(tap)

        if InkSession.shared.canvas == nil {
            DispatchQueue.main.async { context.coordinator.activate() }
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.isUserInteractionEnabled = allowsInput
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        InkSession.shared.picker.removeObserver(canvas)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: InkCanvas
        weak var canvas: PKCanvasView?

        init(_ parent: InkCanvas) { self.parent = parent }

        @objc func activate() {
            guard let canvas else { return }
            let session = InkSession.shared
            session.canvas = canvas
            session.picker.setVisible(true, forFirstResponder: canvas)
            canvas.becomeFirstResponder()
            parent.onActivate()
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) { activate() }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.data = canvasView.drawing.dataRepresentation()
            parent.onChange()
        }
    }
}

// MARK: - Camera

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

// MARK: - Share sheet

struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
