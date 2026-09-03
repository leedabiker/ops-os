# OPS/OS

Godot 4 desktop. One 8-minute shift. Three miner modes.

80x25 bitmap grid, integer scaled. No TTF. Amber industrial.

From the project (vendored Godot, same as ctrl-alt-defend):

```
./run.sh
```

or:

```
GDK_SCALE=1 ./.tools/Godot_v4.6.2-stable_linux.x86_64 --path .
```

`.tools/` is local, not in git. Copy the 4.6.2 linux binary there once.

## Play

Boot is workspace 2, mining focused, miner SAFE, clock 08:00. Workspaces are nameless desktops. Starting layout: power on 1, mining+repair on 2, radar+cam on 3. Move them.

Win: clock out while the site is still producing. Score is credits.
Lose: cascade reaches SITE KILL. The kill screen names the ignored event.
`r` or `Enter` (or click `retry`) starts the shift over. Do not quit the window.

## Keys

- `1` `2` `3` and `Super+1` `Super+2` `Super+3` — switch workspace
- `Super+Tab` / `Super+Shift+Tab` — next / previous workspace
- `Super+Shift+1/2/3` — move focused window and follow
- `Super+Shift+Alt+1/2/3` — move focused window, stay
- `Super+arrows` — focus window by direction
- `Super+Shift+arrows` — swap with window in that direction
- `Tab` — next window on this workspace
- `s` `h` `m` — SAFE / HIGH / MAX (anywhere except the terminal)
- `[` `]` — step mode down / up
- `Enter` — Repair clears FILTER / BELT / JAM / CELL / FAULT (Repair focused). Radar focused: ack the selected/first contact. Click a radar `■` to ack that one.
- `q` / `Super+Q` / `Super+W` — hide focused window
- `Super+Return` — terminal on this workspace
- `apps` / `apps list` — names (`cam` `mining` `power` `radar` `repair` `terminal`)
- `apps mining` — launch or focus. Hidden opens on this desktop. Already open jumps there.
- `Super+P` `Super+M` `Super+R` `Super+S` `Super+C` — same launches (in-game)
- `r` / `Enter` — retry on the end screen (SITE KILL / SHIFT END)
- Click a window to focus. Drag the title row by cells.

HEAT_WARN does not clear on Enter. Drop to SAFE while it is still STRESSED.

Radar blobs are live contacts. Unlabeled `?` until Repair `classify`; then the focused/nearest blob reads `contact` / `fence` / `intrusion`. `early` adds +6s to those contacts only. Fence ignore is legal. Unacked intrusion is SITE KILL. Hiss is scatter, not a contact. Blank radar is `NO SIGNAL`.

Cam is read-only. It shows the rig: mode, belt, hopper, filter, heat, lamp, power. Jam, heat, and dead power are visible without the ASCII line.

## Modes

| | SAFE | HIGH | MAX |
|---|---|---|---|
| materials | 1x | 2x | ~3.5x |
| draw | ~30% | ~60% | ~95% |
| heat | falls | creeps | climbs |
| events | JAM_SAFE (rare) | FILTER_CLOG, BELT_SLIP | HEAT_WARN. Ceiling. |

HIGH is the living. MAX is the extra cut and the way you start the chain.
MAX + Power STRESS (CELL_DIP) puts DEM over SUP; ignore that and Power FAULTs (brownout).
Heat at 100 is Mining FAULT.

The third mode is named MAX.

## HTML playtest

Previous canvas playtest lives in `playtest/index.html`. Open that file in a browser and click the canvas once so keys bind. It is not the Godot game.

## Stubbed

- GREP_CODE incident (terminal `pwd ls cd cat grep` works; Repair lock field is not wired)
- PUMP_STALL / BREAKER_TRIP as random spawns (brownout still arrives through the cascade)
