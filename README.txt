============================================================
  MVP - Dungeon Vouches (TBC Anniversary Edition)
  Version 1.0.7
============================================================
MVP is a reputation-tracking addon for 5-man heroic
dungeons. After each run, you rate your party members
with a positive or negative vouch. These vouches are
shared with other MVP users building a community-sourced
reputation database across your realm.

When you open the LFG tool in game, MVP displays a tooltip 
below the LFG window showing that players reputation if
they have been vouched for previously.

Make sure you rename the folder once unzipped to: MVP

------------------------------------------------------------
HOW IT WORKS
------------------------------------------------------------
1. Run a dungeon with a party.
2. When the dungeon ends (or you type /mvp end),
   a vouch window opens listing your party members.
3. For each player, select their role, give a
   thumbs up or thumbs down, and optionally choose
   a reason (e.g. Skilled Player, Slow, Ninja
   Looter, etc.).
4. Your vouches are saved locally and broadcast
   to over players running MVP.
   
Vouches will decay over time, the only negative comment that is
considerably serious and never fully decays is the Ninja Looter
negative comment. Reputation decays 1% per day (floor 0%), 
except Ninja Looter which floors at 10% permanently.

------------------------------------------------------------
REPUTATION TIERS
------------------------------------------------------------
  Exalted      	100+    		(orange)
  Revered       80-99  			(blue)
  Honored       60-79  			(bright green)
  Friendly      20-59  			(green)
  Neutral       -19 to +19  	(gray)
  Unfriendly   	-20 to -59 		(orange-red)
  Hostile      	-60 to -79  	(red)
  Hated        	-80 and below  	(dark red)


------------------------------------------------------------
DATABASE WINDOW (/mvp db)
------------------------------------------------------------
- Searchable, sortable list of all vouched players.
- Click a column header to sort; click again to
  reverse direction.
- Double Left-click a player row to toggle Favorite.
- Right-click a player row to send their report
  to party/raid chat.
- Favorites appear at the top of the list.


------------------------------------------------------------
SLASH COMMANDS
------------------------------------------------------------
  /mvp or /mvp help - - displays all the /mvp commands in your chat window
  /mvp start - Snapshot your current party and begin tracking a dungeon run manually.
			 - doesn't normally need to be used
  /mvp end - End the current run and open the vouch window. Doesn't normally need to 
		   - be used but if the end of dungeon isn't recognized, use it.
  /mvp db - Open or close the reputation database window.
  /mvp status - Show the current run state, party members being tracked, and run ID.
  /mvp sync - Forces a sync, just the same as the DB sync button
  /mvp sources - Show anti-fraud source tracking stats: how many vouches have independent confirmations.

------------------------------------------------------------
					DATA & PRIVACY
------------------------------------------------------------
- All data is stored locally in your WoW
  SavedVariables folder as MVP.lua.
- Vouches are broadcast over the custom addon
  channel "MVPdata" — visible only to other
  players running the MVP addon.
- No external servers or third-party services
  are used.
- To back up your database, copy MVP.lua from:
  WTF\Account\<name>\SavedVariables\MVP.lua


============================================================
				Author: Tehshortbus
============================================================
