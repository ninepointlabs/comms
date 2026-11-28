# Comms

All-in-one text chat for **WoW Forever** (Interface 16001): one addon instead of five. Chat formatting, clickable URLs and invite links, name and keyword alerts, a whisper window with a tab per person, chat and typed history that survive `/reload` and logout, a bigger chat box with Tab completion, channel auto-leave, and quick lines on a quick-bar or key bindings.

It stays out of your way in dungeons, raids and battlegrounds, where Forever locks chat down for addons.

Comms by Nine Point Labs, not related to Forever Comms Voice / Guild Comms / Group Comms or Quick Comms.

> Status: v0.2.1 released on GitHub (installable with OmaForge). In-game testing is still in progress.

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
| **Quick lines** | Situational sets (Open World, Party / Dungeon, Raid / BG) that swap with where you are, plus an always-visible Combat row. Up to 10 editable lines per set, auto channel (instance > raid > party > say), tokens `%t %f %z %r %d`, a quick-bar and key bindings. See [Quick lines](#quick-lines). |
| **Sticky channels** | The chat type you last used stays selected (Blizzard already does this on Forever; Comms leaves it alone unless you change a type). |
| **/tt** | `/tt message` whispers your target (realm-aware); `/tt` alone opens the box as `/w Target `. |

## Quick lines

The quick-bar has two rows:

1. **The active set**, with a set tab at the left (`World`, `Party`, `Raid`; `*` when pinned). Comms picks the set for you:

   | Set | When | Default lines |
   |---|---|---|
   | **Open World** | solo, not in a group instance | hi, wave (`/e`), ty, thx, group?, inv (whisper), brb, LFG (LookingForGroup channel) |
   | **Party / Dungeon** | in a group, or in a dungeon | ready, omw, ty, quest?, wait, brb, back, gg |
   | **Raid / BG** | in a raid group, a battleground or an arena | inc, help, clear, omw, ready, ty |

2. **The Combat row**: oom, inc, peel, pull, heal (up to 10 lines). It never swaps, and stays visible in combat, even with "Hide the quick-bar in combat" on (that setting hides row 1 only). **It's optional (on by default):** Settings › Quick lines › "Show the Combat row" turns it off or on, and "When to show it" picks On, always (default) / On, only in groups / Off. Or type `/comms combat off` / `/comms combat on`; bare `/comms combat` says whether it's on (always), on (only in groups) or off, and toggles it. Showing or hiding it waits until combat ends; turned off mid-fight, it stays on screen until then but ignores clicks and keys.

How switching works:

- Comms re-reads where you are on zoning, loading screens, group changes and the end of combat. **It never switches in combat:** a change mid-fight waits until combat ends, so the buttons never move under your mouse. If the game won't say (hidden values), the current set stays.
- **Pin a set:** click the set tab (cycles), use Settings › Quick lines, or `/comms set world|party|raid`. A pin holds until `/comms set auto` (or right-click on the set tab), or until the next login or `/reload`.
- "Switch sets automatically" off: the set you last picked is used, also after logging in. Each situational set can be turned off; the next one that's on is used instead.
- Edit every line (text, button label, channel, whisper/channel target) in `/comms quick`; one tab per set, plus Add a line / Remove / Reset.

Key bindings (Esc › Options › Keybindings › AddOns › Comms):

- **Quick line 1-10** fire slot 1-10 of the **active set** (the set on the bar). They keep v0.1's binding names, so keys bound in v0.1 still work.
- **Combat line 1-5** fire the Combat row. While the row is hidden (off, or "only in groups" while solo) they do nothing.

In dungeons, raids and battlegrounds every quick line (any set, Combat too) goes into Blizzard's chat box: press Enter. Upgrading from v0.1: if you had edited your 10 lines, they become your Open World and Party / Dungeon sets; if not, you get the new defaults.

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

With [OmaForge](https://github.com/ninepointlabs/omaforge):

```
omaforge install -c forever github:ninepointlabs/comms
```

Already installed: `omaforge update`.

By hand: download `Comms-vX.Y.Z.zip` from [Releases](https://github.com/ninepointlabs/comms/releases), unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, then `/reload` and `/comms`.

For testing from a checkout, `tools/install-dev.sh` copies only the files WoW needs into a scratch folder (or a folder you name). It refuses a live WoW AddOns folder unless `COMMS_ALLOW_LIVE=1` is set.

## Commands

```
/comms                    open or close the window
/comms whispers | quick | settings | channels | alerts
/comms search <text>      search chat history and whispers
/comms q <n>              fire quick line n of the active set
/comms set <world|party|raid|auto>   pin a quick-line set, or back to automatic
/comms combat [on|off]               show or hide the Combat row (bare: show the state and toggle)
/comms leave | rejoin     channels: leave now / rejoin (prefills /join, press Enter)
/comms history clear      clear stored chat history
/comms setup | help
/tt [message]             whisper your target
```

Key bindings: Esc › Options › Keybindings › AddOns › Comms (Quick line 1-10 for the active set, Combat line 1-5, Open whisper window, Reply to last whisper).

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
