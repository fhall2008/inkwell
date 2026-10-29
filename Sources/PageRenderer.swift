import UIKit
import PencilKit

/// Flattens a page (template, images, ink) into a bitmap for thumbnails and exports.
enum PageRenderer {
    /// A4 at 96 dpi. The default for new notes and for imported PDF and Word pages.
    static let pageSize = CGSize(width: 794, height: 1123)

    /// Biggest side of any bitmap this makes, in pixels, so a huge whiteboard can't run the iPad out of memory.
    private static let maxPixels: CGFloat = 4096

    static func render(
        note: Note,
        page: NotePage,
        scale: CGFloat = 2,
        includeTemplate: Bool = true,
        includeImages: Bool = true
    ) -> UIImage {
        let size = note.pageSize
        let effectiveScale = min(scale, maxPixels / max(size.width, size.height))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = effectiveScale
        let rect = CGRect(origin: .zero, size: size)
        let number = (note.pages.firstIndex { $0.id == page.id } ?? 0) + 1

        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor(hex: note.paperHex).setFill()
            UIRectFill(rect)

            if let file = page.background {
                if includeImages { ImageCache.image(file)?.draw(in: rect) }
            } else if includeTemplate {
                if note.isWhiteboard {
                    if let tile = TemplateKind.whiteboardTile(note.template, paperHex: note.paperHex) {
                        UIColor(patternImage: tile).setFill()
                        UIRectFill(rect)
                    }
                } else {
                    note.template.drawFitted(size: size)
                }
            }

            // The watermark sits above the paper but behind pictures, objects and ink.
            if let watermark = note.watermark, !note.isWhiteboard {
                WatermarkRenderer.draw(watermark, in: size)
            }

            if note.pageNumbers && !note.isWhiteboard {
                drawPageNumber(number, in: size)
            }

            if includeImages {
                for placed in page.images {
                    guard let img = ImageCache.image(placed.file) else { continue }
                    img.draw(in: CGRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height))
                }
                for object in page.objects { ObjectDrawing.draw(object) }
            }

            if let drawing = try? PKDrawing(data: page.drawing), !drawing.bounds.isEmpty {
                // Render ink with light-mode colours so it matches the paper.
                UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                    drawing.image(from: rect, scale: effectiveScale).draw(in: rect)
                }
            }
        }
    }

    private static func drawPageNumber(_ number: Int, in size: CGSize) {
        let text = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor(red: 0.36, green: 0.40, blue: 0.45, alpha: 1),
        ]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: size.height - 28), withAttributes: attributes)
    }
}
