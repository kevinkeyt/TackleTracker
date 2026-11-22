import Foundation

nonisolated enum UPC {
    /// UPC-A (12), EAN-13 and GTIN-14 of the same product differ only by leading zeros, so store digits without them.
    static func normalize(_ code: String?) -> String? {
        let digits = (code ?? "").filter(\.isASCIIDigit)
        let trimmed = digits.drop(while: { $0 == "0" })
        return trimmed.isEmpty ? nil : String(trimmed)
    }

    /// UPC-E is the short code on small packages; stores and product pages list the full UPC-A.
    static func expandUPCE(_ code: String) -> String {
        let c = Array(code)
        guard c.count == 8, c.allSatisfy(\.isASCIIDigit), c[0] == "0" || c[0] == "1" else { return code }
        let (n, d1, d2, d3, d4, d5, d6, check) = (c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7])
        let body: String
        switch d6 {
        case "0", "1", "2": body = "\(n)\(d1)\(d2)\(d6)0000\(d3)\(d4)\(d5)"
        case "3": body = "\(n)\(d1)\(d2)\(d3)00000\(d4)\(d5)"
        case "4": body = "\(n)\(d1)\(d2)\(d3)\(d4)00000\(d5)"
        default: body = "\(n)\(d1)\(d2)\(d3)\(d4)\(d5)0000\(d6)"
        }
        return body + String(check)
    }

    /// What someone typed into the UPC box: digits only, with an 8-digit UPC-E expanded.
    static func fromTyped(_ text: String) -> String? {
        let digits = text.filter(\.isASCIIDigit)
        guard digits.count >= 6 else { return nil }
        return digits.count == 8 ? expandUPCE(digits) : digits
    }
}

extension Character {
    nonisolated var isASCIIDigit: Bool { isASCII && isNumber }
}
