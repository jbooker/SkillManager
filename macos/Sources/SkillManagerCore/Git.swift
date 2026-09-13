import Foundation

struct GitRepo: Equatable {
    var root: String
    var remoteURL: String?
    var head: String?
}

enum GitError: Error, LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        }
    }
}

enum GitProcess {
    static func repo(containing path: String) -> GitRepo? {
        guard let root = try? run(["rev-parse", "--show-toplevel"], cwd: path) else { return nil }
        let remote = try? run(["remote", "get-url", "origin"], cwd: root)
        let head = try? run(["rev-parse", "HEAD"], cwd: root)
        return GitRepo(root: root, remoteURL: remote, head: head)
    }

    static func isDirty(_ root: String) -> Bool {
        let status = (try? run(["status", "--porcelain"], cwd: root)) ?? ""
        return !status.isEmpty
    }

    static func remoteHead(url: String, ref: String?) -> String? {
        let needle = (ref?.isEmpty == false) ? ref! : "HEAD"
        guard let out = try? run(["ls-remote", url, needle], cwd: nil) else { return nil }
        let line = out.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let sha = line.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return sha.isEmpty ? nil : sha
    }

    static func pull(root: String) throws -> String {
        _ = try run(["pull", "--ff-only"], cwd: root)
        return try run(["rev-parse", "HEAD"], cwd: root)
    }

    static func clone(url: String, dest: String, ref: String?) throws {
        var args = ["clone", "--depth", "1"]
        if let ref, !ref.isEmpty, !looksLikeSHA(ref) {
            args += ["--branch", ref]
        }
        args += [url, dest]
        _ = try run(args, cwd: nil)
        if let ref, looksLikeSHA(ref) {
            _ = try run(["fetch", "--depth", "1", "origin", ref], cwd: dest)
            _ = try run(["checkout", "--detach", "FETCH_HEAD"], cwd: dest)
        }
    }

    static func head(at root: String) -> String? {
        try? run(["rev-parse", "HEAD"], cwd: root)
    }

    @discardableResult
    static func run(_ args: [String], cwd: String?) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["git"] + args
        if let cwd {
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        proc.environment = env
        do {
            try proc.run()
        } catch {
            throw GitError.failed(error.localizedDescription)
        }
        proc.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let combined = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if proc.terminationStatus != 0 {
            let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.failed(message.isEmpty ? combined : message)
        }
        return combined
    }

    static func looksLikeSHA(_ value: String) -> Bool {
        let s = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count >= 7, s.count <= 40 else { return false }
        return s.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }
}
