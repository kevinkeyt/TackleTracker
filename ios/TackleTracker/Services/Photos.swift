import UIKit
import Vision

nonisolated enum Photos {
    /// Phone photos are several MB; shrink to 1200px JPEG before storing.
    @concurrent
    static func jpeg(from data: Data, maxDimension: CGFloat = 1200) async -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image, maxDimension: maxDimension)
    }

    static func jpeg(from image: UIImage, maxDimension: CGFloat = 1200) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.82)
    }

    /// Downloads a product image onto the phone so it shows offline.
    static func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Net.browserUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return nil }
        return await jpeg(from: data)
    }

    /// Reads a barcode out of a still photo.
    @concurrent
    static func barcode(in image: UIImage) async -> String? {
        guard let cg = image.cgImage else { return nil }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.upce, .ean13, .ean8, .code128]
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        try? VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
        guard let best = request.results?.first(where: { $0.payloadStringValue != nil }),
              let payload = best.payloadStringValue else { return nil }
        return best.symbology == .upce ? UPC.expandUPCE(payload) : payload
    }
}

extension CGImagePropertyOrientation {
    nonisolated init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
