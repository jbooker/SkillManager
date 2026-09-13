# Skill Manager

Inventory of Agent Skills (`SKILL.md` folders) across Claude, Cursor, Grok, Codex, Gemini, and OpenCode.

## Language

**Origin**:
The upstream a skill was installed from — a git remote, an assigned GitHub repo, a harness plugin cache, or a Cursor built-in.
_Avoid_: source (collides with symlink source path)

**Refresh**:
Replacing a local skill folder with the current contents of its origin.
_Avoid_: update, sync, pull (those are how, not the domain action)

**Assigned origin**:
A GitHub or git URL the user recorded for a copy that has no local `.git`.
_Avoid_: metadata, provenance

**Load**:
Copying SKILL.md folders from a GitHub library into a harness load path.
_Avoid_: install, import, add (those are how, not the domain action)

**Library**:
A git repo that contains one or more SKILL.md folders.
_Avoid_: catalog, registry, marketplace

**Load target**:
Where new copies land — all harnesses (`everywhere`) or one harness user folder.
_Avoid_: destination, install path
