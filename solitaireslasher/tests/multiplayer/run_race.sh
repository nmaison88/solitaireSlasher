#!/bin/zsh
# Plays a real multiplayer race between copies of the game on this Mac, then prints a summary.
#   tests/multiplayer/run_race.sh <Solitaire|Spider|Sudoku> [clients=1] [host_last|client_last]
# host_last / client_last: one player forfeits, the last player standing presses END ROUND & READY.
# Port 7777 must be free, so stop any copy of the game running from the Godot editor first.
# Runs on a temporary copy of the project; logs go to tests/multiplayer/logs/.
set -uo pipefail

ROOT=${0:A:h:h:h}
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
GAME=${1:?usage: run_race.sh <Solitaire|Spider|Sudoku> [clients] [scenario]}
CLIENTS=${2:-1}
SCENARIO=${3:-}
LOGS=$ROOT/tests/multiplayer/logs
TAG=$GAME-$CLIENTS${SCENARIO:+-$SCENARIO}
WORK=$(mktemp -d)/game
trap 'rm -rf "${WORK:h}"' EXIT

if lsof -nP -iUDP:7777 >/dev/null 2>&1; then
  echo "Port 7777 is in use. Stop the game running in the Godot editor first."
  exit 1
fi

mkdir -p "$LOGS"
rsync -a --exclude export --exclude store --exclude tests --exclude .git "$ROOT/" "$WORK/"
cp "$ROOT/tests/multiplayer/race_driver.gd" "$WORK/_tmp_mp_driver.gd"
python3 - "$WORK/scripts/Main.gd" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '\t_setup_main_menu()\n'
assert s.count(old) == 1
open(p, 'w').write(s.replace(old, old + '\tadd_child(load("res://_tmp_mp_driver.gd").new())\n', 1))
PY

cd "$WORK"
run() {  # run <log name> <driver args...>
  local log=$1; shift
  perl -e 'alarm 300; exec @ARGV' "$GODOT" --headless --path . -- "$@" "--game=$GAME" "--scenario=$SCENARIO" > "$LOGS/$TAG-$log.log" 2>&1
}
run host --role=host "--clients=$CLIENTS" &
pids=($!)
sleep 2
for i in $(seq 1 "$CLIENTS"); do
  run "client$i" --role=client "--idx=$i" &
  pids+=($!)
done
for pid in $pids; do wait $pid; done

files=("$LOGS/$TAG"-*.log)
players=$(( CLIENTS + 1 ))
errors=$(cat $files | grep -c 'SCRIPT ERROR')
finished=$(cat $files | grep -c 'MPTEST.*DONE')
round1=$(grep -h 'round1 ready=true' $files | grep -o 'SIG=[0-9-]*' | sort -u | wc -l | tr -d ' ')
round2=$(grep -h 'round2 ready=true' $files | grep -o 'SIG=[0-9-]*' | sort -u | wc -l | tr -d ' ')
false_jams=$(cat $files | grep -c 'truly_has_moves=true my_reported_status=1')
echo "$TAG: players=$players finished=$finished errors=$errors round1_deals=$round1 round2_deals=$round2 false_jams=$false_jams"
if (( finished == players && errors == 0 && round1 == 1 && round2 == 1 && false_jams == 0 )); then
  echo PASS
else
  echo "FAIL (see $LOGS)"
  exit 1
fi
