#!/bin/zsh
# Builds Solitaire Slasher for the App Store and uploads it to App Store Connect (TestFlight).
#   store/release.sh [patch|minor|major] [--no-upload] [--skip-tests]
#     (no bump word)  next build number, same version: for more TestFlight builds
#     patch/minor/major  also bumps the version: needed once the current version has been released
#     --no-upload     do everything including App Store signing, send nothing, undo the bump
#     --skip-tests    skip the multiplayer race tests
# Needs: Xcode signed in to the Apple Developer account, Godot closed (it can overwrite
# export_presets.cfg), and no game running from the editor (the race tests use port 7777).
# On success it commits the version and tags it; pushing is left to you.
set -euo pipefail

ROOT=${0:A:h:h}
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
BUMP=build; UPLOAD=1; TESTS=1
for arg in "$@"; do
  case $arg in
    patch|minor|major) BUMP=$arg ;;
    --no-upload) UPLOAD=0 ;;
    --skip-tests) TESTS=0 ;;
    *) print "Unknown option: $arg"; exit 1 ;;
  esac
done

cd "$ROOT"
PRESETS=export_presets.cfg
[[ $(git branch --show-current) == main ]] || { print "Switch to main first."; exit 1; }
if [[ -n $(git status --porcelain -- . ':!export' ':!.DS_Store') ]]; then
  print "Commit your changes first, so the release matches git:"; git status --short -- . ':!export' ':!.DS_Store'; exit 1
fi
if pgrep -f "Godot.*--path $ROOT.*--editor" >/dev/null; then
  print "Close the Godot editor first: it can overwrite export_presets.cfg."; exit 1
fi

print "› Importing assets"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true

if (( TESTS )); then
  print "› Multiplayer race tests"
  for game in Solitaire Spider Sudoku; do
    tests/multiplayer/run_race.sh $game 1 | tail -2
  done
fi

# Version numbers live in the iOS export preset: short_version (1.2.3) and version (the build number)
preset() { grep "^application/$1=" $PRESETS | cut -d'"' -f2; }
set_preset() { perl -pi -e "s|^application/$1=.*|application/$1=\"$2\"|" $PRESETS; }

BACKUP=$(mktemp)
cp $PRESETS "$BACKUP"
RELEASED=0
rollback() {
  (( RELEASED )) && return
  print "› Rolling back the version and export folder"
  cp "$BACKUP" "$ROOT/$PRESETS"
  git -C "$ROOT" checkout -- export 2>/dev/null || true
}
trap rollback EXIT

VERSION=$(preset short_version); VERSION=${VERSION:-1.0.0}
BUILD=$(preset version); BUILD=${BUILD:-0}
parts=("${(@s/./)VERSION}")
case $BUMP in
  major) VERSION="$(( parts[1] + 1 )).0.0" ;;
  minor) VERSION="${parts[1]}.$(( parts[2] + 1 )).0" ;;
  patch) VERSION="${parts[1]}.${parts[2]}.$(( parts[3] + 1 ))" ;;
esac
BUILD=$(( BUILD + 1 ))
set_preset short_version "$VERSION"
set_preset version "$BUILD"
print "› Releasing $VERSION ($BUILD)"

print "› Godot release export"
# Project only: Xcode does the archive below, so it lands in the Organizer
perl -pi -e 's|^application/export_project_only=.*|application/export_project_only=true|' $PRESETS
"$GODOT" --headless --export-release iOS export/solitaireslasher.ipa 2>&1 | grep -E 'SCRIPT ERROR|Parse Error|EXPORT FAILED|ERROR: Project export' || true
perl -pi -e 's|^application/export_project_only=.*|application/export_project_only=false|' $PRESETS

# Refuse to ship the wrong thing
XCPROJ=export/solitaireslasher.xcodeproj/project.pbxproj
grep -q "MARKETING_VERSION = $VERSION;" $XCPROJ || { print "Export didn't pick up version $VERSION."; exit 1; }
if ar t export/solitaireslasher.xcframework/ios-arm64/libgodot.a | grep -q template_debug; then
  print "Export produced a debug engine build; not shipping it."; exit 1
fi

EXPORT_DIR=$(mktemp -d)
# Real releases go where Xcode's Organizer shows them
ARCHIVE=$EXPORT_DIR/test.xcarchive
(( UPLOAD )) && ARCHIVE=~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/"Solitaire Slasher $VERSION ($BUILD).xcarchive"
print "› Archiving"
xcodebuild -project export/solitaireslasher.xcodeproj -scheme solitaireslasher -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet archive

OPTIONS=$(mktemp).plist
cp store/ExportOptions.plist "$OPTIONS"
(( UPLOAD )) || plutil -replace destination -string export "$OPTIONS"
print "› $( (( UPLOAD )) && print 'Uploading to App Store Connect' || print 'Signing for the App Store (no upload)')"
EXPORT_LOG=$(mktemp)
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" \
  -exportPath "$EXPORT_DIR" -allowProvisioningUpdates > "$EXPORT_LOG" 2>&1 || true
grep -E 'error:|EXPORT SUCCEEDED|EXPORT FAILED|Upload' "$EXPORT_LOG" || true
grep -q 'EXPORT SUCCEEDED' "$EXPORT_LOG" || { print "Upload/export failed; full log: $EXPORT_LOG"; exit 1; }

# Xcode raises the build number at upload if Apple already has it; keep ours in step
if [[ -f $EXPORT_DIR/DistributionSummary.plist ]]; then
  ACTUAL=$(python3 - "$EXPORT_DIR/DistributionSummary.plist" <<'PY'
import plistlib, sys
def find(node):
    if isinstance(node, dict):
        if "buildNumber" in node: return node["buildNumber"]
        node = list(node.values())
    if isinstance(node, list):
        for item in node:
            found = find(item)
            if found: return found
print(find(plistlib.load(open(sys.argv[1], "rb"))) or "")
PY
  )
  [[ $ACTUAL == <-> ]] && (( ACTUAL > BUILD )) && BUILD=$ACTUAL && set_preset version "$BUILD"
fi

if (( ! UPLOAD )); then
  print "✔ $VERSION ($BUILD) built and signed for the App Store: $EXPORT_DIR"
  print "  Nothing was uploaded, and the version bump is undone."
  exit 0
fi

RELEASED=1
git add $PRESETS $XCPROJ export/solitaireslasher.pck
git commit -q -m "Release $VERSION ($BUILD)" -- $PRESETS $XCPROJ export/solitaireslasher.pck
git tag "v$VERSION-$BUILD"
git checkout -- export  # Back to the tracked debug engine; only this script ships release builds
print "✔ Uploaded $VERSION ($BUILD), committed and tagged v$VERSION-$BUILD (run: git push --follow-tags)."
print "  It appears in App Store Connect → TestFlight after processing (5–30 min)."
