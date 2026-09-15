# Skill Manager

A native macOS app for [Agent Skills](https://agentskills.io) (`SKILL.md` folders) across **Claude Code**, **Cursor**, **Grok**, **Codex**, **Gemini CLI**, and **OpenCode**.

The problem it solves: skills are the same format everywhere, but each harness looks in different folders. A skill in `~/.claude/skills` is invisible to Codex. A skill in `~/.agents/skills` is invisible to Claude Code. Plugin caches look like “you have a hundred skills” until you check which runtime can see them.

## What “global” means here

| Bucket | Path | Who loads it |
| --- | --- | --- |
| **Shared global** | `~/.agents/skills/` | Cursor, Grok, Codex, Gemini, OpenCode |
| Claude user | `~/.claude/skills/` | Claude, Cursor, Grok, OpenCode |
| Cursor user | `~/.cursor/skills/` | Cursor only |
| Grok user | `~/.grok/skills/` | Grok only |
| Codex user | `~/.codex/skills/` | Codex, Cursor |
| Gemini user | `~/.gemini/skills/` | Gemini only |
| OpenCode user | `~/.config/opencode/skills/` | OpenCode only |

Project copies of those folders (`.claude/skills`, `.agents/skills`, …) follow the same visibility map.

**Link everywhere** creates copies in both `~/.agents/skills` and `~/.claude/skills`, which is the combination that covers every harness in this table.

**Link** puts a skill into one of those user folders. **Unlink** takes it out of that folder only. A symlink is removed. The last real user folder is moved to `~/.config/skill-manager/archive/` instead of deleted, so you can restore it. **Mark inactive** leaves the folder in place and sets `disable-model-invocation` so models stop auto-loading it. **Delete** is permanent and asks first. Plugin caches and Cursor built-ins are never changed.

Cursor also loads plugin skills under `~/.cursor/plugins` and built-ins under `~/.cursor/skills-cursor`. **Built-in** means Cursor shipped the skill itself. **Plugin** means it arrived with a Cursor or Claude plugin package. Skill Manager will not unlink either of those copies. Link into a user folder only if you want a personal copy other harnesses can load.

## Refresh from origin

Each copy records an **origin**: git checkout, assigned GitHub repo, Cursor plugin, or built-in. The inspector shows it and offers **Refresh from source** when the origin is a git remote or a GitHub URL you assigned.

- Git checkouts (including plugin caches that still have `.git`) fast-forward with `git pull`. Local uncommitted changes are refused.
- Copies without git need a GitHub URL first (**Set GitHub source…**), then refresh clones that repo and replaces the skill folder.
- Cursor built-ins are synced by Cursor itself. Plugin caches without git are left to the harness; copy the skill into your own folder if you want to refresh it from GitHub.

Assigned origins live in `~/.config/skill-manager/config.json`.

## Load from GitHub

**Load from GitHub** (toolbar plus, or File → Load from GitHub…) clones a repo, lists every `SKILL.md` folder, and copies the ones you keep checked onto disk.

Pick the load target *before* loading:

| Target | Where it lands |
| --- | --- |
| **All harnesses** | Real copy in `~/.agents/skills`, symlink in `~/.claude/skills` (`everywhere`) |
| One harness | That harness’s user folder only (`~/.claude/skills`, `~/.cursor/skills`, …) |

A library URL loads every skill in the repo. A tree URL that points at one skill loads just that folder. Nested example `SKILL.md` files inside a skill are not treated as extra skills. Names that already exist at the destination are skipped. Each new copy records the repo as its origin so **Refresh from source** works later.

## Download

Every push to `main` publishes a versioned disk image on [GitHub Releases](https://github.com/jbooker/SkillsManager/releases/latest).

[Skill-Manager-0.1.1.dmg](https://github.com/jbooker/SkillsManager/releases/latest/download/Skill-Manager-0.1.1.dmg) — open it and drag **Skill Manager** into **Applications**.

There is no separate installer. A Mac app is already a self-contained `.app` bundle; the disk image is a wrapper with an Applications shortcut. The version comes from `VERSION` and is stamped into the app and the `.dmg` filename.

The first launch, Gatekeeper blocks the app because this build is not Apple-notarized. Click **Done** (not Move to Trash). Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to Skill Manager. Confirm **Open**. After that, double-click works as usual.

Requires macOS 14+ on Intel or Apple silicon.

## Run from source

Requires macOS 14+ and Xcode command line tools.

```bash
swift run --package-path macos SkillManager
```

That launches **Skill Manager** as a native SwiftUI app: sidebar by harness, searchable table, coverage matrix, inspector with link / unlink / archive / delete / refresh, **Load from GitHub** for libraries, and Settings for extra scan roots.

To build a `.app` and disk image locally:

```bash
bash scripts/package-macos.sh
```

Outputs land in `release/`, including `Skill-Manager-<version>.dmg`. Open `macos/Package.swift` in Xcode if you want to run or iterate from there.

## Tests

```bash
swift test --package-path macos
```

## Contributing

Open a pull request against `main`. Anyone can propose a change; only repository owners can merge. Direct pushes to `main` are blocked.

## License

MIT. See [LICENSE](LICENSE).
