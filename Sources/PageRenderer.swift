import UIKit
import PencilKit

/// Flattens a page (template, images, ink) into a bitmap for thumbnails and exports.
enum PageRenderer {
    /// A4 at 96 dpi.
    static let pageSize = CGSize(width: 794, height: 1123)

    static func render(
        note: Note,
        page: NotePage,
        scale: CGFloat = 2,
        includeTemplate: Bool = true,
        includeImages: Bool = true
    ) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let rect = CGRect(origin: .zero, size: pageSize)
        return UIGraphicsImageRenderer(size: pageSize, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(rect)
            if includeTemplate { note.template.draw(size: pageSize) }
            if includeImages {
                for placed in page.images {
                    guard let img = ImageCache.image(placed.file) else { continue }
                    img.draw(in: CGRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height))
                }
            }
            if let drawing = try? PKDrawing(data: page.drawing), !drawing.bounds.isEmpty {
                // Render ink with light-mode colours so it matches the paper.
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    drawing.image(from: rect, scale: scale).draw(in: rect)
                }
            }
        }
    }
}
