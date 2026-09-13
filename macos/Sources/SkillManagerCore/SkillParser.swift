import Foundation
import Yams

public enum SkillParser {
    private static let frontmatter = try! NSRegularExpression(
        pattern: "^---[ \\t]*\\r?\\n([\\s\\S]*?)\\r?\\n---[ \\t]*\\r?\\n?([\\s\\S]*)$",
        options: []
    )

    public static func parse(content: String, folderName: String) -> ParseResult {
        var errors: [String] = []
        var normalized = content
        if normalized.hasPrefix("\u{FEFF}") {
            normalized.removeFirst()
        }
        normalized = normalized.replacingOccurrences(of: "\r\n", with: "\n")

        var raw: [String: Any] = [:]
        var body = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(normalized.startIndex..., in: normalized)

        if let match = frontmatter.firstMatch(in: normalized, options: [], range: range),
           let yamlRange = Range(match.range(at: 1), in: normalized),
           let bodyRange = Range(match.range(at: 2), in: normalized)
        {
            body = String(normalized[bodyRange])
            let yaml = String(normalized[yamlRange])
            do {
                let loaded = try Yams.load(yaml: yaml)
                if let dict = stringKeyedDict(loaded) {
                    raw = dict
                } else if loaded != nil {
                    errors.append("invalid-frontmatter")
                }
            } catch {
                errors.append("invalid-frontmatter")
            }
        } else {
            errors.append("missing-frontmatter")
        }

        let nameFromFm = stringifyScalar(raw["name"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let name = normalizeSkillName(nameFromFm).nilIfEmpty
            ?? normalizeSkillName(folderName).nilIfEmpty
            ?? folderName
        if nameFromFm.isEmpty {
            errors.append("missing-name")
        } else if nameFromFm != folderName {
            errors.append("name-folder-mismatch")
        }

        let description = stringifyScalar(raw["description"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if description.isEmpty {
            errors.append("missing-description")
        }

        let whenToUse = stringifyScalar(raw["when-to-use"] ?? raw["when_to_use"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let license = stringifyScalar(raw["license"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let compatibility = stringifyScalar(raw["compatibility"]).trimmingCharacters(in: .whitespacesAndNewlines)

        let meta = SkillMeta(
            name: name,
            description: description,
            disableModelInvocation: asBool(raw["disable-model-invocation"] ?? raw["disable_model_invocation"]),
            userInvocable: {
                if raw["user-invocable"] == nil && raw["user_invocable"] == nil { return nil }
                return asBool(raw["user-invocable"] ?? raw["user_invocable"])
            }(),
            paths: asStringList(raw["paths"] ?? raw["globs"]),
            whenToUse: whenToUse,
            license: license,
            compatibility: compatibility,
            metadata: asStringMap(raw["metadata"])
        )

        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("empty-body")
        }

        return ParseResult(meta: meta, body: body, errors: errors)
    }

    /// Insert or strip `disable-model-invocation` while keeping the rest of the file intact.
    public static func patchDisableModelInvocation(content: String, inactive: Bool) -> String {
        var text = content
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        let regex = try! NSRegularExpression(pattern: "(?m)^disable[-_]model[-_]invocation:[^\\n]*\\n?")
        let range = NSRange(text.startIndex..., in: text)
        text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        guard inactive else { return text }

        if let open = text.range(of: "---") {
            var idx = open.upperBound
            if idx < text.endIndex, text[idx] == "\n" {
                idx = text.index(after: idx)
            }
            return String(text[..<idx]) + "disable-model-invocation: true\n" + String(text[idx...])
        }
        return "---\ndisable-model-invocation: true\n---\n" + text
    }

    public static func normalizeSkillName(_ value: String) -> String {
        var s = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        s = s.replacingOccurrences(of: "[_\\s]+", with: "-", options: .regularExpression)
        s = s.replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s
    }

    public static func stringifyScalar(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue ? "true" : "false"
            }
            return n.stringValue
        }
        if let b = value as? Bool { return b ? "true" : "false" }
        if let i = value as? Int { return String(i) }
        if let d = value as? Double { return String(d) }
        return ""
    }

    public static func asBool(_ value: Any?) -> Bool {
        if let b = value as? Bool { return b }
        if let s = value as? String {
            return s == "true" || s == "yes"
        }
        if let n = value as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue }
            return n.intValue == 1
        }
        if let i = value as? Int { return i == 1 }
        return false
    }

    public static func asStringList(_ value: Any?) -> [String] {
        if let arr = value as? [Any] {
            return arr.map { stringifyScalar($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let s = value as? String {
            return s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }

    public static func asStringMap(_ value: Any?) -> [String: String] {
        guard let dict = stringKeyedDict(value) else { return [:] }
        var out: [String: String] = [:]
        for (key, val) in dict {
            let s = stringifyScalar(val)
            if !s.isEmpty {
                out[key] = s
            } else if !(val is NSNull) {
                out[key] = String(describing: val)
            }
        }
        return out
    }

    private static func stringKeyedDict(_ value: Any?) -> [String: Any]? {
        if let d = value as? [String: Any] { return d }
        if let d = value as? NSDictionary {
            var out: [String: Any] = [:]
            for (key, val) in d {
                if let ks = key as? String { out[ks] = val }
            }
            return out
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
