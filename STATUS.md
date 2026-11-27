# STATUS: Comms v0.2.0, situational quick-chat sets + Combat row (2026-11-27)

**PR:** https://github.com/ninepointlabs/comms/pull/2 **merged into `main` on 2026-11-27** (merge commit `fe3474c`, on Tim's OK). Released as **v0.2.0** (see Release below). Brief: `designer-briefs/comms-situational-macro-bar.md` (Tim approved option 2, a dedicated Combat row, 2026-11-27).

**What changed**
- `Modules/QuickSets.lua` (new): context detection (Raid / BG if `IsInRaid()`, a `pvp`/`arena` instance or `C_PvP.IsBattleground()`; Party / Dungeon in a `party` instance or a group; else Open World; any secret/missing/erroring answer keeps the current set), deferred switching in combat, session pin, per-set enable with fallback, auto on/off.
- `Core/DB.lua`: schema 2, `settings.quick.sets.{world,party,raid,combat}`, `auto`, `lastPicked`, `combatRow`. `DB.Migrate` now runs *before* defaults are filled and is idempotent. v0.1 lines Tim edited → Open World + Party / Dungeon; untouched v0.1 lines → new defaults. `settings.quick.lines` is left in place (read by nothing) for one version.
- `UI/QuickBar.lua`: two rows (active set with a set tab; Combat row). Layout runs out of combat only (plus the very first layout after a `/reload` in combat). Hide-in-combat hides row 1 only.
- `Modules/QuickLines.lua`: `Q.Fire(n, source, setKey)`, `Comms.CombatLine(n)`. Lockdown path unchanged (prefill / show).
- `Bindings.xml`: `COMMS_QUICKLINE_1..10` unchanged (now: active set), new `COMMS_COMBATLINE_1..5`.
- `Core/Boot.lua`: `GROUP_ROSTER_UPDATE` on the existing event frame; re-evaluate on `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `GROUP_ROSTER_UPDATE`, `PLAYER_REGEN_ENABLED`; `/comms set world|party|raid|auto`.
- `Core/Lockdown.lua`: `CombatLocked()` is also true between `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED` (InCombatLockdown() is still false inside the REGEN_DISABLED handler, so v0.1's hide-in-combat could miss the start of a fight).
- Settings › Quick lines (auto, per-set on/off, pins, Combat row mode) and the editor (`/comms quick`: tab per set, Add / Remove / Reset line / Reset set).

**Headless tests:** 54/54 with `lua5.1` and `luajit`; syntax check over every `.lua`. New/updated: context detection (11 contexts + C_PvP + secret/erroring/missing APIs), deferred swap and no layout in combat, `/reload` mid-fight, Combat row in combat incl. hide-in-combat and the REGEN_DISABLED timing, row modes, bindings (active set + Combat), lockdown → prefill with zero sends across all sets, `/comms set`, pins, per-set enable, migration (untouched / edited / no schema / fresh / idempotent / arrays never merged), editor add/remove/reset, TOC lists every addon file.

**In-game checklist (not yet done):** see the PR body.

---

# STATUS: Comms v0.1 (2026-11-24)

**What it is:** an all-in-one text chat addon for WoW Forever. It replaces the Prat + WIM + Chattynator + BigChatBox + Block Blizzard Chat Channels stack with one addon and stays out of the way in chat lockdown (dungeons, raids, battlegrounds). It's built from `BRIEF.md` (gitignored), on The Terminal List's layout, widget kit, strict-mock tests and CI/release workflow.

**Repo:** https://github.com/ninepointlabs/comms (**⚠ public, not private**: the GitHub API reports `visibility: public`, and the repo's only visibility event is a `PublicEvent` at 2026-11-24T18:05:07Z, its creation time, before this work began. I didn't change it; the brief says not to touch visibility, so it's Tim's/Admin's call), branch `feature/initial-addon`, PR #1 https://github.com/ninepointlabs/comms/pull/1, **merged into `main` on 2026-11-25** (merge commit `69699ea`, on Tim's OK). Released **v0.1.0** for OmaForge on Tim's OK (2026-11-24, "approved, tag the PR branch").

**OmaForge (2026-11-24):**
- Topics `wow-addon` + `world-of-warcraft` added; OmaForge's GitHub search requires `wow-addon`.
- The annotated tag `v0.1.0` points at `6a7ac78`, the PR branch head at that time. Since the merge, `main` contains it (merge commit, not squash, so the tagged commit is in `main`'s history).
- The Release workflow (BigWigs packager) passed (run 45461410079). Release: https://github.com/ninepointlabs/comms/releases/tag/v0.1.0
  - Assets: `Comms-v0.1.0.zip` and `release.json` (`flavor: forever`, `interface: 16001`). I downloaded and checked them: TOCs say `## Version: v0.1.0`, and the zip has Core, Modules, UI, Media, Bindings.xml, LICENSE and CHANGELOG, with no tests, tools, README or STATUS.
  - The packager's notes were replaced with a feature summary and install steps. There's no autonomix-cli line, because the release ships no Linux executables.
- `omaforge search -c forever ninepointlabs/comms` and `omaforge search -c forever comms -p github` both list `github:ninepointlabs/comms`.
- OmaForge's GitHub provider resolves **v0.1.0 → `Comms-v0.1.0.zip`, compat `ok`, channel stable** for the Forever client.
- Install: `omaforge install -c forever github:ninepointlabs/comms`. Tim installed it (2026-11-25); I checked the installed `AddOns/Comms` folder (read-only): TOCs say `v0.1.0`, every addon file is present, no overlapping chat addons are installed. Commits use `Nine Point Labs <179739321+ninepointlabs@users.noreply.github.com>`.

**Not done (not authorized):** CurseForge/Wago/WoWInterface, website, DNS, posts. I installed nothing into the live WoW folder (Tim did, via OmaForge): `tools/install-dev.sh` only ran into a scratch folder, and it now refuses the live `_forever_` AddOns path unless `COMMS_ALLOW_LIVE=1`. WTF/SavedVariables weren't touched; the installed AddOns folder was only read (slash-command collision check).

## Verified headlessly (2026-11-24)

| Check | Result |
|---|---|
| `lua5.1 tests/run.lua` | **48/48 pass** |
| `luajit tests/run.lua` | 48/48 pass |
| Lua syntax | every `.lua` loads with `lua5.1` |
| `tools/install-dev.sh <scratch>` | copies only the 2 TOCs, `Bindings.xml`, Core, Modules, UI, Media and LICENSE (34 files) |
| `tools/install-dev.sh <live _forever_ AddOns>` | refused, exit 1, nothing written |
| `omaforge clients` | Forever `1.60.1.71091`, Interface `16001`, matching both TOCs |
| CI (`.github/workflows/test.yml`: syntax + tests) | **pass** on PR #1 (run 45460490067) |

The strict mock (`tests/wow_mock.lua`) errors on any undefined global and loads every TOC file. It mocks Forever's `ChatFrameUtil` filter registries (which skip secret args), `C_ChatInfo`, `C_RestrictedActions`, `Enum.AddOnRestrictionType`, `EventRegistry`, `LinkUtil`, `issecretvalue`/`canaccessvalue`. The tests cover:

- **Packaging:** TOCs identical, Interface 16001, title/author/version token/website/icon, `CommsDB`/`CommsCharDB`, Boot loads last, every file exists, `Bindings.xml` has the `COMMS` header and all 12 bindings with labels. The icon is a valid 64×64 32-bit TGA.
- **Naming:** no `ForeverComms*`/`QuickComms*` globals or `/fc /qc /gc /fcv /fgc /fgp /commsvoice`. At runtime every global Comms creates is `Comms*`, `SLASH_COMMS*` or `BINDING_*COMMS*`.
- **Forever guard:** with `WOW_PROJECT_ID` ≠ 18, nothing is wired (no filters, hooks, callbacks or DB), and `/comms` and `/tt` refuse.
- **Taint audit:**
  - Static: no `SetScript` on chat frames or edit boxes. No assignment to `ChatFrameUtil.*`, `ChatEdit_*`, `ChatFrame_*`, `SetItemRef` or `CHAT_*_GET`. No `channelList` writes, `LinkUtil.RegisterLinkHandler`, `SendText`, `SetAttribute`, `Add/RemoveChatWindowChannel` or `SendAddonMessage`. `SendChatMessage` appears only in `QuickLines.lua`, and never in a timer.
  - Runtime: zero `SetScript` calls on Blizzard objects. Edit boxes are only `HookScript`/`hooksecurefunc`'d. All sticky types stay at Blizzard's values by default.
- **Lockdown:** `InChatMessagingLockdown`, `IsAddOnRestrictionActive(Chat)` and `ADDON_RESTRICTION_STATE_CHANGED` (Activating counts) drive `LOCKDOWN_CHANGED`. Combat alone is "busy" but can still send.
- **Format:**
  - Class colour through the sender-name filter. Names that are already coloured, unknown classes and secret GUIDs are left alone.
  - Short channel names keep Blizzard's `N. ` prefix and the original length.
  - Timestamps go through the `showTimestamps` CVar: on, off, and deferred in lockdown.
  - Any secret arg or a stage error returns `false` untouched.
- **Links:**
  - URL patterns: http, https, `www.`, domain.tld/path. Trailing punctuation is trimmed, there are no false hits on "lol.no" or "3.5", and existing item links are never rewritten.
  - A URL click opens the copy box. `[invite]` appears on inv/invite/+1 inv (whole word, any case) in whispers, party and guild, but not in SAY, not on "invitation" and not on my own lines. Clicking it calls `C_PartyInfo.InviteUnit`.
  - Clicks are handled through EventRegistry `SetItemRef`.
- **Alt-click invite:** works on player links. Plain clicks, non-player links, secret links and the setting turned off don't invite.
- **/tt:** no target, same realm and cross-realm. With no message it prefills `/w Name `. In lockdown it prefills and never sends. Secret names and NPC targets are handled.
- **Alerts:** name and keywords, any case, whole word on/off, my own lines skipped, once per line across chat windows, sound + tab flash + list + badge, never on secret lines.
- **Typed history:** `SetAltArrowKeyMode(false)`, history lines raised to 100. Lines survive a simulated reload (refill) and are capped at 100, consecutive duplicates are dropped, the refill isn't re-recorded, and nothing is recorded in lockdown.
- **Input:** height and font restyle, deferred in combat and applied on `PLAYER_REGEN_ENABLED`; the original values come back when turned off.
- **Autocomplete:**
  - Names from friends, guild, group and seen names, de-duplicated, own realm dropped, other realms kept.
  - Completes after `/tt`, our commands, and channels after `/join`.
  - Never completes `/p`, `/w name` or anything inside chat-type commands. Cycles through matches.
  - The Tab hook leaves Blizzard's own changes alone, and does nothing in lockdown or combat.
- **Channels:**
  - Leaves the selected channels on `PLAYER_ENTERING_WORLD`, one line each.
  - Skipped in instances and lockdown, retried when the restriction goes inactive.
  - The per-character override doesn't change the account list.
  - Hide mode drops lines without leaving.
  - Rejoin prefills `/join Name`.
- **Whispers:**
  - Tab per name-realm, plus Battle.net tabs keyed by BattleTag. Unread counts are cleared on open. Replies go as WHISPER / BN whisper.
  - "Show in main chat" off drops them from Blizzard's frame (locked ones still show).
  - Secret events store nothing. The lockdown banner and "Reply in chat" are shown, and nothing is sent in lockdown.
  - Caps: 200 lines per contact, 50 contacts with the oldest pruned. History is account-wide.
- **Quick lines:**
  - Auto channel INSTANCE > RAID > PARTY > SAY. Whisper goes to the target, else the last whisperer, else SAY. EMOTE and CHANNEL are supported.
  - Tokens `%t %f %z %r`; unknown tokens are kept. `%d` always prefills, with the cursor where it was.
  - Only `click`/`key`/`slash` sources fire; `nil`/"timer"/"event" do nothing.
  - **In lockdown, zero `SendChatMessage` calls across all 10 lines, the binding and the slash**, and `OpenChat` is prefilled with the slash form (`/i ty for the group!`). "Show" mode opens a copy box instead.
  - Quick-bar: 10 buttons, labels, bound key in the tooltip, hide-in-combat.
- **History:** lines stored per window as received. Secret lines are never stored. Ring cap per setting, max 2,000. Replay is dimmed, newest last, and off means nothing replays. Clear wipes everything.
- **Search** covers history, the session and whispers. **Copy** gets chat lines with secret ones skipped and counted. **Sticky** only writes what Tim changes, never in lockdown, and turning a change off restores Blizzard's value.
- **UI:** every page and all 8 settings tabs render unlocked, locked and in combat. About shows the live lockdown status and the "not related to Forever Comms…" line. `/comms` subcommands and help work.
- **SavedVariables caps:** typed 100, whispers 200×50, history ≤2,000 per window, seen names ≤2,000 (pruned by age).

**Headless limits:** the mock follows the forever-branch source, not the client. Taint, secret-value behaviour, frame layout and sounds can only be proven in game.

## Decisions (mine; Tim's to change)

The brief names these APIs, but the forever-branch source showed they'd taint or break chat, so I built them differently:

1. **Short names for Party/Guild/Raid aren't done.** Those tags come from Blizzard's `CHAT_*_GET` strings. Replacing them from an addon taints every chat line, and in lockdown that turns into errors on secret values. Numbered channels are shortened through the filter's channel argument instead. Blizzard requires the `N. ` prefix, so it reads **`[2. T]`, not `[T]`**. The short form is padded with invisible `|r` codes to the original length, because Blizzard matches that length against its channel list. Plain `[T]` would need replacing Blizzard's chat function.
2. **Timestamps use Blizzard's own `showTimestamps` option** (set by `C_CVar.SetCVar` outside lockdown and combat), not a filter. A filter can only add text after the name, and Blizzard's timestamps also work on locked lines. The default is "leave Blizzard's setting alone"; first-run setup offers a format.
3. **No "click a timestamp" line copy,** because Blizzard's timestamps aren't links. Instead:
   - a copy button on each chat window opens all visible lines;
   - every Search result has **Copy** and **To chat** (Shift-click's job, outside lockdown).
4. **Link clicks go through EventRegistry `SetItemRef`, not `LinkUtil.RegisterLinkHandler`.** Blizzard already registers the one `addon:` handler (`ItemRefHandlersShared.lua`) and rebroadcasts the click; a second registration is refused as a duplicate. Alt-click invite uses EventRegistry `ChatFrame.OnHyperlinkClick`. Blizzard's own plain-click action, which opens `/w Name`, still runs.
5. **Sticky channels:** on Forever, Blizzard already makes SAY/PARTY/RAID/INSTANCE/GUILD/OFFICER/WHISPER/BN/CHANNEL sticky, so Comms writes **nothing** by default. `ChatTypeInfo` is read on Blizzard's send path. Comms writes only types Tim changes, and never in lockdown or combat.
6. **Channel "hide" mode is a message filter** (drop the line), not `ChatFrame_RemoveChannel`. That function doesn't exist on Forever, and its replacement writes `chatFrame.channelList`, which Blizzard compares against secret channel names in lockdown.
7. **Rejoin prefills Blizzard's `/join <channel>`;** Tim presses Enter. Joining from addon code means writing that same channel list (see 6). `/comms rejoin` handles one channel per press and says how many are left. A rejoined channel that's still ticked gets left again at next login, and Settings says so.
8. **Autocomplete never completes chat-type commands** (`/p`, `/g`, `/w Name`). Blizzard re-parses the box on every text change, so completing those from addon code would set the box's chat type from tainted code. Blizzard already completes `/w` names. Comms completes plain-text names, `/tt` and `/inv` names, its own commands, and channels after `/join`/`/leave`.
9. **Lockdown fallback for quick lines** is `ChatFrameUtil.OpenChat` prefill (the brief's choice), with a Settings option "Show it to copy" in case prefill turns out to cause trouble in game (see the checklist).
10. **Defaults:**
    - Leave Services + Trade (City) (brief). Mode: leave. Auto-leave runs at login even before first-run setup is finished.
    - Bigger input on (32 px, font 15, below chat). Alerts on (name; sound "Raid warning"; tab flash). Whisper window on, also shown in main chat.
    - History on (500 lines, replay on). Quick-bar shown at bottom centre. Lockdown action: prefill. Role DPS.
11. **Quick line `%d`:** a line containing it is always prefilled (never sent), with the cursor where `%d` was, so Tim types the dungeon name and presses Enter. "LFG %d as %r" opens as `/4 LFG | as DPS`, where `|` is the cursor.
12. **Battle.net contacts are keyed by BattleTag.** The presence ID changes every session. A BN reply from the window needs that friend to have whispered this session (it prints a note otherwise).
13. **Not built in v0.1:** the "optional multi-line look" for the input. A multi-line EditBox changes what Enter does in Blizzard's box. Also not built: right-click-a-line copy, which would need a callback field on Blizzard's chat frame.
14. **No addon-compartment global function.** The TOC has no `AddonCompartmentFunc`, so the global table stays `Comms` only. It registers at runtime through `AddonCompartmentFrame:RegisterAddon` when that exists.
15. **Extra global frame names:** `CommsMainFrame`, `CommsMessenger`, `CommsCopyFrame`, `CommsQuickBar`, `CommsMinimapButton` (Escape-to-close needs names). Slashes are `/comms` and `/tt`. No clash in Tim's installed Forever AddOns (`rg` over `_forever_/Interface/AddOns`, 2026-11-24). Blizzard's localized slash list (GlobalStrings) isn't in wow-ui-source, so `/tt` is checked in game (item 2 below).

## Still to check in game (nothing here is claimed until Tim confirms)

Install from a release later, or for a test, with `tools/install-dev.sh "<_forever_ AddOns path>"` and `COMMS_ALLOW_LIVE=1`. That's Tim's call; I didn't do it.

1. **Client:** `/run print(GetBuildInfo()) print(WOW_PROJECT_ID)` should show 1.60.1 / 71091 and 18. Comms loads with no Lua errors.
2. **Slash:** before enabling Comms, `/tt` should say it's unknown (so Comms doesn't hide a Blizzard command). After: `/comms`, `/comms help`, `/tt hi` with a player targeted.
3. **First run:** the setup window opens once (3 steps), then never again on another character.
4. **City (Stormwind/Orgrimmar):** joined to Trade and Services.
   - Services and Trade (City) are left with one line each. The other characters do the same with no setup.
   - `/comms rejoin` prefills `/join …`.
   - Hide mode hides lines.
5. **Chat look:**
   - Names in class colours.
   - Trade lines read `[2. T]`. **Check the invisible `|r` padding doesn't show and channel lines still appear at all.**
   - Timestamps in the chosen format.
6. **Links:**
   - A URL in chat is clickable and opens the copy box.
   - A friend whispers "inv": `[invite]` appears and invites.
   - Alt-click a name invites (Blizzard also opens `/w Name`; Escape closes it).
7. **Alerts:** someone says your name or a keyword: sound, tab flash, Alerts list.
8. **Input:**
   - The box is bigger and sits below (or above) chat. **Check Blizzard doesn't move it back when switching or docking tabs.**
   - Up/Down recalls without Alt. After `/reload` and after logout, the old lines are still there.
9. **Tab completion:** names in plain text, `/tt Na<Tab>`, `/join Tr<Tab>`, `/co<Tab>`. `/w Na<Tab>` is still Blizzard's.
10. **Whispers with a friend, including a Battle.net friend:**
    - Tabs, unread badges, reply from the window (both kinds).
    - "Also show in main chat" off hides them from main chat.
    - History survives `/reload` and relog.
11. **Party in the open world:** quick-bar `ty`/`brb` go to party; `inv` goes to the target. The SAY/EMOTE lines and the LFG channel line send on click, then on a bound key.
12. **A dungeon (the key test):**
    - The whisper window shows the lockdown banner and "Reply in chat".
    - Quick lines prefill Blizzard's box; Enter sends them.
    - **You can always type and send normally. No `ADDON_ACTION_FORBIDDEN` / `ADDON_ACTION_BLOCKED`**, including after using the quick-bar, Tab completion and `/tt` outside before entering.
    - Settings › About says "Chat locked: yes (…)".
    - If prefill ever blocks sending, switch Settings › Quick lines › In chat lockdown to "Show it to copy" and tell me.
13. **A battleground:** same as 12, plus no auto-leave inside. Leaving resumes it.
14. **`/reload`:** earlier chat lines come back dimmed; `/comms search <word>` finds them.
15. **SavedVariables size** after a few days: `WTF/Account/…/SavedVariables/Comms.lua` well under 2 MB.

## Next (v0.2 ideas from the brief, not built)

Mention history tab with jump-to, per-keyword sounds, spam filters, whisper extras (contacts, notes, pin; auto-reply needs Tim's decision), profiles and per-role quick-line packs. Release (`v0.1.0` tag → BigWigs zip + `release.json`, then `omaforge search -c forever ninepointlabs/comms`) only on Tim's OK.
