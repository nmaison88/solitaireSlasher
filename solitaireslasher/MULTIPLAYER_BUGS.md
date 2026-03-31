# Multiplayer Bug Fix Plan

Bugs identified via static analysis and manual testing of the Solitaire / Spider / Sudoku multiplayer system.
Work top-to-bottom — Critical bugs break the core loop and should be fixed first.

---

## CRITICAL

### [✓] C1 — `race_ended` signal fires 2–3 times per game end

- **Files:** `MultiplayerGameManager.gd`
- **Functions:** `_on_local_game_completed()`, `_on_race_completed()`, `_end_multiplayer_race()`
- **Root cause:** `_on_local_game_completed` calls `_end_multiplayer_race()` (emits `race_ended`), then broadcasts `RACE_COMPLETE`. When that broadcast echo arrives back, `_on_race_completed()` fires and calls `_end_multiplayer_race()` again. The signal fires 2–3 times per game end.
- **Symptom:** Multiple stacked ready-screen panels; `_start_new_round()` called multiple times.
- **Fix:** Add a `_race_ended` bool guard in `_end_multiplayer_race()`. Set it `true` on first call, return early on subsequent calls. Reset in `_start_new_round()`.

---

### [✓] C2 — Sudoku multiplayer win is silently dropped

- **Files:** `Main.gd`
- **Function:** `_on_multiplayer_sudoku_completed()`
- **Root cause:** The function shows a status label and plays a sound, but never calls `MultiplayerGameManager.forfeit_player()` / `report_race_completion()`. There is a TODO comment confirming this is unimplemented.
- **Symptom:** Opponent is stuck playing forever. Ready screen never appears. Round can never end cleanly.
- **Fix:** Call `MultiplayerGameManager.report_race_completion()` (or equivalent) inside `_on_multiplayer_sudoku_completed()`. Mirror the same call pattern used in the Solitaire completion handler.

---

### [✓] C3 — Sudoku game-over (0 lives) in multiplayer is silently dropped

- **Files:** `Main.gd`
- **Function:** `_on_multiplayer_sudoku_game_over()`
- **Root cause:** Same as C2. Shows overlay, but never updates multiplayer state or broadcasts anything.
- **Symptom:** Opponent never receives notification. No transition. Opponent stuck.
- **Fix:** Call `MultiplayerGameManager.forfeit_player()` inside `_on_multiplayer_sudoku_game_over()`, same as how Solitaire handles a jammed state.

---

## HIGH

### [✓] H1 — `race_ended` emitted with inconsistent arguments

- **Files:** `MultiplayerGameManager.gd`
- **Callsites:** Lines ~229, ~250, ~262, ~421
- **Root cause:** Four different callsites emit `race_ended(winner_id, winner_name, time)` with different payloads — some pass empty `winner_name` and `0.0` time, one passes real data.
- **Symptom:** "Who won" UI always shows blank name and zero time.
- **Fix:** Funnel all emissions through `_end_multiplayer_race()` exclusively. Remove the direct `race_ended.emit()` calls at lines ~250 and ~229. Ensure `_end_multiplayer_race()` always resolves a real winner name before emitting.

---

### [✓] H2 — Host calls `NetworkManager.host_game()` twice on startup

- **Files:** `Main.gd`, `MultiplayerGameManager.gd`
- **Functions:** `Main._on_host_game()`, `MultiplayerGameManager.host_multiplayer_game()`
- **Root cause:** `Main._on_host_game()` calls `NetworkManager.host_game()` directly, then `_show_multiplayer_lobby()` → `lobby.setup_as_host()` → `MultiplayerGameManager.host_multiplayer_game()` calls it again. The first ENet server is silently discarded; stale player IDs accumulate.
- **Fix:** Remove the direct `NetworkManager.host_game()` call from `Main._on_host_game()`. Let `MultiplayerGameManager.host_multiplayer_game()` be the sole entry point.

---

### [✓] H3 — Client `local_player_id` read before handshake completes

- **Files:** `NetworkManager.gd`
- **Function:** `join_game()`
- **Root cause:** `local_player_id = multiplayer.get_unique_id()` is called immediately after `create_client()`. The handshake has not completed; the ID returned is always `1` (default). This collides with the host's own ID. All ready/status tracking on both sides uses the wrong ID.
- **Fix:** Remove `local_player_id` assignment from `join_game()`. Move it into `_on_connected_to_server()` where the handshake is complete and `get_unique_id()` returns the real peer ID.

---

### [✓] H4 — Disconnected player mid-game never removed from `player_statuses`

- **Files:** `MultiplayerGameManager.gd`, `NetworkManager.gd`
- **Function:** `MultiplayerGameManager` (no handler for `player_disconnected` signal)
- **Root cause:** `NetworkManager` removes the peer from `players` on disconnect and emits `player_disconnected`. `MultiplayerGameManager` does not listen to this signal. `player_statuses` retains the entry as `PLAYING` forever, so `_check_last_player_standing` never fires and the remaining player is stuck.
- **Fix:** Connect `NetworkManager.player_disconnected` in `MultiplayerGameManager`. In the handler, call `forfeit_player(disconnected_id)` to mark them as jammed and trigger the normal end-of-race flow.

---

### [✓] H5 — Both players finishing simultaneously double-ends the race

- **Files:** `MultiplayerGameManager.gd`
- **Functions:** `_on_local_game_completed()`, `_on_race_completed()`
- **Root cause:** If both players complete near-simultaneously, the host fires `_end_multiplayer_race()` for itself, then receives the client's `RACE_COMPLETE` and fires it again. Two `RACE_ENDED` broadcasts go out.
- **Fix:** The `_race_ended` guard added in C1 handles this. Once the flag is set, the second call returns early.

---

### [✓] H6 — `game_settings` never cleared between sessions

- **Files:** `NetworkManager.gd`
- **Function:** `leave_game()`
- **Root cause:** `game_settings` is only overwritten when new settings arrive. When a player leaves and joins a different session, the old `mirror_mode` setting from the previous game persists.
- **Symptom:** Mirror mode applied incorrectly on the second session.
- **Fix:** Add `game_settings = {}` to `NetworkManager.leave_game()`.

---

### [✓] H7 — Forfeit only disables the Solitaire board, not the Sudoku board

- **Files:** `Main.gd`
- **Function:** `_on_forfeit_pressed()`
- **Root cause:** The forfeit handler sets `_board.mouse_filter = MOUSE_FILTER_IGNORE` (Solitaire board) but never touches `_sudoku_board`. Players can continue entering numbers after forfeiting.
- **Fix:** Add `_sudoku_board.mouse_filter = Control.MOUSE_FILTER_IGNORE` alongside the existing `_board` line, guarded by `if _current_game_type == "Sudoku"`.

---

## MEDIUM

### [✓] M1 — Race condition: `race_started` may fire before Main.gd connects its handler

- **Files:** `Main.gd`, `MultiplayerGameManager.gd`
- **Root cause:** On the host, `start_multiplayer_race()` → `start_race()` → `race_started.emit()` all happen synchronously before `Main._setup_multiplayer_game()` has finished connecting signals. The host relies on a fallback `if local_game` check; clients have no such fallback.
- **Fix:** In `_setup_multiplayer_game()`, connect to `race_started` before calling anything that could trigger it. Add a deferred call or check `local_game` validity on the client path after mirror data arrives.

---

### [✓] M2 — `_check_all_players_ready` fires with 1 player if opponent disconnects during ready phase

- **Files:** `MultiplayerGameManager.gd`
- **Function:** `_check_all_players_ready()`
- **Root cause:** If the opponent disconnects after the race ends but before ready-up, `total_players` drops to 1. The host's own ready status triggers `all_ready = true` and immediately starts a new round with no opponent.
- **Fix:** Add a minimum-player guard: `if total_players < 2: return`.

---

### [✓] M3 — `local_player_finished` set after `race_ended` emitted, not before

- **Files:** `MultiplayerGameManager.gd`
- **Function:** `_on_race_completed()`
- **Root cause:** `local_player_finished = true` is assigned at line ~253, *after* `race_ended.emit()` at line ~250. Re-entrant calls during signal emission are not guarded.
- **Fix:** Set `local_player_finished = true` at the top of `_on_race_completed()`, before any signal emission.

---

### [✓] M4 — `discover_games()` busy-waits on main thread for 3 seconds

- **Files:** `NetworkManager.gd`
- **Function:** `discover_games()`
- **Root cause:** Uses a `while` loop on wall-clock time — blocks rendering and input for 3 seconds. On mobile this can trigger OS termination.
- **Fix:** Replace with a `Timer` node or `await get_tree().create_timer(3.0).timeout` to yield control back to the engine.

---

### [✓] M5 — `_broadcast_session` leaks a UDP socket every 2 seconds

- **Files:** `NetworkManager.gd`
- **Function:** `_broadcast_session()`
- **Root cause:** `PacketPeerUDP.new()` is called inside the function on every timer tick and never closed.
- **Fix:** Promote the `PacketPeerUDP` to a class member, instantiate once in `_ready()` or `host_game()`, and close it in `leave_game()`.

---

### [✓] M6 — Solitaire mirror data double-applied due to indentation error

- **Files:** `MultiplayerGameManager.gd`
- **Function:** `receive_mirror_data()`
- **Root cause:** The `if _pending_mirror_data.has("mirror_data"):` block at line ~489 is at the same indentation as the preceding `else:`, not inside it. After the `else` block stores the mirror data, execution falls through and immediately calls `local_game.new_game_mirror()` again. `race_started` is emitted twice.
- **Fix:** Fix the indentation so the mirror application block is nested inside the correct branch, or restructure with explicit `if/elif/else`.

---

### [✓] M7 — "Last player standing" has a notification race window

- **Files:** `MultiplayerGameManager.gd`
- **Function:** `_check_last_player_standing()`
- **Root cause:** The `PLAYER_STATUS` broadcast for the forfeiting player may arrive at the opponent after a delay. `_check_last_player_standing` only fires if the local player is the last one standing. There is a window where neither player triggers the notification.
- **Fix:** Also call `_check_last_player_standing()` inside `receive_player_status()` on the remote side, not just inside `forfeit_player()`.

---

### [✓] M9 — `_on_back_to_menu_pressed` bypasses `leave_game()`

- **Files:** `Main.gd`
- **Function:** `_on_back_to_menu_pressed()`
- **Root cause:** Directly sets `NetworkManager.is_host = false` and `NetworkManager.players.clear()` without calling `NetworkManager.leave_game()`. The UDP broadcast timer and discovery server keep running after returning to main menu.
- **Fix:** Replace the direct mutations with a single call to `NetworkManager.leave_game()`.

---

## LOW

### [✓] L1 — Race timer wraps at midnight

- **Files:** `MultiplayerGameManager.gd`
- **Function:** `_on_race_started()`, `_on_local_game_completed()`
- **Root cause:** `hour * 3600 + minute * 60 + second` wraps at midnight.
- **Fix:** Use `Time.get_ticks_msec() / 1000.0` (same as `Game.gd`) and store `_race_start_ticks` instead.

---

### [✓] L2 — Host processes its own broadcasts (wrong sender_id filter)

- **Files:** `NetworkManager.gd`
- **Function:** `receive_message()`
- **Root cause:** Godot sets `sender_id = 0` for local RPC calls, not `1`. The filter `if is_host and sender_id == 1: return` never fires for local calls. Host processes its own broadcasts, doubling the effect of every broadcast on the host side.
- **Fix:** Change filter to `if sender_id == 0 or (is_host and sender_id == 1): return`.

---

### [✓] L3 — `start_local_game()` leaks old `Game` node if called repeatedly

- **Files:** `MultiplayerGameManager.gd`
- **Function:** `start_local_game()`
- **Root cause:** `local_game = Game.new(); add_child(local_game)` without checking if `local_game` already exists.
- **Fix:** Add `if local_game: local_game.queue_free()` before reassigning.

---

### [✓] L4 — `is_multiplayer = true` set before connection succeeds

- **Files:** `MultiplayerLobby.gd`
- **Function:** `setup_as_client()`
- **Root cause:** `is_multiplayer` set to `true` unconditionally. If the lobby is closed before connecting, single-player games behave as multiplayer (forfeit button instead of new-game, status checks on every move).
- **Fix:** Only set `is_multiplayer = true` inside `_on_connected_to_server()`, after a successful handshake.

---

### [✓] L5 — Connection failure leaves UI stuck on "Connecting..."

- **Files:** `NetworkManager.gd`
- **Function:** `_on_connection_failed()`
- **Root cause:** Only prints a message. `is_multiplayer` stays `true`, lobby UI stuck.
- **Fix:** Call `leave_game()` (or emit a `connection_failed` signal) so the lobby can reset its state and show an error message.

---

### [✓] L6 — `has_valid_moves()` always returns `true` if stock is non-empty

- **Files:** `Game.gd`
- **Function:** `has_valid_moves()`
- **Root cause:** `if not stock.is_empty(): return true` — having stock cards doesn't mean a move can ever lead to progress. Auto-forfeit never triggers as long as any card remains in the stock.
- **Fix:** This is a design decision. At minimum, remove the early return and let the full move-validity check run, so "jammed" can be detected even with stock cards.

---

### [✓] L8 — Sudoku win overlay persists into the next round for the winner

- **Files:** `Main.gd`, `SudokuBoard.gd`
- **Root cause:** `_on_multiplayer_race_ended` disables the Sudoku board but does not clear `win_overlay`. The next round starts with the win screen still showing.
- **Fix:** Call `_sudoku_board.render()` (or explicitly hide `win_overlay`) when setting up a new round.
  *(Note: `win_overlay` is already hidden in `SudokuBoard.render()` — ensure `set_game()` / `render()` is called at the start of each round.)*

---

### [✓] L9 — Host sends `GAME_START` before client finishes processing `RACE_ENDED`

- **Files:** `MultiplayerGameManager.gd`
- **Function:** `_start_new_round()`
- **Root cause:** Host immediately calls `start_multiplayer_race()` after clearing state, broadcasting `GAME_SETTINGS` + `GAME_START` before the client has finished showing the ready screen.
- **Fix:** Add a short `await get_tree().create_timer(0.5).timeout` before `start_multiplayer_race()` in `_start_new_round()` to give clients time to settle. Or have clients explicitly signal they are ready to receive the new game start.

---

## Summary Table

| ID  | Severity | Status | Description |
|-----|----------|--------|-------------|
| C1  | Critical | [✓] | `race_ended` fires 2–3× per game end |
| C2  | Critical | [✓] | Sudoku win never reported to race system |
| C3  | Critical | [✓] | Sudoku game-over never reported to race system |
| H1  | High     | [✓] | `race_ended` args inconsistent across callsites |
| H2  | High     | [✓] | Host calls `host_game()` twice on startup |
| H3  | High     | [✓] | Client peer ID wrong until after handshake |
| H4  | High     | [✓] | Disconnected player stays `PLAYING` in status dict |
| H5  | High     | [✓] | Simultaneous finish double-ends race (covered by C1 fix) |
| H6  | High     | [✓] | `game_settings` not cleared between sessions |
| H7  | High     | [✓] | Forfeit doesn't disable Sudoku board input |
| M1  | Medium   | [✓] | `race_started` signal race condition |
| M2  | Medium   | [✓] | Ready-up with 1 player starts round immediately |
| M3  | Medium   | [✓] | `local_player_finished` set after signal emitted |
| M4  | Medium   | [✓] | `discover_games()` blocks main thread 3s |
| M5  | Medium   | [✓] | UDP socket leaked every 2s in `_broadcast_session` |
| M6  | Medium   | [✓] | Mirror data double-applied (indentation bug) |
| M7  | Medium   | [✓] | Last-standing notification race window |
| M9  | Medium   | [✓] | Back-to-menu bypasses `leave_game()` |
| L1  | Low      | [✓] | Race timer wraps at midnight |
| L2  | Low      | [✓] | Host processes own broadcasts |
| L3  | Low      | [✓] | Old `Game` node leaked on `start_local_game()` |
| L4  | Low      | [✓] | `is_multiplayer=true` set before connection |
| L5  | Low      | [✓] | Connection failure leaves UI stuck |
| L6  | Low      | [✓] | `has_valid_moves()` never false with stock cards |
| L8  | Low      | [✓] | Sudoku win overlay persists into next round |
| L9  | Low      | [✓] | Host sends `GAME_START` before client settles |
