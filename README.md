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

Boot is workspace 2, Mining focused, miner SAFE, clock 08:00.

Win: clock out while the site is still producing. Score is credits.
Lose: cascade reaches SITE KILL. The kill screen names the ignored event.
`r` or `Enter` (or click `retry`) starts the shift over. Do not quit the window.

## Keys

- `1` `2` `3` and `Super+1` `Super+2` `Super+3` — workspaces (Power / Mining / Security). `3` is radar+cam
- `s` `h` `m` — SAFE / HIGH / MAX (from Mining, or anywhere except the terminal)
- `[` `]` — step mode down / up
- `Tab` / `Super+Tab` — next window on this workspace
- `Enter` — Repair clears FILTER / BELT / JAM / CELL / FAULT (Repair focused)
- `q` / `Super+Q` — hide focused window
- `Super+Return` — terminal on this workspace
- `Super+P` `Super+M` `Super+R` `Super+S` `Super+C` — power / mining / repair / radar / cam
- `r` / `Enter` — retry on the end screen (SITE KILL / SHIFT END)
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

- Radar contacts / ack / INTRUSION (blank `NO SIGNAL` is live; floor dust and one dim contact when a clock is open)
- GREP_CODE incident (terminal `pwd ls cd cat grep` works; Repair lock field is not wired)
- `classify` / `early` spend materials or print `denied`; they do not change radar yet
- PUMP_STALL / BREAKER_TRIP as random spawns (brownout still arrives through the cascade)
