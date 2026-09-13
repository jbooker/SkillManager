import Foundation

public enum SkillUsageScanner {
    private static let skillFilePattern = try! NSRegularExpression(
        pattern: #"(?:^|["'\\s/=])(?:[A-Za-z]:)?(?:/[^"'\\s]*?)?/([^/"'\\s]+)/SKILL\.md"#,
        options: .caseInsensitive
    )
    private static let jsonPathPattern = try! NSRegularExpression(
        pattern: #""path"\s*:\s*"([^"]*SKILL\.md)""#,
        options: .caseInsensitive
    )
    private static let invokedNamePattern = try! NSRegularExpression(
        pattern: #""name"\s*:\s*"([^"]+)""#
    )
    private static let isoFractional = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let isoBasic = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let cursorTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE, MMM d, yyyy, h:mm a"
        formatter.timeZone = .current
        return formatter
    }()

    public static func defaultRoots(homeDir: String) -> [String] {
        [
            (homeDir as NSString).appendingPathComponent(".cursor/projects"),
            (homeDir as NSString).appendingPathComponent(".claude/projects"),
        ]
    }

    public static func scan(homeDir: String, extraRoots: [String] = []) -> [String: SkillUsage] {
        let roots = defaultRoots(homeDir: homeDir) + extraRoots
        var sessions: [(Set<String>, Date)] = []
        for root in roots {
            collectTranscripts(in: root) { url in
                if let session = scanFile(at: url) {
                    sessions.append(session)
                }
            }
        }
        return aggregate(sessions)
    }

    public static func aggregate(_ sessions: [(Set<String>, Date)]) -> [String: SkillUsage] {
        var datesBySkill: [String: [Date]] = [:]
        for (names, date) in sessions {
            for name in names {
                datesBySkill[name, default: []].append(date)
            }
        }
        var out: [String: SkillUsage] = [:]
        for (name, dates) in datesBySkill {
            let sorted = dates.sorted()
            out[name] = SkillUsage(sessionCount: sorted.count, lastUsed: sorted.last, dates: sorted)
        }
        return out
    }

    public static func session(fromLines lines: [String], fileDate: Date) -> (names: Set<String>, date: Date)? {
        var names = Set<String>()
        var latest = fileDate
        var foundTimestamp = false
        for line in lines {
            if let stamped = timestamp(in: line) {
                if !foundTimestamp || stamped > latest {
                    latest = stamped
                }
                foundTimestamp = true
            }
            if line.contains("invoked_skills") {
                names.formUnion(namesFromInvokedSkills(line))
            } else if isAssistantLine(line) {
                names.formUnion(namesFromAssistantLine(line))
            }
        }
        names.remove("unknown")
        guard !names.isEmpty else { return nil }
        return (names, latest)
    }

    public static func namesFromAssistantLine(_ line: String) -> Set<String> {
        var names = Set<String>()
        for match in jsonPathPattern.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
            guard let range = Range(match.range(at: 1), in: line) else { continue }
            names.formUnion(skillNames(inPath: String(line[range])))
        }
        return names
    }

    public static func namesFromInvokedSkills(_ line: String) -> Set<String> {
        guard let start = line.range(of: "invoked_skills") else { return [] }
        let rest = String(line[start.lowerBound...])
        var names = Set<String>()
        let ns = rest as NSString
        for match in invokedNamePattern.matches(in: rest, range: NSRange(location: 0, length: ns.length)) {
            let raw = ns.substring(with: match.range(at: 1))
            let normalized = SkillParser.normalizeSkillName(raw)
            if !normalized.isEmpty {
                names.insert(normalized)
            }
        }
        names.formUnion(skillNames(inText: rest))
        return names
    }

    public static func timestamp(in line: String) -> Date? {
        if let iso = firstCapture(in: line, pattern: "\"timestamp\"\\s*:\\s*\"([^\"]+)\"") {
            if let date = isoFractional.date(from: iso) ?? isoBasic.date(from: iso) {
                return date
            }
        }
        if let raw = firstCapture(in: line, pattern: "<timestamp>([^<]+)</timestamp>") {
            var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let paren = cleaned.firstIndex(of: "(") {
                cleaned = String(cleaned[..<paren]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let date = cursorTimestamp.date(from: cleaned) {
                return date
            }
        }
        return nil
    }

    public static func relativeString(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let startNow = calendar.startOfDay(for: now)
        let startThen = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startThen, to: startNow).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "1d ago" }
        if days < 14 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 10 { return "\(weeks)w ago" }
        let months = days / 30
        if months < 18 { return "\(months)mo ago" }
        return "\(max(1, days / 365))y ago"
    }

    public static func scanFile(at url: URL) -> (names: Set<String>, date: Date)? {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fileDate = ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? Date()
        return session(fromLines: contents.split(whereSeparator: \.isNewline).map(String.init), fileDate: fileDate)
    }

    private static func isAssistantLine(_ line: String) -> Bool {
        line.contains("\"role\":\"assistant\"") || line.contains("\"type\":\"assistant\"")
    }

    private static func skillNames(inPath path: String) -> Set<String> {
        let posix = path.replacingOccurrences(of: "\\", with: "/")
        if posix.contains("node_modules") { return [] }
        guard posix.lowercased().hasSuffix("skill.md") else { return [] }
        let parent = URL(fileURLWithPath: posix).deletingLastPathComponent().lastPathComponent
        let normalized = SkillParser.normalizeSkillName(parent)
        return normalized.isEmpty ? [] : [normalized]
    }

    private static func skillNames(inText text: String) -> Set<String> {
        var names = Set<String>()
        let ns = text as NSString
        for match in skillFilePattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let folder = ns.substring(with: match.range(at: 1))
            if text.contains("node_modules") { continue }
            let normalized = SkillParser.normalizeSkillName(folder)
            if !normalized.isEmpty {
                names.insert(normalized)
            }
        }
        return names
    }

    private static func firstCapture(in line: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges > 1
        else { return nil }
        return ns.substring(with: match.range(at: 1))
    }

    private static func collectTranscripts(in root: String, visit: (URL) -> Void) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { return }
        let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension.lowercased() == "jsonl" {
                visit(url)
            }
        }
    }
}
