import Foundation
import SwiftSoup

nonisolated struct TWVariant: Identifiable, Hashable, Sendable {
    var sku: String?
    var name: String
    var price: Double?
    var upc: String?
    var image: URL?
    var styles: [String: String]
    var color: String?
    var size: String?
    var inStock: String?

    var id: String { sku ?? name }
    /// What to show under the swatch.
    var title: String {
        color ?? (styles.isEmpty ? name : styles.keys.sorted().compactMap { styles[$0] }.joined(separator: " / "))
    }
}

nonisolated struct TWProduct: Sendable {
    var name: String
    var brand: String?
    var image: URL?
    var url: URL
    var category: Category
    var variants: [TWVariant]
}

nonisolated enum TWError: LocalizedError {
    case invalidLink, notProductPage, unreachable, status(Int), notAProduct

    var errorDescription: String? {
        switch self {
        case .invalidLink: "That is not a valid link"
        case .notProductPage: "Paste a Tackle Warehouse product page link (it contains \"descpage-\")"
        case .unreachable: "Couldn't reach Tackle Warehouse. Check your connection and try again."
        case .status(let code): "Tackle Warehouse returned \(code)"
        case .notAProduct: "That page didn't look like a Tackle Warehouse product"
        }
    }
}

/// Reads Tackle Warehouse product pages (…/descpage-XXXX.html). Each color/size is a schema.org Offer row
/// carrying its own SKU, price, GTIN and swatch image.
nonisolated enum TackleWarehouse {
    static let host = "www.tacklewarehouse.com"

    static func searchURL(_ text: String) -> URL {
        var c = URLComponents()
        c.scheme = "https"
        c.host = host
        c.path = "/search-tackle.html"
        c.queryItems = [URLQueryItem(name: "searchtext", value: text)]
        return c.url!
    }

    static func isProductLink(_ text: String) -> Bool {
        text.range(of: "descpage-", options: .caseInsensitive) != nil
    }

    /// Checks the link and points it at the canonical https host.
    static func productURL(from raw: String) throws -> URL {
        guard var c = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), let h = c.host else {
            throw TWError.invalidLink
        }
        let hostOK = h == "tacklewarehouse.com" || h.hasSuffix(".tacklewarehouse.com")
        guard hostOK, c.path.range(of: "descpage-", options: .caseInsensitive) != nil else { throw TWError.notProductPage }
        c.scheme = "https"
        c.host = host
        c.fragment = nil
        guard let url = c.url else { throw TWError.invalidLink }
        return url
    }

    static func fetchProduct(_ raw: String) async throws -> TWProduct {
        let url = try productURL(from: raw)
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpShouldHandleCookies = false
        request.setValue(Net.browserUserAgent, forHTTPHeaderField: "User-Agent")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw TWError.unreachable
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TWError.status(http.statusCode)
        }
        return try await parse(html: String(decoding: data, as: UTF8.self), url: url)
    }

    @concurrent
    static func parse(html: String, url: URL) async throws -> TWProduct {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        func attr(_ el: Element?, _ name: String) -> String? {
            guard let el, el.hasAttr(name), let v = try? el.attr(name), !v.isEmpty else { return nil }
            return v
        }
        func text(_ el: Element?) -> String { (try? el?.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" }
        func first(_ root: Element, _ css: String) -> Element? { try? root.select(css).first() }

        let titleText = text(first(doc, "title"))
            .replacingOccurrences(of: #"\s*-\s*Tackle Warehouse\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        let name = (attr(first(doc, ".js-ordering-table"), "data-owner-name") ?? titleText).trimmingCharacters(in: .whitespaces)
        let brand = attr(first(doc, "meta[itemprop=brand]"), "content")
        let mainImg = first(doc, "img[itemprop=image]")
        let image = largest(fromSrcset: attr(mainImg, "srcset")) ?? attr(mainImg, "src").flatMap { resized($0, width: 600) }

        let rows = (try? doc.select("tr[itemprop=offers]").array()) ?? []
        let variants: [TWVariant] = rows.map { row in
            var styles: [String: String] = [:]
            var thumb: String?
            for st in (try? row.select(".js-ordering-style").array()) ?? [] {
                let key = text(first(st, ".js-ordering-style-name"))
                let val = text(first(st, ".js-ordering-style-item-name"))
                if !key.isEmpty, !val.isEmpty { styles[key] = val }
                thumb = thumb ?? attr(st, "data-stylethumb")
            }
            let sizeKey = styles.keys.sorted().first { $0.range(of: "size|length|weight|count|pack", options: [.regularExpression, .caseInsensitive]) != nil }
            return TWVariant(
                sku: attr(row, "data-code") ?? attr(first(row, "meta[itemprop=sku]"), "content"),
                name: text(first(row, ".js-ordering-name")),
                price: attr(first(row, "meta[itemprop=price]"), "content").flatMap(Double.init),
                upc: UPC.normalize(attr(first(row, "meta[itemprop^=gtin]"), "content")),
                image: thumb.flatMap { resized($0, width: 600) },
                styles: styles,
                color: styles["Color"],
                size: sizeKey.flatMap { styles[$0] },
                inStock: text(first(row, ".js-ordering-available")).nilIfBlank
            )
        }

        if name.isEmpty && variants.isEmpty { throw TWError.notAProduct }
        return TWProduct(name: name, brand: brand, image: image, url: url, category: .guess(from: name), variants: variants)
    }

    /// Their image server takes the width as `nw`; ask for something big enough to look sharp.
    static func resized(_ raw: String, width: Int) -> URL? {
        guard let base = URL(string: "https://\(host)/"), let abs = URL(string: raw, relativeTo: base)?.absoluteURL,
              var c = URLComponents(url: abs, resolvingAgainstBaseURL: true) else { return nil }
        if c.queryItems?.contains(where: { $0.name == "path" }) == true {
            c.queryItems = c.queryItems!.filter { $0.name != "nw" } + [URLQueryItem(name: "nw", value: String(width))]
        }
        return c.url
    }

    static func largest(fromSrcset srcset: String?) -> URL? {
        guard let srcset else { return nil }
        let best = srcset.split(separator: ",")
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .compactMap { parts -> (String, Int)? in
                guard let u = parts.first else { return nil }
                return (u, parts.count > 1 ? Int(parts[1].filter(\.isASCIIDigit)) ?? 0 : 0)
            }
            .max { $0.1 < $1.1 }
        return best.flatMap { resized($0.0, width: 600) }
    }
}

nonisolated enum Net {
    /// Pages are written for phones; ask for the same HTML Safari on an iPhone would get.
    static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}
