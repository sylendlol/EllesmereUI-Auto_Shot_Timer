# EllesmereUI-Auto_Shot_Timer

<img width="1312" height="945" alt="image" src="https://github.com/user-attachments/assets/93da0b29-32c1-4b07-9921-b615467d6144" />
<img width="1300" height="941" alt="image" src="https://github.com/user-attachments/assets/492b27f7-aca3-4a03-b6fd-8bc478f014c7" />

A standalone add-on for **EllesmereUI** that adds a Hunter **Auto Shot timer** with the classic wind-up window: a bar that shows the reload, when you must be standing still, and when the next shot really comes.

```
[ reload ............................. |  wind-up ]
  move and cast freely                  stand still, no casts
```

Built for **WoW Forever** (Interface 16001) and tested against **EllesmereUI v9.6.1**. Its settings live in the **Dworak** section of the EllesmereUI panel.

## Features

- **Reload bar** restarted by every Auto Shot, filled in the UI Accent Color (or a color of your own).
- **Wind-up window**: a line and a tinted zone at the bar's right end. Be standing still by the line. Moving or casting past it turns the zone red and the time reads `hold`.
- **Haste-aware wind-up**: the window scales with ranged haste (Quick Shots, Rapid Fire, quiver), read from the reload the game reports against your bow's printed speed.
- **Latency compensation**: the line moves one ping + 0.10 s earlier, since your stop reaches the server that much later. A fine-tune offset is included.
- **Late shots are tracked**: when the server's try fails (moving, out of range, facing away, line of sight), the bar stays full and predicts the retry. A light then runs over the late shot's own wind-up up to the shot.
- **Move line** (optional): from this point you may start moving again and the shot still goes out.
- **Clip readout** (optional): `+0.12` after every shot, showing how much later than one reload it fired. Green under 0.25 s, amber under 0.50 s, red above.
- **Afterglow**: every shot briefly flashes the bar.
- Handles the WoW Forever quirks: a melee swing restarts the ranged reload, getting up from Feign Death restarts it, and turning Auto Shot on adds a wind-up + latency before the first shot.
- EllesmereUI look: EUI bar textures (plus SharedMedia), pixel-perfect border, the EUI cast spark, the global font. **Match Cast Bar Look** copies the player cast bar's texture, background and border.
- Can be **attached to the EllesmereUI player cast bar** (above or below, optional matching width), or placed freely in Unlock Mode.
- Live animated preview at the top of its options page.
- No EllesmereUI file is modified.

## Requirements

- EllesmereUI (v9.6.1 or newer recommended)
- **EllesmereUIDworak** (the core of the Dworak section)
- Optional: the EllesmereUI **Resource Bars** module, for *Attach to Cast Bar*, *Match Cast Bar Look* and the two rows in the Cast Bar options
- The WoW Forever client: the timer is driven by Forever's `PLAYER_SWING` event (12.0 clients give add-ons no combat log)

## Installation

1. Download or clone this repository.
2. Copy the `EllesmereUIAutoShot` folder into your AddOns folder, for example:
   `World of Warcraft\_classic_beta_\Interface\AddOns\EllesmereUIAutoShot`
3. Make sure the folder contains `EllesmereUIAutoShot.toc` directly (not a nested folder).
4. Enable **EllesmereUI Auto Shot Timer** in the add-on list and `/reload`.
5. Open EllesmereUI → **Dworak** → **Auto Shot Timer** (or type `/autoshot`) and switch it on. It is off by default.

## Reading the bar

| What you see | Meaning |
| --- | --- |
| Fill (Reload Color) | The reload since the last shot. Move and cast freely. |
| Green line + zone | The wind-up window. Be standing still by the line. |
| Red zone, time reads `hold` | You are moving or casting inside the window: the shot is held back. |
| Light blue line | Move line: from here you may move again and the shot still goes out. Shown only if you stood still since the last shot. |
| Full bar, light running over it | A late shot: the server retries, and the light runs over that shot's wind-up up to the shot. |
| Flash | A shot just went out (afterglow). |
| `+0.12` in the middle | Clip of the last shot: how late it came compared with one clean reload. |
| Time on the right | Seconds to the next shot. |

## Settings

EllesmereUI → **Dworak** → **Auto Shot Timer**.

| Setting | Default | Description |
| --- | --- | --- |
| **Auto Shot Timer** | Off | Turns the timer on. |
| **Hunters Only** | On | Off: also shows for other classes' ranged auto-repeat (Shoot, Throw). |
| **Hide When Idle** | On | Hidden while Auto Shot is off and nothing reloads. |
| **Melee Resets Reload** | On | On WoW Forever every melee swing restarts the Auto Shot reload. The bar restarts with it. |
| **Base Wind-up** | 0.5 s | The unhasted wind-up. Ranged haste shortens it automatically. |
| **Latency Compensation** | On | Moves the line one ping + 0.10 s earlier. |
| **Latency Offset (ms)** | 0 | Added to the compensation. If shots still clip, raise it. |
| **Mark Window** | On | The wind-up line and zone. |
| **Move Line** | On | The light blue "you may move now" line. |
| **Clip Text** | On | The `+0.12` readout after every shot. Cleared when combat ends. |
| **Texture** | None | EllesmereUI bar texture (SharedMedia textures are listed too). |
| **Match Cast Bar Look** | Off | Uses the cast bar's texture, background and border instead of the ones here. |
| **Width / Height** | 220 × 14 | Bar size. Width is locked while *Match Cast Bar Width* is on. |
| **Font / Text Size** | EUI Global Font / 11 | Font of the label, time and clip text. |
| **Show Label / Show Time** | On / On | "Auto Shot" on the left, seconds on the right. |
| **Show Spark** | On | The spark on the fill's moving edge. |
| **Afterglow** | On | The flash on every shot. |
| **Border** | 1 px, black | Border thickness and color (0 = none). |
| **Background** | 60 %, near black | Background opacity and color. |
| **Reload Color** | UI Accent Color | The fill. *Custom* uses the color next to it. Follows Global Settings live. |
| **Marker Colors** | green / red / light blue | Window, Blocked and Move Line colors. |
| **Attach to Cast Bar** | Off | Anchors the bar to the EllesmereUI player cast bar. While attached it moves with the cast bar. |
| **Side / Gap** | Below / 2 | Where it sits relative to the cast bar. |
| **Match Cast Bar Width** | On | The bar takes the cast bar's width while attached. |

Resource Bars → **Cast Bar** → **EXTRAS** also has quick rows for *Auto Shot Timer*, *Attach to Cast Bar*, *Auto Shot Side* and *Auto Shot Gap*.

Settings are saved in the EllesmereUI profile store, so they follow profile switches. When the bar is not attached, move it in **Unlock Mode** (group "Dworak").

## Slash commands

| Command | Description |
| --- | --- |
| `/autoshot` or `/euiautoshot` | Opens the options page. |
| `/autoshot debug` | Prints what the timer knows right now: ping, bow speed, wind-up, saved reload, Auto Shot / moving / combat state, the last clip. |
| `/autoshot log` | Toggles a shot log in chat (see below). |

### The shot log

`/autoshot log` prints every shot and everything in between:

```
shot: 2.98s after the last, reload 2.50s, clip +0.48s, bar +0.05s - the stop reached the server late
  +1.32s move (bar: shot in 1.18s)
  +2.09s failed while moving, counted (bar: shot in 0.95s)
  +2.32s stop (bar: shot in 0.68s)
```

`bar` is the shot's time minus where the bar ended: `+` means the shot came after the bar's end, `-` before it. Values around 0 to +0.08 mean the bar is on time. If you see a steady offset, adjust **Latency Offset**.

## How the timing works

WoW Forever reports each Auto Shot with `PLAYER_SWING(duration, Ranged)`, with the duration already hasted. Everything else is worked out from what the client still tells add-ons:

- **Wind-up** = 0.5 s × this reload ÷ the bow's printed speed (read from its tooltip). The line sits that much plus ping + 0.10 s before the bar's end.
- **Reload memory**: `UnitRangedDamage` is hidden in combat on Forever, so the slowest reload seen per bow is remembered and used before the first shot.
- **Failed tries** (`UNIT_SPELLCAST_FAILED_QUIET`): the server tries again 0.5 s later, and the shot comes one wind-up after that. Failures of your own Auto Shot presses are ignored.
- **Moving**: a move inside the running wind-up cancels it. If you moved through the wind-up's start, the server starts the wind-up once your stop reaches it (stop + ping + 0.10 s). A failure that still arrives after the stop overrides that.
- **Switch-on**: the first shot comes one wind-up + ping + 0.12 s after you turn Auto Shot on. A brief off-and-on (a cast flicking it) does not count as a new start.
- **Quick Shots**: buffs are hidden in combat, so a proc is recognized by a player aura change in the same frame as a shot. It is ignored on the pull shot, and it is undone if the next reload does not come back hasted.

Measured in game (shot time minus bar end): steady and standing shots +0.01 to +0.08 s, shots after moving -0.03 to +0.07 s.

## Notes and limitations

- WoW Forever only: other clients have no `PLAYER_SWING` and nothing is shown.
- If the bow's tooltip cannot be read (item data not loaded yet), the wind-up falls back to a flat 0.5 s until it can.
- Quick Shots detection is a timing heuristic. A rare other aura change on a shot frame can still be taken for a proc until the next shot corrects it.
- Spamming `!Auto Shot` can make Forever fire a shot early. This is not predicted. The bar simply restarts on the real shot.
- EllesmereUI's own Swing Timer (Resource Bars → Swing Timer) has a simpler *Movement Guide* with a fixed 0.5 s window. Running both, or another swing timer add-on, shows two Auto Shot bars.

## For developers

The add-on exposes a small global API, used by its Cast Bar rows:

```lua
EllesmereUIAutoShot.Get(key)        -- read a setting
EllesmereUIAutoShot.Set(key, value) -- write a setting (call Refresh or Apply after)
EllesmereUIAutoShot.Apply()         -- re-apply after turning it on or off
EllesmereUIAutoShot.Refresh()       -- repaint after a look or position change
EllesmereUIAutoShot.Open()          -- open the options page
```

The Cast Bar rows join the shared Cast Bar **EXTRAS** host (`ns._EUICastExtras` on the Resource Bars module namespace) with order 20, next to other cast bar extras.

Saved settings use the `as` prefix (`asEnabled`, `asWindup`, `asLatency`, `asAttach`, …). Reloads per bow are kept in `asReloads`.

## Files

| File | Purpose |
| --- | --- |
| `EllesmereUIAutoShot.toc` | Add-on manifest |
| `EllesmereUIAutoShot.lua` | Settings store and shared helpers |
| `AutoShot_Engine.lua` | The timing: shots, wind-up, failed tries, moves, Quick Shots, the log |
| `AutoShot_Bar.lua` | The bar, the options page and preview, Unlock Mode, slash commands |
| `AutoShot_CastExtras.lua` | The rows in Resource Bars → Cast Bar → EXTRAS |

## Credits

Add-on for EllesmereUI by Ellesmere, made by Dworak. This project is not affiliated with EllesmereUI.

The timing rules build on the WoW Forever measurements published in **AppelSwingsForever** by Appel (failed-try retries, haste-scaled wind-up, move cancels, switch-on delay, melee and Feign Death restarts, Quick Shots). The code here is a separate implementation, and the stop rule was re-measured for this add-on.
