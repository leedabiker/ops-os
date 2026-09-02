# OPS/OS

Godot 4 desktop. One 8-minute shift. Three miner modes.

Open `project.godot` in Godot 4.2 or 4.3 (GL Compatibility). Press F5.

Integer-scaled 80x25 bitmap grid. No TTF. Amber industrial, not a themed Control UI.

## Play

Boot is workspace 2, Mining focused, miner SAFE, clock 08:00.

Win: clock out while the site is still producing. Score is credits.
Lose: cascade reaches SITE KILL. The kill screen names the ignored event.

## Keys

- `1` `2` `3` and `Super+1` `Super+2` `Super+3` — workspaces (Power / Mining / Security)
- `s` `h` `m` — SAFE / HIGH / MAX (from Mining, or anywhere except the terminal)
- `[` `]` — step mode down / up
- `Tab` / `Super+Tab` — next window on this workspace
- `Enter` — Repair clears FILTER / BELT / JAM / CELL / FAULT (Repair focused)
- `q` / `Super+Q` — hide focused window
- `Super+Return` — terminal on this workspace
- `Super+P` `Super+M` `Super+R` `Super+S` — power / mining / repair / radar
- `Super+Shift+1/2/3` — move focused window to that workspace
- Click a window to focus. Drag the title row by cells.

HEAT_WARN does not clear on Enter. Drop to SAFE while it is still STRESSED.

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

- Radar contacts / ack / INTRUSION (blank `NO SIGNAL` is live; blobs are not)
- GREP_CODE incident (terminal `pwd ls cd cat grep` works; Repair lock field is not wired)
- `classify` / `early` spend materials or print `denied`; they do not change radar yet
- PUMP_STALL / BREAKER_TRIP as random spawns (brownout still arrives through the cascade)
