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
zip_path="$root/release/Skill-Manager-macos.zip"
dmg_path="$root/release/Skill-Manager-macos.dmg"

rm -rf "$app"
rm -f "$zip_path" "$dmg_path"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

lipo -create -output "$app/Contents/MacOS/SkillManager" "$arm_bin" "$x86_bin"
chmod +x "$app/Contents/MacOS/SkillManager"
lipo -info "$app/Contents/MacOS/SkillManager"

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
elif [[ -f "$root/macos/AppIcon.icns" ]]; then
  cp "$root/macos/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
fi

codesign --force --deep -s - "$app" >/dev/null

ditto -c -k --keepParent "$app" "$zip_path"

stage="$(mktemp -d)"
cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Skill Manager" -srcfolder "$stage" -ov -format UDZO "$dmg_path"
rm -rf "$stage"

echo "Built $app"
echo "Zipped $zip_path"
echo "Disk image $dmg_path"
