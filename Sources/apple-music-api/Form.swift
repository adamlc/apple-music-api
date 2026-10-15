import Foundation

/// Parses `application/x-www-form-urlencoded` text (`a=1&b=two%20words`; `+` is a space).
func parseForm(_ text: String) -> [String: String] {
    var values: [String: String] = [:]
    for pair in text.split(separator: "&") {
        let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        func decode(_ s: Substring) -> String {
            let spaced = s.replacingOccurrences(of: "+", with: " ")
            return spaced.removingPercentEncoding ?? spaced
        }
        values[decode(parts[0])] = parts.count > 1 ? decode(parts[1]) : ""
    }
    return values
}

/// Request fields as Home Assistant and `curl -d` send them: from the body, falling back to the
/// query string for any field the body doesn't have.
func requestValues(body: String, query: String?) -> [String: String] {
    parseForm(query ?? "").merging(parseForm(body)) { _, fromBody in fromBody }
}

func parseBool(_ s: String?) -> Bool? {
    switch s?.lowercased() {
    case "true", "1", "yes", "on": return true
    case "false", "0", "no", "off": return false
    default: return nil
    }
}
