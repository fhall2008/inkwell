import PDFKit
import UIKit

/// Turns each PDF page into an A4 page background you can write on.
enum PDFImporter {
    enum ImportError: Error { case unreadable }

    static func pages(from url: URL) throws -> (title: String, pages: [NotePage]) {
        guard let doc = PDFDocument(url: url), doc.pageCount > 0 else { throw ImportError.unreadable }
        let canvas = PageRenderer.pageSize
        let scale: CGFloat = 2
        var pages: [NotePage] = []

        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            try autoreleasepool {
                var bounds = page.bounds(for: .mediaBox)
                if page.rotation % 180 != 0 { bounds = CGRect(x: 0, y: 0, width: bounds.height, height: bounds.width) }
                guard bounds.width > 0, bounds.height > 0 else { return }

                // Fit inside the A4 page, centred, keeping the PDF's aspect ratio.
                let fit = min(canvas.width / bounds.width, canvas.height / bounds.height)
                let target = CGSize(width: bounds.width * fit, height: bounds.height * fit)
                let thumb = page.thumbnail(of: CGSize(width: target.width * scale, height: target.height * scale), for: .mediaBox)

                let format = UIGraphicsImageRendererFormat.default()
                format.scale = scale
                let composed = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
                    UIColor.white.setFill()
                    UIRectFill(CGRect(origin: .zero, size: canvas))
                    thumb.draw(in: CGRect(
                        x: (canvas.width - target.width) / 2,
                        y: (canvas.height - target.height) / 2,
                        width: target.width,
                        height: target.height
                    ))
                }
                guard let data = composed.jpegData(compressionQuality: 0.8) else { throw ImportError.unreadable }
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
