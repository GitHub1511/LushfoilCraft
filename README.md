# LushfoilCraft

Created by **Shivin Singh** (& Claude Sonnet 5.5). Built from Lushfoil Photography Sim (Matt Newell) and Minecraft Java Edition 1.21.1 (Mojang Studios) - see `CREDITS.md`.

A UE4SS Lua mod that adds Minecraft creative building to the real Lushfoil Photography Sim (UE 5.3.2).
Nothing in the game's Paks or exe is modified. UE4SS is the only addition; `uninstall.ps1` removes it.

This repo is the **mod only** (~9 MB). The full 9 GB built game is not committed here (GitHub blocks
files >100 MB, and Lushfoil's Paks cannot be redistributed). Anyone builds it on their own PC with the
script below, from copies of the two games they own.

## Build it yourself (one command)

You need, on the same PC:

1. **Lushfoil Photography Sim** installed (e.g. Steam `steamapps\common\Lushfoil Photography Sim` -
   the folder that contains `LushfoilSim\` and `Engine\`).
2. **Minecraft Java Edition 1.21.1** launched once (so `%APPDATA%\.minecraft\versions\1.21.1\1.21.1.jar` exists).
3. **Python 3.10+** on PATH, Windows PowerShell.

Then, in this cloned repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\Build-LushfoilCraft.ps1 `
  -LushfoilPath "C:\Program Files (x86)\Steam\steamapps\common\Lushfoil Photography Sim" `
  -MinecraftPath "$env:APPDATA\.minecraft\versions\1.21.1\1.21.1.jar"
```

* `-MinecraftPath` also accepts a folder: the jar file's folder, `versions\1.21.1\`, or your whole `.minecraft` folder.
* Default output is `<parent>\LushfoilCraft` (a copy - your Steam install is untouched).
  Pass `-Output "D:\Games\LushfoilCraft"` to choose elsewhere, or `-NoCopy` to install in place.
* Pass `-SkipAssets` to skip regenerating Minecraft textures on a rebuild.
* What it does: copies the game (unless `-NoCopy`), regenerates `textures\` + `Scripts\blocks.lua /
  models.lua / items.lua` from your jar (`tools\make_*.py` + `tools\gen.ps1`), then runs
  `install.ps1` (UE4SS from `vendor\` + `sync.ps1`).

Play afterwards with:

```powershell
powershell -ExecutionPolicy Bypass -File .\play.ps1 -Game "C:\Games\LushfoilCraft"
```

Worlds/settings live per device in `%LOCALAPPDATA%\LushfoilSim\Saved\LushfoilCraft-*`, not in this folder,
so copying the built game to another PC brings no worlds.

## What it does

- 1,040 Minecraft blocks (386 full cubes, 131 plain-cube stand-ins for entity blocks such as chests/beds/signs, 523 non-cube models:
  stairs, slabs, torches, plants, panes, fences, doors, trapdoors, walls, lanterns, carpets, rails, ladders...) using Minecraft textures
  on Lushfoil's own materials, so they are lit, shadowed and fogged by Lushfoil's lighting.
- Creative building: aim-based break / place on a 1 m grid, hotbar of 9, creative flight, held block.
- Minecraft creative HUD (real Java Edition sprites at Minecraft's auto GUI scale): crosshair, hotbar with isometric block icons, selection frame, item-name fade. F1 hides it. Field of view is Minecraft's 70 (vertical), reach is 5 blocks, black selection outline around the targeted block.
- Break particles (64 per block, Java Edition physics constants), item drops (survival drop table, bobbing/spinning, pickup delay, counted in `LC.inv` - no inventory yet), hand swing on break/place, creative repeat rates (0.25 s break, 0.2 s place; takes effect after a restart).
- Minecraft Steve (third person, skin from the Minecraft jar) with walk swing.
- Graphics tuning (view distance, foliage LOD, TSR history, anisotropy, texture pool, 60 fps cap instead of the game's re-issued 30). Roughly +20% fps on an RTX 3050 at the same look.
- No survival features (by design, for now).

## Game modes, movement, unlocks

- **Creative / Survival** toggle: a LushfoilCraft panel appears top-left whenever the game's menu is up (click a row; F4 or controller LB switches mode, F2 / X flying, F3 / R3 / RB fast walking). The choice is saved in `config.txt` in the mod folder.
  - Creative: instant breaking, no drops, no particles, any block.
  - Survival: hearts, hunger, XP bar, fall damage, regeneration, starvation, cactus and magma damage, death (inventory drops, respawn at the start); real inventory in the 9 hotbar slots (counts shown), Java Edition mining times (hardness, tool speed, tool tiers, "needs the right tool to drop"), break cracks, particles, item drops with pickup, survival drop table (stone->cobblestone, ores->items, leaves->saplings...), sand/gravel fall, plants and torches pop off when unsupported, eating (hold use on bread / apple / beef), Q throws an item. Optional starter kit (iron tools, shears, bread) from the panel.
- **Flying** (F2 / X, Space up, Ctrl / L3 down) and **fast walking** (x3, F3 / R3) work in both modes.
- **Go anywhere**: the game's 370 invisible `boundaryblock` colliders per level are switched off.
- **Everything unlocked**: levels, portals, photo boards, unlockable items, totems, animals and tutorials are written into the live save every 15 s. `tools/unlock_save.py <savefile.sav> <out.sav>` builds the same thing as a file (`savefile_unlocked.sav`, from your savefile.sav); `install_save.ps1` installs it with a backup (game closed).

## Worlds, movement, mobile view

- **Worlds** are saved like Minecraft's (`saves/` in the mod folder): every placed block, your position, game mode, health/hunger, inventory and hotbar. They autosave every minute and whenever a menu opens; the menu panel has **World** (click to switch to your next world), **Save world** and **New world**. The last world reopens automatically on the next start.
- The **hotbar and crosshair** only show once the game has started (not on the launch scene or in menus); F1 hides them.
- **Movement as in Java Edition**: walking 4.317 and sprinting 5.612 blocks/s, a 1.25 block jump under 32 blocks/s^2 gravity, 0.6 block steps, double-tap W or hold Ctrl (left stick click on a pad) to sprint, held Space keeps jumping, sprinting widens the view, no sprinting at 6 food or less in survival.
- **Mobile view** (F6 or the panel row): a 9:16 portrait render with black side bars, a slightly wider view, and the hotbar/crosshair laid out inside the phone-shaped frame (`MOBILE_ASPECT` in craft.lua changes the ratio).

## Inventory, commands, controller, sliders

- **Creative flight** (creative mode): double-tap Space (or the pad's A) to start flying, double-tap again to stop and fall. Space rises, Ctrl / Shift / left-stick click descends, flying is 10.9 blocks/s and double with a double-tap-W sprint. The hand and view stay still while flying.
- **Every map**: the mod follows level changes (all nine maps: Lago di Braies, Chamonix, Iceland, Fushimi Inari, Castle Rock Beach, Mardi Himal Trail, Shengshan Island, Syon Park, Yamadera). Each map keeps its own worlds, the hidden perimeter walls are removed on every map, and all maps, photo boards, totems, unlockables and tutorials are unlocked.
- **Inventory** (E, or Y on a pad): survival shows your 36 slots, armour and crafting layout and Steve; creative shows the item browser (search by clicking the box and typing, scroll with the bar / Page Up/Down, trash slot, "Inventory" tab). Left/right click, shift-click and drop-on-close work like Minecraft; on a pad D-pad moves, A clicks, X right-clicks, B/Y closes, LB/RB switch tab.
- **Commands**: T or / opens the chat bar with suggestions and Tab completion. `/give <item> [count]` (and `/give @s <item> [count]`) gives any block or item that has a sprite (1,040 blocks + 432 items).
- **Controller**: A jumps, Y inventory, D-pad left/right hotbar, up third person, down drop, LB+RB together raise/lower the Lushfoil camera, RT break, LT place/use. **Keyboard**: the Lushfoil camera is on P (Photos Quick Access moved to O); Space jumps.
- **Walking** (menu panel, F8): "Minecraft" (default: Java speeds 4.317 / 5.612 blocks/s, jump, sprint on double-tap W / Ctrl, view bobbing) or "LushfoilCraft" (the game's own gentle walk, plus the fast-walking toggle which only appears there).
- **Sliders** in the menu panel: field of view (30-110), screen shape (full window to 9:16 phone) and render distance. Fine-tune FOV with - and = in the game.
- **Water** is Lushfoil's own again: lakes are solid and its respawner returns you to your last dry spot (an earlier swimming feature was removed).
- The hand: a visible right arm in first person and Steve's arm holds and swings the item in third person; the near blur is off so the held item stays sharp.
- **Per device**: worlds and settings are stored in `%LOCALAPPDATA%\LushfoilSim\Saved\LushfoilCraft-*`, not in this folder, so copying the game to another PC brings no worlds.

## Maps and worlds

The game's own launch scene and credits (Created by Matt Newell, published by Annapurna Interactive) are untouched. To change map or world at any time press **F9** (or "Maps and worlds" in the pause panel): pick one of the nine maps, then one of that map's worlds or "+ new world" and type its name. Worlds belong to the map they were made on; switching saves the current world first. Mouse, arrows + Enter/Escape, or pad D-pad + A/B. (`Scripts/title.lua`; its credits screen and boot-time opening exist but are off: `LC.titleBoot` does nothing.)
Pictures are made by `tools/Gen.cs` (`tools/gen.ps1` compiles and runs it; no packages needed): the realistic block logo (grass-on-dirt "LUSHFOIL", stone "CRAFT", with "created by Shivin Singh (& Claude Sonnet 5.5 + mark)") and the Minecraft credits panel.

## Controls

Keyboard / mouse: LMB or F break, RMB or R place, 1-9 hotbar, Q/E block -/+, PageUp/PageDown +/-9, F2 flight (Space up, Ctrl down), F5 third person, F7 tuned/default graphics.
Xbox-style controller (360/One over USB, XInput): RT break, LT place, RB/LB hotbar slot, D-pad left/right block -/+, D-pad up/down +/-9, X flight (A up, L3 down), Y third person, Back graphics toggle.

## Files

- `Scripts/main.lua` framework (single per-frame hook, polled keys, timers, hot reload) - restart the game to change it.
- `Scripts/craft.lua` features, hot-reloaded. `Scripts/dev.lua` scratch, run once per change.
- `Scripts/blocks.lua`, `Scripts/models.lua`, `textures/` generated by `tools/make_assets.py`, `tools/make_models.py`, `tools/make_gui.py`, `tools/make_items.py`, `tools/make_icons.py` from the Minecraft 1.21.1 client jar (via `Build-LushfoilCraft.ps1`, never committed).
- `install.ps1`, `uninstall.ps1`, `sync.ps1` (copy mod into the game folder, safe while running), `play.ps1`.

## UE4SS stability rules (learned the hard way)

Never use LoopAsync / ExecuteWithDelay / RegisterKeyBind callbacks - they run Lua on other threads and crash UE4SS.dll. Use the frame hook + `LC.after` timers and `IsInputKeyDown` polling. Cache the PlayerController/World; never destroy the active view target.
