import Foundation
import SwiftSoup

/// One color/size a product page offers.
nonisolated struct ProductVariant: Identifiable, Hashable, Sendable {
    var sku: String?
    var name: String
    var price: Double?
    var upc: String?
    var image: URL?
    var styles: [String: String] = [:]
    var color: String?
    var size: String?
    var inStock: String?

    var id: String { sku ?? upc ?? name }
    /// What to show in the option list.
    var title: String {
        if let color { return [color, size].compactMap { $0 }.joined(separator: ", ") }
        if !styles.isEmpty { return styles.keys.sorted().compactMap { styles[$0] }.joined(separator: " / ") }
        return [name.nilIfBlank, size].compactMap { $0 }.joined(separator: ", ").nilIfBlank ?? sku ?? "Option"
    }
}

/// What a store's product page says about the product.
nonisolated struct ProductInfo: Sendable {
    var name: String
    var brand: String?
    var image: URL?
    var url: URL
    var category: Category
    var variants: [ProductVariant]
}

nonisolated enum ProductPageError: LocalizedError {
    case invalidLink, unreachable, status(Int), notAProduct

    var errorDescription: String? {
        switch self {
        case .invalidLink: "That doesn't look like a web link. Copy the product page's address and paste it here."
        case .unreachable: "Couldn't reach that site. Check your connection and try again."
        case .status(let code): "The site returned an error (\(code)). Try opening the link in Safari to check it."
        case .notAProduct: "Couldn't find product details on that page. Fill them in yourself; the link is saved for reordering."
        }
    }
}

/// Reads product details from any store's product page. Most stores describe their products for search engines
/// and link previews, so this looks, in order, at schema.org JSON-LD, schema.org microdata (some stores list every
/// color as its own offer row this way), and Open Graph tags.
nonisolated enum ProductPage {
    /// A web link from pasted text: http(s) only, `https://` added when the scheme was left off.
    static func link(from raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        if !text.contains("://") {
            guard text.contains(".") else { return nil }
            text = "https://" + text
        }
        guard var c = URLComponents(string: text), let scheme = c.scheme?.lowercased(),
              scheme == "https" || scheme == "http", let host = c.host, host.contains(".") else { return nil }
        c.scheme = "https" // iOS blocks plain-http loads; stores all serve https
        c.fragment = nil
        return c.url
    }

    static func fetch(_ raw: String) async throws -> ProductInfo {
        guard let url = link(from: raw) else { throw ProductPageError.invalidLink }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(Net.browserUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ProductPageError.unreachable
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ProductPageError.status(http.statusCode)
        }
        // A redirect (short links, tracking links) lands on the real page; keep that address.
        return try await parse(html: String(decoding: data, as: UTF8.self), url: response.url ?? url)
    }

    @concurrent
    static func parse(html: String, url: URL) async throws -> ProductInfo {
        let doc = try SwiftSoup.parse(html, url.absoluteString)
        let ld = jsonLDProducts(doc)
        let ldMain = ld.first

        let siteName = meta(doc, property: "og:site_name")
        let name = (ldMain.flatMap { str($0["name"]) }
            ?? attr(first(doc, ".js-ordering-table"), "data-owner-name")
            ?? meta(doc, property: "og:title").map { cleanTitle($0, site: siteName) }
            ?? text(first(doc, "title")).nilIfBlank.map { cleanTitle($0, site: siteName) }
            ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let brand = ldMain.flatMap { str($0["brand"]) ?? str($0["manufacturer"]) }
            ?? attr(first(doc, "meta[itemprop=brand]"), "content")
            ?? text(first(doc, "[itemprop=brand]")).nilIfBlank
            ?? meta(doc, property: "product:brand")

        let mainImg = first(doc, "img[itemprop=image]")
        let image = ldMain.flatMap { imageURL($0["image"], base: url) }
            ?? largest(fromSrcset: attr(mainImg, "srcset"), base: url)
            ?? attr(mainImg, "src").flatMap { absolute($0, base: url) }
            ?? meta(doc, property: "og:image").flatMap { absolute($0, base: url) }

        let fromLD = ld.flatMap { ldVariants($0, base: url) }
        let fromMicrodata = microdataVariants(doc, productName: name, base: url)
        var variants = fromLD.count >= fromMicrodata.count ? fromLD : fromMicrodata
        if variants.isEmpty, let price = meta(doc, property: "product:price:amount").flatMap(Double.init) {
            variants = [ProductVariant(name: name, price: price)]
        }

        if name.isEmpty && variants.isEmpty { throw ProductPageError.notAProduct }
        return ProductInfo(name: name, brand: brand, image: image, url: url, category: .guess(from: name), variants: variants)
    }

    // MARK: JSON-LD

    private static func jsonLDProducts(_ doc: Document) -> [[String: Any]] {
        var out: [[String: Any]] = []
        for script in (try? doc.select("script[type=application/ld+json]").array()) ?? [] {
            guard let data = script.data().data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            collectProducts(json, into: &out)
        }
        return out
    }

    private static func collectProducts(_ any: Any, into out: inout [[String: Any]]) {
        if let array = any as? [Any] {
            array.forEach { collectProducts($0, into: &out) }
        } else if let obj = any as? [String: Any] {
            if types(obj).contains(where: { $0 == "Product" || $0 == "ProductGroup" }) { out.append(obj) }
            if let graph = obj["@graph"] { collectProducts(graph, into: &out) }
        }
    }

    private static func types(_ obj: [String: Any]) -> [String] {
        let raw = (obj["@type"] as? [String]) ?? [(obj["@type"] as? String)].compactMap { $0 }
        return raw.map { $0.components(separatedBy: "/").last ?? $0 }
    }

    private static func ldVariants(_ product: [String: Any], base: URL) -> [ProductVariant] {
        if let members = product["hasVariant"] as? [[String: Any]], !members.isEmpty {
            return members.map { variant(fromProduct: $0, offer: offers($0).first, fallbackName: str(product["name"]), base: base) }
        }
        let list = offers(product)
        if list.count > 1 {
            return list.map { offer in
                var v = variant(fromProduct: product, offer: offer, fallbackName: nil, base: base)
                v.name = str(offer["name"]) ?? v.name
                v.sku = str(offer["sku"]) ?? v.sku
                v.upc = gtin(offer) ?? v.upc
                v.color = str(offer["color"]) ?? (offer["itemOffered"] as? [String: Any]).flatMap { str($0["color"]) } ?? v.color
                return v
            }
        }
        let single = variant(fromProduct: product, offer: list.first, fallbackName: nil, base: base)
        let hasDetails = single.price != nil || single.upc != nil || single.sku != nil || single.color != nil
        return hasDetails ? [single] : []
    }

    private static func variant(fromProduct p: [String: Any], offer: [String: Any]?, fallbackName: String?, base: URL) -> ProductVariant {
        ProductVariant(
            sku: str(offer?["sku"]) ?? str(p["sku"]),
            name: str(p["name"]) ?? fallbackName ?? "",
            price: offer.flatMap { price($0) },
            upc: gtin(p) ?? offer.flatMap { gtin($0) },
            image: imageURL(p["image"], base: base),
            color: str(p["color"]),
            size: str(p["size"]),
            inStock: offer.flatMap { availability($0["availability"]) }
        )
    }

    private static func offers(_ obj: [String: Any]) -> [[String: Any]] {
        if let list = obj["offers"] as? [[String: Any]] { return list }
        guard let one = obj["offers"] as? [String: Any] else { return [] }
        if let inner = one["offers"] as? [[String: Any]], !inner.isEmpty { return inner } // AggregateOffer
        return [one]
    }

    private static func price(_ offer: [String: Any]) -> Double? {
        for key in ["price", "lowPrice"] {
            if let n = offer[key] as? NSNumber { return n.doubleValue }
            if let s = offer[key] as? String, let d = Double(s.filter { $0.isASCIIDigit || $0 == "." }) { return d }
        }
        if let spec = offer["priceSpecification"] as? [String: Any] { return price(spec) }
        return nil
    }

    private static func gtin(_ obj: [String: Any]) -> String? {
        for key in ["gtin12", "gtin13", "gtin14", "gtin8", "gtin", "upc"] {
            if let code = UPC.normalize(str(obj[key])) { return code }
        }
        return nil
    }

    private static func availability(_ any: Any?) -> String? {
        guard let s = str(any) else { return nil }
        switch s.components(separatedBy: "/").last ?? s {
        case "InStock", "InStoreOnly", "OnlineOnly", "LimitedAvailability": return "In stock"
        case "OutOfStock", "SoldOut", "Discontinued": return "Out of stock"
        case "PreOrder", "BackOrder": return "Backordered"
        default: return nil
        }
    }

    private static func imageURL(_ any: Any?, base: URL) -> URL? {
        if let s = any as? String { return absolute(s, base: base) }
        if let list = any as? [Any] { return list.lazy.compactMap { imageURL($0, base: base) }.first }
        if let obj = any as? [String: Any] { return imageURL(obj["url"] ?? obj["contentUrl"], base: base) }
        return nil
    }

    /// A readable string from a JSON-LD value: strings, numbers, `{ "name": … }` objects, or the first of a list.
    private static func str(_ any: Any?) -> String? {
        switch any {
        case let s as String: return s.nilIfBlank
        case let n as NSNumber: return n.stringValue
        case let obj as [String: Any]: return str(obj["name"])
        case let list as [Any]: return list.lazy.compactMap { str($0) }.first
        default: return nil
        }
    }

    // MARK: Microdata

    /// Pages that mark each color/size as its own schema.org Offer, with nested sku, price and GTIN.
    private static func microdataVariants(_ doc: Document, productName: String, base: URL) -> [ProductVariant] {
        let rows = (try? doc.select("[itemprop=offers]").array()) ?? []
        return rows.compactMap { row in
            var styles: [String: String] = [:]
            var thumb: String?
            for st in (try? row.select(".js-ordering-style").array()) ?? [] {
                let key = text(first(st, ".js-ordering-style-name"))
                let val = text(first(st, ".js-ordering-style-item-name"))
                if !key.isEmpty, !val.isEmpty { styles[key] = val }
                thumb = thumb ?? attr(st, "data-stylethumb")
            }
            let priceEl = first(row, "[itemprop=price]")
            let price = (attr(priceEl, "content") ?? text(priceEl).nilIfBlank)
                .flatMap { Double($0.filter { $0.isASCIIDigit || $0 == "." }) }
            let sku = attr(row, "data-code") ?? attr(first(row, "[itemprop=sku]"), "content") ?? text(first(row, "[itemprop=sku]")).nilIfBlank
            let upc = UPC.normalize(attr(first(row, "[itemprop^=gtin]"), "content") ?? text(first(row, "[itemprop^=gtin]")).nilIfBlank)
            guard price != nil || sku != nil || upc != nil else { return nil }
            let sizeKey = styles.keys.sorted().first { $0.range(of: "size|length|weight|count|pack", options: [.regularExpression, .caseInsensitive]) != nil }
            let rowName = text(first(row, ".js-ordering-name")).nilIfBlank ?? text(first(row, "[itemprop=name]")).nilIfBlank
            return ProductVariant(
                sku: sku,
                name: rowName ?? productName,
                price: price,
                upc: upc,
                image: thumb.flatMap { absolute($0, base: base) },
                styles: styles,
                color: styles["Color"] ?? text(first(row, "[itemprop=color]")).nilIfBlank,
                size: sizeKey.flatMap { styles[$0] },
                inStock: text(first(row, ".js-ordering-available")).nilIfBlank
                    ?? availability(attr(first(row, "[itemprop=availability]"), "href") ?? attr(first(row, "[itemprop=availability]"), "content"))
            )
        }
    }

    // MARK: HTML helpers

    private static func attr(_ el: Element?, _ name: String) -> String? {
        guard let el, el.hasAttr(name), let v = try? el.attr(name), !v.isEmpty else { return nil }
        return v
    }

    private static func text(_ el: Element?) -> String {
        (try? el?.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    private static func first(_ root: Element, _ css: String) -> Element? {
        try? root.select(css).first()
    }

    private static func meta(_ doc: Document, property: String) -> String? {
        attr(first(doc, "meta[property=\(property)]"), "content") ?? attr(first(doc, "meta[name=\(property)]"), "content")
    }

    /// "Zoom Trick Worm | Bass Shop" → "Zoom Trick Worm".
    static func cleanTitle(_ title: String, site: String?) -> String {
        var t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let site, !site.isEmpty {
            for sep in [" | ", " - ", " – ", " — ", ": "] where t.hasSuffix(sep + site) {
                t = String(t.dropLast(sep.count + site.count))
            }
        } else if let r = t.range(of: " | ", options: .backwards) {
            t = String(t[..<r.lowerBound])
        }
        return t
    }

    /// Resolves a page-relative image address. Some image servers take the width as `nw`; ask for one big enough to look sharp.
    static func absolute(_ raw: String, base: URL, width: Int = 600) -> URL? {
        guard let abs = URL(string: raw.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL,
              var c = URLComponents(url: abs, resolvingAgainstBaseURL: true) else { return nil }
        if c.scheme == "http" { c.scheme = "https" }
        if let items = c.queryItems, items.contains(where: { $0.name == "nw" }) {
            c.queryItems = items.filter { $0.name != "nw" } + [URLQueryItem(name: "nw", value: String(width))]
        }
        return c.url
    }

    static func largest(fromSrcset srcset: String?, base: URL) -> URL? {
        guard let srcset else { return nil }
        let best = srcset.split(separator: ",")
            .map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
            .compactMap { parts -> (String, Int)? in
                guard let u = parts.first else { return nil }
                return (u, parts.count > 1 ? Int(parts[1].filter(\.isASCIIDigit)) ?? 0 : 0)
            }
            .max { $0.1 < $1.1 }
        return best.flatMap { absolute($0.0, base: base) }
    }
}

/// Searches with Safari's default search engine, so the app doesn't pick a store or search provider.
nonisolated enum WebSearch {
    static func url(_ query: String) -> URL {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#"))) ?? ""
        return URL(string: "x-web-search://?\(q)")!
    }
}

nonisolated enum Net {
    /// Pages are written for phones; ask for the same HTML Safari on an iPhone would get.
    static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
}
