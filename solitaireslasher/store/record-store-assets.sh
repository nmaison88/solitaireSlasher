#!/bin/zsh
# Renders the App Store screenshots and preview video with Godot Movie Maker.
#   store/record-store-assets.sh [shots|video]   (default: both)
# Works on a throwaway copy of the project, patched to behave like an iPhone (mobile sizes, notch
# safe area) with its own save data, so the real project and your Mac's save are never touched.
# Output: store/screenshots/6.9in (1320x2868), store/screenshots/6.3in (1206x2622) and
# store/previews/app-preview-6.9in.mp4 (886x1920, 30 fps, 15-30 s, AAC audio).
set -euo pipefail

ROOT=${0:A:h:h}
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
WHAT=${1:-all}
WORK=$(mktemp -d)/game
trap 'rm -rf "${WORK:h}"' EXIT
command -v ffmpeg >/dev/null || { echo "Missing ffmpeg (brew install ffmpeg)"; exit 1; }

rsync -a --exclude export --exclude store --exclude .git "$ROOT/" "$WORK/"
cp "$ROOT"/store/tools/*.gd "$WORK/"

python3 - "$WORK" <<'PY'
import glob, re, sys
work = sys.argv[1]
for path in glob.glob(work + "/scripts/*.gd"):
    s = open(path).read()
    s = s.replace('OS.has_feature("mobile")', 'true')
    s = s.replace('DisplayServer.get_display_safe_area()', 'Rect2i(0, 177, 1320, 2589)')  # iPhone Pro Max
    s = s.replace('DisplayServer.screen_get_size()', 'Vector2i(1320, 2868)')
    # Game clocks follow Movie Maker's fixed 30 fps time instead of real time
    s = s.replace('Time.get_ticks_msec()', '(Engine.get_process_frames() * 1000 / 30)')
    open(path, 'w').write(s)
p = work + "/scripts/Main.gd"; s = open(p).read()
s = s.replace('\t_setup_main_menu()\n', '\t_setup_main_menu()\n\tadd_child(load("res://demo_driver.gd").new())\n', 1)
open(p, 'w').write(s)
p = work + "/project.godot"; s = open(p).read()
s = s.replace('config/name="solitaireslasher"', 'config/name="solitaireslasher-store-capture"')  # Separate user:// data
s = s.replace('run/main_scene="res://scenes/Main.tscn"', 'run/main_scene="res://capture_root.tscn"')
open(p, 'w').write(s)
PY

cd "$WORK"
for name in seed_search capture_root; do
  print "[gd_scene format=3]\n\n[ext_resource type=\"Script\" path=\"res://$name.gd\" id=\"1\"]\n\n[node name=\"S\" type=\"Node\"]\nscript = ExtResource(\"1\")" > $name.tscn
done
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
SEED=$("$GODOT" --headless --path . res://seed_search.tscn 2>/dev/null | grep -m1 '^SEED' | cut -d' ' -f2)
echo "Using deal seed ${SEED:?seed search failed}"
# Each deal in a run uses the next seed, so the two Solitaire screenshots differ
perl -pi -e "s/^(\s*)local_game\.new_game\(\)\$/\$1var deal: int = get_meta(\"deals\", 0); set_meta(\"deals\", deal + 1); local_game.new_game($SEED + deal)/" scripts/MultiplayerGameManager.gd
grep -q "$SEED + deal" scripts/MultiplayerGameManager.gd || { echo "Couldn't apply the deal seed"; exit 1; }

# The small window is only Movie Maker's clock and audio track; pictures come from capture_root.gd
print "[display]\n\nwindow/size/window_width_override=270\nwindow/size/window_height_override=585\n" > override.cfg
render() {  # render <movie file> <driver args...>
  local movie=$1; shift
  perl -e 'alarm 1500; exec @ARGV' "$GODOT" --path . --write-movie "$movie" --fixed-fps 30 --disable-vsync --quit-after 4500 -- "$@" 2>&1 | grep -E 'SCRIPT ERROR|^SHOT|Done recording' || true
}

if [[ $WHAT != video ]]; then
  SHOTS=$ROOT/store/screenshots
  mkdir -p "$SHOTS/6.9in" "$SHOTS/6.3in"
  render "$WORK/shots.avi" --size=1320x2868 --mode=shots "--out=$SHOTS/6.9in"
  for file in "$SHOTS"/6.9in/*.png; do
    sips -z 2622 1206 "$file" --out "$SHOTS/6.3in/${file:t}" >/dev/null
  done
fi

if [[ $WHAT != shots ]]; then
  mkdir -p "$ROOT/store/previews"
  OUT=$ROOT/store/previews/app-preview-6.9in.mp4
  mkdir -p "$WORK/frames"
  render "$WORK/demo.avi" --size=886x1920 --mode=video "--frames=$WORK/frames"
  ffmpeg -v error -y -framerate 30 -i "$WORK/frames/f%05d.jpg" -i "$WORK/demo.avi" -map 0:v -map 1:a \
    -vf "format=yuv420p" -c:v libx264 -profile:v high -preset slow -crf 16 \
    -c:a aac -ar 44100 -ac 2 -b:a 256k -shortest -movflags +faststart "$OUT"
  duration=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT")
  echo "Saved $OUT (${duration%.*} s)"
  (( ${duration%.*} >= 15 && ${duration%.*} < 30 )) || echo "Warning: App Store previews must be 15-30 s long."
fi
