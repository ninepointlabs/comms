# Comms

All-in-one text chat for **WoW Forever** (Interface 16001): one addon instead of five. Chat formatting, clickable URLs and invite links, name and keyword alerts, a whisper window with a tab per person, chat and typed history that survive `/reload` and logout, a bigger chat box with Tab completion, channel auto-leave, and quick lines on a quick-bar or key bindings.

It stays out of your way in dungeons, raids and battlegrounds, where Forever locks chat down for addons.

Comms by Nine Point Labs, not related to Forever Comms Voice / Guild Comms / Group Comms or Quick Comms.

> Status: v0.1 in review. Private repo; not published anywhere.

## Features

| | |
|---|---|
| **Chat look** | Class-coloured names, short channel names (`[2. Trade]` → `[2. T]`, editable), timestamps (format choice, on/off) |
| **Links** | URLs become clickable (click = copy box). "inv", "invite", "+1 inv" in whispers, party, raid, instance and guild add an `[invite]` link. Alt-click a name to invite. |
| **Copy** | Copy button on each chat window (all visible lines, select and Ctrl+C). Copy or re-use any line from Search. |
| **Alerts** | Your name and keywords: sound, tab flash, and an Alerts list. Case-insensitive, whole-word option. |
| **Whispers** | One movable window, a tab per person (Battle.net friends separate), unread badges, reply box, history kept for all characters (200 lines per contact, 50 contacts). Optionally hide whispers from main chat. |
| **History** | Last 500 lines per chat window (up to 2,000) replayed dimmed at login. Search over it with `/comms search <text>` or the Search page. |
| **Typed history** | Up/Down recall without Alt, last 100 sent lines, kept across `/reload` and logout. |
| **Input** | Bigger chat box (height, font size, above/below chat). It restyles Blizzard's box; no replacement frame. Tab completes names (friends, guild, group, whisper partners, people seen in chat), `/tt`, `/inv`, `/comms`, and channel names after `/join`. |
| **Channels** | Leaves General, Trade, Trade (City), LocalDefense, LookingForGroup and Services for you (your pick, account-wide, optional per-character list), or hides them instead. Never inside an instance. |
| **Quick lines** | 10 editable lines (`inv pls`, `ty for the group!`, `brb`...), auto channel (instance > raid > party > say), tokens `%t %f %z %r %d`, a quick-bar and key bindings. |
| **Sticky channels** | The chat type you last used stays selected (Blizzard already does this on Forever; Comms leaves it alone unless you change a type). |
| **/tt** | `/tt message` whispers your target (realm-aware); `/tt` alone opens the box as `/w Target `. |

## In chat lockdown (dungeons, raids, battlegrounds)

Forever hides chat from addons there and doesn't let addons send. Comms steps back:

| Feature | Outside instances | In chat lockdown |
|---|---|---|
| Formatting, alerts, invite/URL links, history capture | On | Off for locked lines (Blizzard shows them plain) |
| Whisper window | On | Whispers show in main chat; reply opens Blizzard's box |
| Quick lines | Send on click/key | Put into Blizzard's chat box: press Enter |
| Bigger input / autocomplete / no-Alt recall | On | Input styling stays (static), hooks do nothing |
| Auto-leave | Runs | Waits, runs after |

Comms never sends a chat message without a click or key press from you, and never calls `SendChatMessage` in lockdown.

## Install

Not released yet. When it is (Tim's call):

```
omaforge install -c forever github:ninepointlabs/comms
```

For testing from a checkout, `tools/install-dev.sh` copies only the files WoW needs into a scratch folder (or a folder you name). It refuses a live WoW AddOns folder unless `COMMS_ALLOW_LIVE=1` is set.

## Commands

```
/comms                    open or close the window
/comms whispers | quick | settings | channels | alerts
/comms search <text>      search chat history and whispers
/comms q <n>              fire quick line n
/comms leave | rejoin     channels: leave now / rejoin (prefills /join, press Enter)
/comms history clear      clear stored chat history
/comms setup | help
/tt [message]             whisper your target
```

Key bindings: Esc › Options › Keybindings › AddOns › Comms (Quick line 1-10, Open whisper window, Reply to last whisper).

## Known conflicts

Prat, WIM, Chattynator, BigChatBox, Block Blizzard Chat Channels and Better Forever Chat do the same jobs. If you add one, turn off the overlapping part of Comms (or don't run both).

## Development

```
lua5.1 tests/run.lua     # or luajit tests/run.lua
```

A strict WoW API mock (`tests/wow_mock.lua`, undefined globals are errors) loads every file in the TOC. CI runs a syntax check and the tests on every push and PR. Forever API reference: `Gethe/wow-ui-source`, branch `forever`, commit `c01a87b` (1.60.1 71091).

The icon is drawn by `tools/make-icon.py` (no dependencies).

## Licence

MIT. Comms is an unofficial fan project, not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and Warcraft are trademarks of Blizzard Entertainment, Inc.
