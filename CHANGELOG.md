# Changelog

## v0.2.0 (2026-11-27)

- Situational quick-line sets: **Open World**, **Party / Dungeon** and **Raid / BG**, each with its own editable lines (up to 10). The bar switches set by context (group, dungeon, raid, battleground, arena) and only out of combat; a change in combat waits until it ends.
- **Combat row**: a second, always-visible row (oom, inc, peel me, pulling, heal me; up to 10 lines) that never swaps in combat and stays shown with "Hide the quick-bar in combat" on. Show it always, only in groups, or off.
- Set tab on the bar (click: next set, right-click: automatic), `/comms set world|party|raid|auto`, "Switch sets automatically" and per-set on/off in Settings › Quick lines. A pin lasts until cleared or the next login.
- Key bindings: Quick line 1-10 now fire the active set's slots (same binding names as v0.1, so bound keys keep working); new Combat line 1-5.
- The quick-lines editor has a tab per set, plus Add a line, Remove and Reset this set.
- SavedVariables schema 2. Your v0.1 quick lines, if you had edited them, become Open World and Party / Dungeon; untouched v0.1 lines are replaced by the new defaults. `settings.quick.lines` is left in place for one version and will be dropped later.
- Fix: "Hide the quick-bar in combat" now also applies at the very start of a fight (`InCombatLockdown()` is still false while `PLAYER_REGEN_DISABLED` is handled).

## v0.1.0 (2026-11-24)

First version for WoW Forever (Interface 16001):

- Chat look: class-coloured names, short channel names, timestamps (Blizzard's own option).
- Clickable URLs (copy box), `[invite]` links on invite requests, Alt-click a name to invite.
- Copy button per chat window; copy or re-use any line from Search.
- Name and keyword alerts: sound, tab flash, Alerts list.
- Whisper window: a tab per person, Battle.net tabs, unread badges, reply box, account-wide history.
- Chat history kept across /reload and logout, replayed dimmed; `/comms search`.
- Typed history: Up/Down without Alt, last 100 lines, kept across sessions.
- Bigger chat box (restyled Blizzard box) and Tab completion.
- Channel auto-leave (or hide), account-wide with optional per-character list; rejoin.
- 10 quick lines with tokens, a quick-bar and key bindings.
- `/tt` whisper target.
- Steps back in chat lockdown: never sends, never touches Blizzard's box, prefills instead.
