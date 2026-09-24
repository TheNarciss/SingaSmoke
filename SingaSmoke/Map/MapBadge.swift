import MapKit
import SingaSmokeCore
import UIKit

/// Round map markers drawn once and cached: a white ring, a coloured disc, a symbol or a number.
@MainActor
enum MapBadge {
    private static var cache: [String: UIImage] = [:]

    static func image(symbol: String? = nil, text: String? = nil, fill: UIColor, ring: UIColor = .white,
                      glyph: UIColor = .white, diameter: CGFloat) -> UIImage {
        let key = "\(symbol ?? "")|\(text ?? "")|\(fill.hexKey)|\(ring.hexKey)|\(glyph.hexKey)|\(diameter)"
        if let hit = cache[key] { return hit }

        let margin: CGFloat = 5   // room for the shadow
        let size = CGSize(width: diameter + margin * 2, height: diameter + margin * 2)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let disc = CGRect(x: margin, y: margin, width: diameter, height: diameter)
            cg.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3.5, color: UIColor.black.withAlphaComponent(0.35).cgColor)
            ring.setFill()
            UIBezierPath(ovalIn: disc).fill()
            cg.setShadow(offset: .zero, blur: 0, color: nil)
            fill.setFill()
            UIBezierPath(ovalIn: disc.insetBy(dx: diameter * 0.09, dy: diameter * 0.09)).fill()

            if let symbol,
               let sf = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: diameter * 0.38, weight: .bold))?
                .withTintColor(glyph, renderingMode: .alwaysOriginal) {
                let s = sf.size
                sf.draw(in: CGRect(x: disc.midX - s.width / 2, y: disc.midY - s.height / 2, width: s.width, height: s.height))
            }
            if let text {
                let base = UIFont.systemFont(ofSize: diameter * (text.count > 2 ? 0.33 : 0.4), weight: .heavy)
                let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
                let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: glyph])
                let s = attributed.size()
                attributed.draw(at: CGPoint(x: disc.midX - s.width / 2, y: disc.midY - s.height / 2))
            }
        }
        cache[key] = image
        return image
    }

    // MARK: The markers the app uses

    static func spot(_ spot: SmokingSpot) -> UIImage {
        switch spot.source {
        case .nea:
            // The yellow box, on green: what an official designated smoking area looks like.
            return image(symbol: "square", fill: Brand.allowedUI, glyph: Brand.boxYellowUI, diameter: 34)
        case .changi:
            return image(symbol: "airplane", fill: Brand.allowedUI, diameter: 32)
        case .osmArea, .osmVenue:
            return image(symbol: "square.dashed", fill: .white, ring: Brand.allowedUI, glyph: Brand.allowedUI, diameter: 30)
        }
    }

    static func retailer(_ retailer: Retailer) -> UIImage {
        image(symbol: retailer.category.symbol, fill: retailer.category.uiColor, diameter: 26)
    }

    /// A group of markers when zoomed out: green for smoking spots, ink for shops.
    static func cluster(count: Int, fill: UIColor) -> UIImage {
        let label = count > 999 ? "1k+" : "\(count)"
        let diameter: CGFloat = count < 10 ? 32 : count < 100 ? 38 : 44
        return image(text: label, fill: fill, diameter: diameter)
    }

    static func exit() -> UIImage {
        image(symbol: "figure.walk", fill: Brand.warningUI, diameter: 36)
    }

    static func destination() -> UIImage {
        image(symbol: "flag.checkered", fill: ink, diameter: 36)
    }

    /// Near-black of the shop clusters and the destination flag.
    static let ink = UIColor(white: 0.08, alpha: 1)
}

/// Map marker view showing a `MapBadge` image, centred on its coordinate.
final class BadgeAnnotationView: MKAnnotationView {
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        collisionMode = .circle
        centerOffset = .zero
        canShowCallout = false
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        let scale: CGFloat = selected ? 1.25 : 1
        UIView.animate(withDuration: animated ? 0.2 : 0, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
            self.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        transform = .identity
    }
}

private extension UIColor {
    var hexKey: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }
}
