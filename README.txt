MVP - Dungeon Vouch Addon (v0.1.1)

Fixes in this build:
- Correct addon module bootstrap using the addon private table (varargs).
- Load order corrected so MVP.lua runs first and creates the MVP table.
- Slash commands register reliably (/mvp ...).

Install:
1) Unzip and place folder 'MVP' into Interface/AddOns/
2) Relaunch and enable MVP.

Usage:
- Enter a 5-man dungeon.
- After 60s inside, if party size is 5 you will be asked: "Snapshot the party?"
  - Yes: snapshot is saved; replacements who join later are added to the participant list.
  - No: asked again after 120s (while eligible).
- End-of-run vouch window opens when party disbands or /mvp end.

Commands:
- /mvp help
- /mvp end
- /mvp db
- /mvp sync
- /mvp debug


v0.1.2 fixes:
- Named UIDropDownMenu frames to avoid nil-name errors in Classic UIDropDownMenu.
- Added /mvp test and /mvp status.


v0.1.3 changes:
- Vouch window widened + resizable; reason dropdown no longer clipped.
- Removed 'None' vouch option; default is Positive.
- Vouch window displays character names without realms.
- Best-effort role prefill via UnitGroupRolesAssigned (if available).


v0.1.4 fixes:
- Removed SetMinResize (not available); use SetResizeBounds when supported.


v0.1.5 fixes:
- Removed UIPanelResizeButtonTemplate (missing in this client); added custom size-grabber button.


v0.1.8 fixes:
- Rebuilt UI_DB.lua cleanly to fix syntax errors.
- DB window widened/resizable; list shows Top - and Top +; detail shows full reason breakdowns.
- Added Util.StripRealm and removed realm from display strings.
- Vouch options are POS/NEG only; default POS.


v0.1.10 fixes:
- Rebuilt Util.lua (fixed syntax error) and enforced name-only player keys.


v0.1.11 UI:
- Centered DB window title.
- Re-laid out DB window to match reference (top controls, list above, detail panel below).
- Swapped top positive/negative columns to match header order.


v0.1.13 reputation:
- Added net reputation score (pos - neg) and faction-style tiers.
- DB list now shows Rep and Tier instead of Total.
- Tooltip shows Reputation and Tier.


v0.1.14 fixes:
- Fixed UI_Vouch.lua syntax error in RefreshReasonDropdown (removed stray 'end').


v0.1.15 UI:
- Reordered/realigned DB columns: Player, Pos, Neg, Reputation (Tier + value), Top Positive, Top Negative.
- Widened list area so columns fit cleanly.


v0.1.16 DB:
- DB window no longer resizable.
- Clicking a player now persistently highlights the row and reliably populates the detail pane.


v0.1.17 fix:
- Fixed DB detail pane not updating by migrating old Name-Realm keys to Name-only and rebuilding aggregates.


v0.1.18 UI/Test:
- DB window taller; list scrollbar is inside an inset box; detail panel taller to fit content.
- /mvp test marks run as test, allows self-vouch for test only, and sets first role Tank and second Healer.
- Vouch window colors player names by class (best-effort).


v0.1.19 UI:
- Vouch window now uses FULLSCREEN_DIALOG frame strata and high frame level so it always appears on top.


v0.1.20 UI:
- Vouch window is now fully opaque (alpha = 1.0) so background UI does not bleed through.


v0.1.21 reputation colors:
- Reputation value/tier now always recomputed from total pos/neg (no stale cached rep).
- Reputation text colored by tier (Hated..Exalted) in DB list, detail pane, and tooltips.


v0.1.22 party print:
- On joining/changing a 5-man party, MVP prints each party member's reputation tier and value in chat.
- Uses a roster signature to avoid spam (prints only when roster changes).


v0.1.23 party join prints:
- GROUP_ROSTER_UPDATE now prints only newly joined party members after the initial roster print.
- If a member's reputation is negative, includes their top negative comment and count.


v0.1.24 fixes:
- Reputation now colorized consistently anywhere it appears (DB detail + party prints).
- /mvp test rebuilt: includes tester in participants, allows self-vouch for test, and defaults roles (1st=TANK, 2nd=HEALER).


v0.1.25 party/db ui:
- Party join/new member prints: name colored by class, reputation block colored by tier; includes top negative reason when rep<0.
- DB rows: right-click sends party report with reputation and top negative reason when rep<0.
- DB filter: added reputation dropdown; removed Role: label; aligned search + filters.


v0.1.26 fixes:
- Fixed MVP.lua syntax error in party printout and added class-colored names for newcomer prints.
- Fixed UI_DB.lua rep filter dropdown initialization (was appended outside Init) and added REP_FILTERS definition.


v0.1.27 fix:
- Fixed DB rep filter dropdown creation (repDD was nil). Now created and initialized properly.


v0.1.28 fixes:
- DB reputation filter dropdown now actually filters the list by tier.
- DB list Reputation column is now colored by tier.


v0.1.29 fixes:
- Fixed /mvp test: now always populates 5 participants so the vouch UI shows rows/dropdowns.
- /mvp test includes the tester and defaults roles (self=TANK, DummyPlayer2=HEALER).
- Added guard message if vouch UI opens with 0 participants.
