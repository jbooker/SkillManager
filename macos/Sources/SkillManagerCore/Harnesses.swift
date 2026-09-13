import Foundation

public enum Harnesses {
    public static let all: [HarnessDef] = [
        HarnessDef(
            id: .claude,
            name: "Claude Code",
            shortName: "Claude",
            colorHex: "D97757",
            blurb: "Reads ~/.claude/skills and project .claude/skills. Does not read the shared ~/.agents/skills folder.",
            readsSharedAgents: false
        ),
        HarnessDef(
            id: .cursor,
            name: "Cursor",
            shortName: "Cursor",
            colorHex: "7AA2FF",
            blurb: "Reads .cursor/skills, .agents/skills, plus Claude and Codex skill dirs. Also loads plugin and built-in skills.",
            readsSharedAgents: true
        ),
        HarnessDef(
            id: .grok,
            name: "Grok",
            shortName: "Grok",
            colorHex: "D4D4D8",
            blurb: "Reads .grok/skills, ~/.agents/skills, Claude-compatible skill dirs, and extra paths from ~/.grok/config.toml.",
            readsSharedAgents: true
        ),
        HarnessDef(
            id: .codex,
            name: "Codex",
            shortName: "Codex",
            colorHex: "3ECF8E",
            blurb: "Reads .agents/skills in the repo (walked to root) and ~/.agents/skills. Also ~/.codex/skills.",
            readsSharedAgents: true
        ),
        HarnessDef(
            id: .gemini,
            name: "Gemini CLI",
            shortName: "Gemini",
            colorHex: "6EA8FE",
            blurb: "Reads .gemini/skills and the ~/.agents/skills alias. Workspace .agents/skills wins over .gemini/skills.",
            readsSharedAgents: true
        ),
        HarnessDef(
            id: .opencode,
            name: "OpenCode",
            shortName: "OpenCode",
            colorHex: "EB7AA8",
            blurb: "Reads .opencode/skills, plus Claude and agents skill dirs at user and project level.",
            readsSharedAgents: true
        ),
    ]

    public static let userLocations: [LocationRule] = [
        LocationRule(
            id: "cursor-builtin",
            label: "Cursor built-in · ~/.cursor/skills-cursor",
            scope: .builtin,
            shared: false,
            harnesses: [.cursor],
            homeRel: ".cursor/skills-cursor"
        ),
        LocationRule(
            id: "cursor-user",
            label: "User · ~/.cursor/skills",
            scope: .user,
            shared: false,
            harnesses: [.cursor],
            homeRel: ".cursor/skills"
        ),
        LocationRule(
            id: "opencode-user",
            label: "User · ~/.config/opencode/skills",
            scope: .user,
            shared: false,
            harnesses: [.opencode],
            homeRel: ".config/opencode/skills"
        ),
        LocationRule(
            id: "agents-user",
            label: "Shared global · ~/.agents/skills",
            scope: .user,
            shared: true,
            harnesses: [.cursor, .grok, .codex, .gemini, .opencode],
            homeRel: ".agents/skills"
        ),
        LocationRule(
            id: "claude-user",
            label: "User · ~/.claude/skills",
            scope: .user,
            shared: false,
            harnesses: [.claude, .cursor, .grok, .opencode],
            homeRel: ".claude/skills"
        ),
        LocationRule(
            id: "grok-user",
            label: "User · ~/.grok/skills",
            scope: .user,
            shared: false,
            harnesses: [.grok],
            homeRel: ".grok/skills"
        ),
        LocationRule(
            id: "codex-user",
            label: "User · ~/.codex/skills",
            scope: .user,
            shared: false,
            harnesses: [.codex, .cursor],
            homeRel: ".codex/skills"
        ),
        LocationRule(
            id: "gemini-user",
            label: "User · ~/.gemini/skills",
            scope: .user,
            shared: false,
            harnesses: [.gemini],
            homeRel: ".gemini/skills"
        ),
    ]

    public static let projectLocations: [LocationRule] = [
        LocationRule(
            id: "agents-project",
            label: "Project · .agents/skills",
            scope: .project,
            shared: true,
            harnesses: [.cursor, .grok, .codex, .gemini, .opencode],
            projectNeedle: "/.agents/skills/"
        ),
        LocationRule(
            id: "claude-project",
            label: "Project · .claude/skills",
            scope: .project,
            shared: false,
            harnesses: [.claude, .cursor, .grok, .opencode],
            projectNeedle: "/.claude/skills/"
        ),
        LocationRule(
            id: "cursor-project",
            label: "Project · .cursor/skills",
            scope: .project,
            shared: false,
            harnesses: [.cursor],
            projectNeedle: "/.cursor/skills/"
        ),
        LocationRule(
            id: "grok-project",
            label: "Project · .grok/skills",
            scope: .project,
            shared: false,
            harnesses: [.grok],
            projectNeedle: "/.grok/skills/"
        ),
        LocationRule(
            id: "codex-project",
            label: "Project · .codex/skills",
            scope: .project,
            shared: false,
            harnesses: [.codex, .cursor],
            projectNeedle: "/.codex/skills/"
        ),
        LocationRule(
            id: "gemini-project",
            label: "Project · .gemini/skills",
            scope: .project,
            shared: false,
            harnesses: [.gemini],
            projectNeedle: "/.gemini/skills/"
        ),
        LocationRule(
            id: "opencode-project",
            label: "Project · .opencode/skills",
            scope: .project,
            shared: false,
            harnesses: [.opencode],
            projectNeedle: "/.opencode/skills/"
        ),
    ]

    public static let projectSkillParents: Set<String> = [
        ".claude", ".cursor", ".agents", ".grok", ".codex", ".gemini", ".opencode",
    ]

    public static func userSkillDir(homeDir: String, harness: HarnessID) -> String {
        switch harness {
        case .claude: return (homeDir as NSString).appendingPathComponent(".claude/skills")
        case .cursor: return (homeDir as NSString).appendingPathComponent(".cursor/skills")
        case .grok: return (homeDir as NSString).appendingPathComponent(".grok/skills")
        case .codex: return (homeDir as NSString).appendingPathComponent(".codex/skills")
        case .gemini: return (homeDir as NSString).appendingPathComponent(".gemini/skills")
        case .opencode: return (homeDir as NSString).appendingPathComponent(".config/opencode/skills")
        }
    }

    public static func sharedAgentsDir(homeDir: String) -> String {
        (homeDir as NSString).appendingPathComponent(".agents/skills")
    }

    public static func archiveDir(homeDir: String) -> String {
        (homeDir as NSString).appendingPathComponent(".config/skill-manager/archive")
    }

    public static func userSkillDir(homeDir: String, homeRel: String) -> String {
        let parts = homeRel.split(separator: "/").map(String.init)
        return ([homeDir] + parts).reduce("") { acc, part in
            acc.isEmpty ? part : (acc as NSString).appendingPathComponent(part)
        }
    }
}
