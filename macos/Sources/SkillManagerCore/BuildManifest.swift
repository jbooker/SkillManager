import Foundation

public struct BuildManifest: Equatable, Sendable {
    public struct Field: Equatable, Identifiable, Sendable {
        public var id: String { key }
        public var key: String
        public var label: String
        public var value: String

        public init(key: String, label: String, value: String) {
            self.key = key
            self.label = label
            self.value = value
        }
    }

    public var fields: [Field]
    public var prettyJSON: String

    public var detailFields: [Field] {
        fields.filter { !Self.headlineKeys.contains($0.key) }
    }

    public init(fields: [Field], prettyJSON: String) {
        self.fields = fields
        self.prettyJSON = prettyJSON
    }

    public func value(for key: String) -> String? {
        fields.first { $0.key == key }?.value
    }

    public static func loadFromBundle(_ bundle: Bundle = .main) -> BuildManifest? {
        let url = bundle.url(forResource: "BuildManifest", withExtension: "json")
            ?? bundle.url(forResource: "manifest", withExtension: "json")
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return parse(data)
    }

    public static func parse(_ data: Data) -> BuildManifest? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        guard let dict = object as? [String: Any] else { return nil }

        var fields: [Field] = []
        var seen = Set<String>()
        for key in preferredOrder {
            guard let raw = dict[key], let value = displayValue(raw) else { continue }
            seen.insert(key)
            fields.append(Field(key: key, label: label(for: key), value: value))
        }
        for key in dict.keys.sorted() where !seen.contains(key) {
            guard let value = displayValue(dict[key]!) else { continue }
            fields.append(Field(key: key, label: label(for: key), value: value))
        }
        guard !fields.isEmpty else { return nil }

        let pretty: String
        if let json = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: json, encoding: .utf8) {
            pretty = text
        } else if let text = String(data: data, encoding: .utf8) {
            pretty = text
        } else {
            pretty = fields.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        }

        return BuildManifest(fields: fields, prettyJSON: pretty)
    }

    private static let headlineKeys: Set<String> = ["version", "build"]
    private static let preferredOrder = ["version", "build", "commit", "ref", "builtAt"]

    private static func label(for key: String) -> String {
        switch key {
        case "version": return "Version"
        case "build": return "Build"
        case "commit": return "Commit"
        case "ref": return "Branch"
        case "builtAt": return "Built"
        default:
            return key
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
        }
    }

    private static func displayValue(_ raw: Any) -> String? {
        switch raw {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if let formatted = formatTimestamp(trimmed) { return formatted }
            return trimmed
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return value.boolValue ? "Yes" : "No"
            }
            return value.stringValue
        case is NSNull:
            return nil
        default:
            guard JSONSerialization.isValidJSONObject(raw),
                  let data = try? JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]),
                  let text = String(data: data, encoding: .utf8)
            else { return String(describing: raw) }
            return text
        }
    }

    private static func formatTimestamp(_ value: String) -> String? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: value) ?? {
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: value)
        }()
        guard let date else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
