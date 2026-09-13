#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift test --package-path macos
swift build -c release --package-path macos --product SkillManager

bin="$(swift build -c release --package-path macos --show-bin-path)/SkillManager"
app="$root/release/Skill Manager.app"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

cp "$bin" "$app/Contents/MacOS/SkillManager"
chmod +x "$app/Contents/MacOS/SkillManager"
cp "$root/macos/Info.plist" "$app/Contents/Info.plist"
printf 'APPL????' > "$app/Contents/PkgInfo"

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
fi

codesign --force --deep -s - "$app" >/dev/null

echo "Built $app"
