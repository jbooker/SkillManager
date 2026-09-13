#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

skip_tests=false
for arg in "$@"; do
  case "$arg" in
    --skip-tests) skip_tests=true ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--skip-tests]" >&2
      exit 1
      ;;
  esac
done

version="${APP_VERSION:-$(tr -d '[:space:]' < "$root/VERSION")}"
if [[ -z "$version" ]]; then
  echo "VERSION is empty." >&2
  exit 1
fi

if [[ -n "${APP_BUILD:-}" ]]; then
  build="$APP_BUILD"
elif git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  build="$(git -C "$root" rev-list --count HEAD)"
else
  build="1"
fi

if [[ "$skip_tests" != true ]]; then
  swift test --package-path macos
fi

swift build -c release --package-path macos --product SkillManager --triple arm64-apple-macosx
swift build -c release --package-path macos --product SkillManager --triple x86_64-apple-macosx

arm_bin="$(swift build -c release --package-path macos --triple arm64-apple-macosx --show-bin-path)/SkillManager"
x86_bin="$(swift build -c release --package-path macos --triple x86_64-apple-macosx --show-bin-path)/SkillManager"
if [[ ! -x "$arm_bin" || ! -x "$x86_bin" ]]; then
  echo "Missing release binaries:" >&2
  echo "  arm64: $arm_bin" >&2
  echo "  x86_64: $x86_bin" >&2
  exit 1
fi

app="$root/release/Skill Manager.app"
dmg_path="$root/release/Skill-Manager-${version}.dmg"

rm -rf "$app"
rm -f "$root"/release/*.dmg "$root"/release/*.zip
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

lipo -create -output "$app/Contents/MacOS/SkillManager" "$arm_bin" "$x86_bin"
chmod +x "$app/Contents/MacOS/SkillManager"
lipo -info "$app/Contents/MacOS/SkillManager"

cp "$root/macos/Info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

python3 - "$app/Contents/Resources/BuildManifest.json" "$version" "$build" "$root" <<'PY'
import json, os, subprocess, sys
from datetime import datetime, timezone

path, version, build, root = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def git(*args):
    try:
        return subprocess.check_output(
            ["git", "-C", root, *args],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return ""

sha = os.environ.get("GITHUB_SHA") or git("rev-parse", "HEAD")
commit = sha[:7] if sha else ""
ref = os.environ.get("GITHUB_REF_NAME") or git("rev-parse", "--abbrev-ref", "HEAD")
if ref in ("", "HEAD"):
    ref = ""

manifest = {
    "version": version,
    "build": str(build),
    "commit": commit,
    "ref": ref,
    "builtAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
manifest = {key: value for key, value in manifest.items() if value}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY

if [[ -f "$root/build/icon.png" ]]; then
  iconset="$root/build/SkillManager.iconset"
  rm -rf "$iconset"
  mkdir -p "$iconset"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$root/build/icon.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s * 2))" "$((s * 2))" "$root/build/icon.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
  cp "$app/Contents/Resources/AppIcon.icns" "$root/macos/AppIcon.icns" 2>/dev/null || true
elif [[ -f "$root/macos/AppIcon.icns" ]]; then
  cp "$root/macos/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep -s - "$app" >/dev/null

stage="$(mktemp -d)"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Skill Manager $version" -srcfolder "$stage" -ov -format UDZO "$dmg_path"
rm -rf "$stage"

echo "Version $version ($build)"
echo "Built $app"
echo "Disk image $dmg_path"
