#!/usr/bin/env bash
# jameLuLu release packager: use only an already signed app and notarize the DMG.
# No upstream Objective-See credentials, unsigned artifacts or implicit bypasses.
set -euo pipefail

fail() { printf 'jameLuLu packaging: %s\n' "$*" >&2; exit 2; }

[[ "$(uname -s)" == "Darwin" ]] || fail "requires macOS"
: "${JAMELULU_DEVELOPER_ID:?Set JAMELULU_DEVELOPER_ID to a Developer ID Application certificate}"
: "${JAMELULU_TEAM_ID:?Set JAMELULU_TEAM_ID to the matching Apple Team ID}"
: "${JAMELULU_NOTARY_PROFILE:?Set JAMELULU_NOTARY_PROFILE to a configured notarytool keychain profile}"
[[ "$JAMELULU_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail "invalid Apple Team ID"

for tool in /usr/bin/codesign /usr/bin/ditto /usr/bin/hdiutil /usr/bin/xcrun /usr/bin/shasum /usr/libexec/PlistBuddy; do
  [[ -x "$tool" ]] || fail "required macOS tool is unavailable: $tool"
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="${1:-$script_dir/Release/jameLuLu.app}"
output_dir="${2:-$script_dir}"
[[ -d "$app" ]] || fail "signed app does not exist: $app"
[[ -d "$output_dir" ]] || fail "output directory does not exist: $output_dir"

app_id="io.github.roymejia2217.jamelulu.app"
extension_id="io.github.roymejia2217.jamelulu.extension"
ext="$app/Contents/Library/SystemExtensions/$extension_id.systemextension"
[[ -d "$ext" ]] || fail "embedded system extension missing"

read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$2/Contents/Info.plist"; }
[[ "$(read_plist CFBundleIdentifier "$app")" == "$app_id" ]] || fail "unexpected app identifier"
[[ "$(read_plist CFBundleIdentifier "$ext")" == "$extension_id" ]] || fail "unexpected extension identifier"
version="$(read_plist CFBundleShortVersionString "$app")"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || fail "invalid version"

for bundle in "$app" "$ext"; do
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$bundle" || fail "invalid code signature: $bundle"
  bundle_team="$(/usr/bin/codesign -dv --verbose=4 "$bundle" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
  [[ "$bundle_team" == "$JAMELULU_TEAM_ID" ]] || fail "unexpected signing team: $bundle"
done

dmg="$output_dir/jameLuLu_${version}.dmg"
[[ ! -e "$dmg" ]] || fail "refusing to overwrite existing DMG: $dmg"
stage="$(mktemp -d "${TMPDIR:-/tmp}/jamelulu-dmg.XXXXXXXX")"
release_complete=0
cleanup() {
  rm -rf -- "$stage"
  if [[ "$release_complete" -ne 1 ]]; then rm -f -- "$dmg"; fi
}
trap cleanup EXIT

/usr/bin/ditto "$app" "$stage/jameLuLu.app"
ln -s /Applications "$stage/Applications"
/usr/bin/hdiutil create -srcfolder "$stage" -volname "jameLuLu $version" -format UDZO "$dmg"
/usr/bin/codesign --timestamp --sign "$JAMELULU_DEVELOPER_ID" "$dmg"
/usr/bin/codesign --verify --verbose=2 "$dmg" || fail "invalid DMG signature"
dmg_team="$(/usr/bin/codesign -dv --verbose=4 "$dmg" 2>&1 | sed -n 's/^TeamIdentifier=//p' | head -1)"
[[ "$dmg_team" == "$JAMELULU_TEAM_ID" ]] || fail "unexpected DMG signing team"

notary_result="$(/usr/bin/xcrun notarytool submit "$dmg" --keychain-profile "$JAMELULU_NOTARY_PROFILE" --wait)"
printf '%s\n' "$notary_result"
printf '%s\n' "$notary_result" | grep -Eq '^[[:space:]]*status:[[:space:]]*Accepted[[:space:]]*$' ||
  fail "notarization was not accepted"
/usr/bin/xcrun stapler staple "$dmg"
/usr/bin/xcrun stapler validate "$dmg"
/usr/sbin/spctl -a -vv -t open --context context:primary-signature "$dmg"

release_complete=1
/usr/bin/shasum -a 256 "$dmg"
printf 'SIGNED AND NOTARIZED DMG: %s\n' "$dmg"
