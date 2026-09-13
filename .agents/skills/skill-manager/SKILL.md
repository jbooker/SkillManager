---
name: skill-manager
description: Inventory and manage Agent Skills across Claude, Cursor, Grok, Codex, Gemini, and OpenCode. Use when the user asks which skills are installed, how to make a skill global, how to load a GitHub skill library, or how to unlink, archive, or delete one.
---

# Skill Manager

This repository is a local skill inventory. Prefer the native Mac app (`swift run --package-path macos SkillManager`) over guessing filesystem paths.

## When to use

- User wants to know which skills exist, per harness or globally
- User wants to promote or symlink a skill into another harness folder
- User wants to unlink, archive, or delete a skill from a harness or from shared global
- User wants to refresh a skill from GitHub or its git remote
- User wants to load skills from a GitHub library into all harnesses or one harness
- User is confused why Claude / Cursor / Grok / Codex do not share the same skill list

## App

Run from this repo:

```bash
swift run --package-path macos SkillManager
```

The SwiftUI app has a sidebar by harness, a searchable table, a coverage matrix, and an inspector for link / unlink / archive / delete / refresh. **Load from GitHub** clones a library and copies selected skills into a harness folder. Settings adds extra scan roots.

## Visibility rules (do not invent others)

- Shared global `~/.agents/skills`: Cursor, Grok, Codex, Gemini, OpenCode. Not Claude Code.
- `~/.claude/skills`: Claude, Cursor, Grok, OpenCode.
- `~/.cursor/skills`: Cursor only.
- Cursor built-ins `~/.cursor/skills-cursor`: Cursor ships these. Not unlinkable.
- Plugin caches `~/.cursor/plugins` and `~/.claude/plugins`: arrived with a plugin. Not unlinkable.
- To cover every harness, symlink into both `~/.agents/skills` and `~/.claude/skills` (`everywhere`).

## Load from a GitHub library

- **Load** copies `SKILL.md` folders out of a git repo into a harness load path. It does not leave a clone of the library on disk.
- Paste a repo URL, `owner/repo`, or a URL that points at one skill (`…/tree/main/skills/tdd`). **Find skills** lists what would be loaded. Uncheck anything to skip.
- **All harnesses** copies into `~/.agents/skills` and links `~/.claude/skills` (`everywhere`). A specific harness copies only into that harness’s user folder.
- Each loaded copy records the library as its origin so **Refresh** can pull later updates.
- A skill folder that already exists at the destination is left alone.

## Unlink, archive, inactive, delete

- **Unlink** (CLI: `unload`) removes one copy from a user skill folder. A symlink is removed. If that copy is the last real user folder, it is archived (not deleted). If other harnesses still have a symlink to it, the folder is moved onto that remaining symlink. The inspector shows **Link** or **Unlink** per folder, not both.
- **Archive** removes every user-level copy and keeps one folder at `~/.config/skill-manager/archive/<name>`. Restore puts it back. Archived skills are not loaded by any harness.
- **Inactive** writes `disable-model-invocation: true` so models stop auto-loading the skill. The folder stays in place.
- **Delete** permanently removes user copies and any archive. Requires confirmation. Plugin caches and Cursor built-ins are never changed. Project skill folders are left in the repo.

## Refresh

- **Origin** is where the skill came from (git remote, assigned GitHub URL, plugin cache, Cursor built-in).
- **Refresh** replaces the local folder with the origin's current contents. Git checkouts `git pull --ff-only`. Assigned GitHub URLs are cloned and copied over the skill folder.
- Copies without git need **Set GitHub source…** in the inspector before they can refresh.
- Built-ins and plugin caches without git are not refreshed here.
