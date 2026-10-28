import PDFKit
import UIKit

/// Turns each PDF page into an A4 page background you can write on.
enum PDFImporter {
    enum ImportError: Error { case unreadable }

    static func pages(from url: URL) throws -> (title: String, pages: [NotePage]) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { throw ImportError.unreadable }
        let canvas = PageRenderer.pageSize
        let bounds = CGRect(origin: .zero, size: canvas)
        let scale: CGFloat = 2
        var pages: [NotePage] = []

        for i in 0..<doc.pageCount {
            guard let cgPage = doc.page(at: i)?.pageRef else { continue }
            try autoreleasepool {
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = scale
                let composed = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
                    UIColor.white.setFill()
                    UIRectFill(bounds)

                    let cg = ctx.cgContext
                    cg.saveGState()
                    // Flip into PDF coordinates (origin bottom-left), then fit the page inside A4,
                    // centred, keeping its aspect ratio and honouring any page rotation.
                    cg.translateBy(x: 0, y: canvas.height)
                    cg.scaleBy(x: 1, y: -1)
                    cg.concatenate(cgPage.getDrawingTransform(.mediaBox, rect: bounds, rotate: 0, preserveAspectRatio: true))
                    cg.drawPDFPage(cgPage)
                    cg.restoreGState()
                }
                guard let data = composed.jpegData(compressionQuality: 0.85) else { throw ImportError.unreadable }
                let name = "\(UUID().uuidString).jpg"
                try data.write(to: Paths.images.appendingPathComponent(name))
                var notePage = NotePage()
                notePage.background = name
                pages.append(notePage)
            }
        }
        guard !pages.isEmpty else { throw ImportError.unreadable }
        return (url.deletingPathExtension().lastPathComponent, pages)
    }
}
