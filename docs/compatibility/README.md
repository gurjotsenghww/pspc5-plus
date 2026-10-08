# PSPC5 Plus Compatibility Database

Welcome to the **PSPC5 Plus** Compatibility Database. This document and its accompanying data source [`database.json`](database.json) record authentic, repeatable compatibility reports and hardware milestones.

---

## Compatibility Grading System

- **Playable · Completable**: The title boots, enters gameplay, renders graphics and text accurately, processes input and audio correctly, allows saving and loading, and can be completed.
- **In-game**: The title boots and reaches gameplay, but has noticeable rendering bugs, performance barriers, or crashes that prevent complete progression.
- **Intro / Menu**: The title boots and reaches title logos, menus, or non-interactive video playback, but cannot enter full interactive gameplay.
- **Boots**: The title loads and begins executing, but crashes before rendering visible menus.
- **Nothing**: The title fails during loading or encounters an unsupported early fault.

---

## Verified Compatibility List

| Title | Title ID | Engine | Status | Performance | Notes & Evidence |
|---|---|---|---|---|---|
| **Subnautica: Below Zero** | PPSA02457 | Unity | **Playable · Completable** | 10.60 FPS world / 15.5 FPS menu | Restores survival saves; sRGB lighting fix applied. [Screenshot](../../docs/images/subnautica-below-zero-repeat2-2026-10-03.png) |
| **Terminator 2D: No Fate** | — | Custom 2D | **Playable · Completable** | 22–65 ms frame times | Completed without reported defects. [Screenshot](../../docs/images/live-gameplay.png) |
| **Jets 'n' Guns 2** | — | Custom 2D | **Playable · Completable** | 11–14 FPS | Full playthrough confirmed; audio port routing fixed in 0.3.2. [Screenshot](../../docs/images/jets-n-guns-2-gameplay.png) |
| **Asterix & Obelix: Slap Them All!** | — | Custom 2D | **Playable · Completable** | 28–31 ms frame times | 3,000-flip stability run verified without rejected submissions. [Screenshot](../../docs/images/asterix-obelix-gameplay.png) |
| **Cat Quest III** | — | Unity | **Playable · Completable** | ~8 FPS (124 ms median) | Menus, cards, dialogue, island terrain render correctly. [Screenshot](../../docs/images/cat-quest-iii-world.png) |
| **Dreaming Sarah** | — | Custom 2D | **Playable · Completable** | 60 FPS cap on menu & scene 1 | Requires uncorrupted eboot.bin / libc.prx. [Screenshot](../../docs/images/dreaming-sarah-gameplay.png) |
| **Quake II (2023)** | PPSA09477 | KEX Engine | **Playable · Completable** | Peaks of 60–70 FPS | Level lighting, textures, weapons, and NPCs working. [Screenshot](../../docs/images/quake-ii-gameplay.png) |
| **Jurassic Park Classic Games** | — | Carbon Engine | **Playable · Completable** | 27/33 ms frame times | FreeType font rendering and Latin-1 atlas support enabled. |
| **Mighty Morphin Power Rangers: Rita's Rewind** | — | Custom 2D | **Playable · Completable** | Full speed gameplay | Native cooperative fibers, exact V_SAD_U32/V_MUL_HI lowering. [Screenshot](../../docs/images/ritas-rewind-gameplay.png) |
| **Grand Theft Auto III: The Definitive Edition** | PPSA03527 | Unreal Engine 4 | **In-game** | ~8.53 FPS opening | Walking, car entry, driving verified; lighting defects remain. [Screenshot](../../docs/images/gta3-renderer-performance.png) |
| **Little Nightmares Enhanced Edition** | PPSA10737 | Unreal Engine 4 | **In-game** | 3.7–4.5 FPS | Opening room reached; save/reload verified. Dark material defects remain. [Screenshot](../../docs/images/little-nightmares-saves-performance-2026-10-03.png) |
| **Ghost of Yōtei** | — | Decima Engine | **Intro / In-engine** | 1.23 FPS burning tree | H.264 intro decoded via libSceVideodec2; tree scene reached; heavy pipeline stalls. [Screenshot](../../docs/images/yotei-color-routing-post-tree-2026-10-05.png) |

---

## Updating Compatibility Entries

Use the validation utility to verify and format new entries:

```sh
python tools/compatibility/validate.py
```
