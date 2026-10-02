# Project status and compatibility

[← Documentation index](README.md) · [Project README](../README.md)

Development captures and the furthest repeatable point reached in each observed
title. What the emulator can do subsystem by subsystem is listed separately in
[Implementation status](implementation-status.md).

## Compatibility and progress


Compatibility grades are maintained by the project maintainer; dated notes
below distinguish playthrough reports from development checks. **Playable · Completable** means the title
can be played through; other entries describe the furthest observed milestone.
Performance measurements refer to the current test host. Title content is
supplied locally and is not included in this repository.

| Title | Status | Notes |
|---|---|---|
| **Subnautica: Below Zero**<br><img src="images/subnautica-below-zero-srgb.png" width="240" alt="Subnautica Below Zero snowy opening area after the sRGB lighting fix"> | **Playable · Completable** | October 2, 2026 development checks, PPSA02457 v1.022.125. New Game / Survival reaches the intro and snowy world. The latest unpaused stationary world sample records **12.03 FPS** over 30.01 seconds; earlier 6.46–10.00 FPS samples use different weather/warm-up and are not a controlled comparison. A paused ABBA comparison of buffer alias queries records 11.93–12.23 FPS for full scans and 12.30–12.43 for the bounded index; this small difference does not establish a general gain. CPU scalar resource walks skip vector-only interpretation without dropping GPU instructions; mask invalidation and foreground keyboard input are corrected. Resource preparation, copying and submissions remain expensive; **30 FPS is unmet**. POSIX file writes and full save metadata are fixed: normal Save persists a 213,388-byte archive, and a fresh process recognizes its date and duration. Following several corrupt-pointer failures, mapping ownership checks prevent retired buffer results from reaching a replacement allocation. Two consecutive follow-ups restore the world before another hash access violation prompts a check-to-read race fix. GPU reads and hashes now hold the mapping through completion; the first follow-up restores the save again, but a fresh repeat still crashes in `hash + 0xf0` during loading. The draw stack shrinks from 447,424 to 32,640 bytes; sampled-descriptor updates shrink from 753,720 to 56 bytes. A native regression also fixes failed unmaps leaving removed pages marked readable; the first subsequent process restores the save. **Long-session stability and an FPS gain from these last changes remain unverified.** A released-command-arena regression also passes, without establishing it as the loading fault's cause. The sRGB lighting fix remains in place. One unresolved scalar binding, rendering defects, intermittent loading failures, full playthrough and audio correctness remain open. [New world capture](images/subnautica-below-zero-descriptor-world.png) · [Latest performance, saves and loading checks](development/subnautica-vector-walk-save-2026-10-02.md) · [sRGB fix](development/subnautica-backing-spans-2026-10-01.md) · [New-game investigation](development/subnautica-new-game-2026-10-01.md)
| **Terminator 2D: No Fate**<br><img src="images/live-gameplay.png" width="240" alt="Terminator 2D gameplay with the player character, HUD and desert scene"> | **Playable · Completable** | Completed without reported problems. Correct backgrounds, characters, HUD, textures and colors; warmed-up startup frames measure 22–65 ms on the current test host. [Gameplay capture](images/live-gameplay.png) |
| **Pistol Whip** | Maps the native PS VR2 plugin and Burst module, then starts loading Unity asset archives | Headset, tracking, controller, and host OpenXR support are intentionally deferred |
| **Propagation: Paradise Hotel** | Mounts the 8.8 GiB UE PAK, completes ICU/config bootstrap, opens the cooked Global shader archive, creates AGC shaders, and submits the first DCB | This milestone predates the new synchronization packet constructors and needs a fresh run; VR presentation still has no host headset bridge |
| **Big Helmet Heroes**<br><img src="images/big-helmet-heroes-scalar-history-tutorial.png" width="240" alt="Big Helmet Heroes tutorial after the scalar-load bookkeeping change"> | **Main menu · tutorial scene renders · playability unverified** | September 29 development build: resource checkpoints omit unused scalar-load history, and full scalar analysis avoids redundant history scans on forward visits. Matched menu samples measure 157 ms (6.37 FPS), versus 154.5 ms (6.47 FPS) in the control. Tutorial samples measure 270 ms (3.70 FPS), versus 269 ms (3.72 FPS). No game FPS improvement is demonstrated. Longer isolated scalar-load fixtures are 9–45% cheaper; short walks are effectively unchanged. Copies, resource preparation and GPU waits remain expensive. 30 FPS has not been reached. Shared buffer-pool, page-watch, texture-copy, command-queue and startup fixes remain. Output is 1080p; internal targets can be larger. Visual artifacts remain; full gameplay, save recovery and long-session stability are unverified. [Scalar-history measurements](development/big-helmet-heroes-scalar-history-2026-09-29.md) · [Buffer-pool measurements](development/big-helmet-heroes-buffer-pool-2026-09-29.md) · [Current tutorial capture](images/big-helmet-heroes-scalar-history-tutorial.png) · [Maintainer-approved menu reference](images/big-helmet-heroes-menu.png) |
| **Tetris Effect: Connected** | **Developer logos · readable license screen · Journey Mode selection · gameplay and stability unverified** | Verified on September 24, 2026 with PPSA07923 v2.000.022. The translated composite replaces speculative 4K overrides. Faster tiled clears reduce the median license frame from 235 to 159 ms (about 4.3 to 6.3 FPS). Publishing linear metadata fills and supporting R11G11B10/RGB10A2 DCC clears remove accumulated UI copies and the vertical scene boundary. A 128-target title profile retains the approximately 100-attachment working set; observed Journey frames take 318–396 ms instead of 1127–1276 ms with the smaller cache. Dark interface elements and an unresolved compute texture binding remain under investigation. Later video playback faults in the guest H.264 decoder; a secondary host diagnostic alignment panic is corrected and regression-tested. Longer-run stability and gameplay are not established. The particle capture below records an earlier milestone |
| **The Precinct** | Links the complete six-image guest graph, starts Unity plug-ins through `sceKernelLoadStartModule`, indexes its audio assets, and plays both observed intro movies as synchronized 3840×2160 NV12 video and 48 kHz stereo PCM. It renders the complete 1920×1080 title artwork, opens `PLAY GAME`, and displays the readable `NEW GAME` confirmation shown below. Holding `Triangle` enters the cold world load; an earlier guarded run reached the `Cross` prompt and produced the first verified in-engine gameplay image. Target-thread exception delivery completes Unity's stop-the-world handshake, resident typed storage images preserve its compute graph, and dynamic compute scalars prevent runtime SGPR values from generating a new Vulkan pipeline every frame. Its world-load frame measures 2.1 s where it measured 5.1 s, after descriptor recovery stopped replaying each kernel's prolog once per resource it names | The first world transition still takes several minutes on the current RTX 3070 Ti test host because first-use shader translation, NVIDIA pipeline compilation, synchronous submission, and resource staging remain expensive. The former title- and shader-signature-specific NVIDIA compiler guard has been removed in favor of the general shader path, so the transition needs a fresh end-to-end validation before current gameplay compatibility is claimed |
| **Jets 'n' Guns 2**<br><img src="images/jets-n-guns-2-gameplay.png" width="240" alt="Jets n Guns 2 gameplay with the player ship, HUD and score"> | **Playable · Completable** | Playthrough confirmed by the maintainer on September 15, 2026. Levels, HUD, score, enemies and the parallax scene render correctly in the captured gameplay. Measured frames on the current RTX 3070 Ti host take 70-92 ms, about 11-14 FPS: of a 70 ms frame, 18 ms is spent waiting on the GPU across 33 queue submissions, 11 ms preparing resource checkpoints, and 13 ms staging 894 distinct guest buffers totalling 15 MiB. Audio routing thrashed between two active output ports several times per frame, tearing the mix down and reopening the host device each time; that is fixed in release 0.3.2. [Gameplay capture](images/jets-n-guns-2-gameplay.png) |
| **Asterix & Obelix: Slap Them All!**<br><img src="images/asterix-obelix-gameplay.png" width="240" alt="Asterix and Obelix gameplay in a forest with the HUD and a GO sign"> | **Playable · Completable** | Playthrough confirmed. Gameplay and UI render upright; intro playback works. Observed gameplay typically measures 28–31 ms per frame, with a 3,000-flip development run free of rejected submissions. [Gameplay capture](images/asterix-obelix-gameplay.png) |
| **Cat Quest III**<br><img src="images/cat-quest-iii-world.png" width="240" alt="Cat Quest III island gameplay"> | **Playable · Completable** | Playthrough confirmed. Menus, adventure cards, dialogue, island terrain and colors render correctly in the captured scenes. Latest opening-island samples have a median of 124 ms (about 8 FPS), versus roughly 148 ms before optimization. [Gameplay capture](images/cat-quest-iii-world.png) |
| **Dreaming Sarah**<br><img src="images/dreaming-sarah-gameplay.png" width="240" alt="Dreaming Sarah forest scene with an NPC"> | **Playable · Completable** | Playthrough confirmed on September 15, 2026. Menus, the animated title, world scenes, characters and NPCs render correctly. The title menu and first scene run at the 60 FPS cap on the current RTX 3070 Ti host, measured as 5,280 flips over 90 seconds; the maintainer reports the frame rate falling on the second gameplay scene, which is not yet measured. Loading required restoring `eboot.bin` and `sce_module/libc.prx` from the backups left by the copy's eboot patcher, which had truncated both. [Gameplay capture](images/dreaming-sarah-gameplay.png) |
| **Quake II (2023)**<br><img src="images/quake-ii-gameplay.png" width="240" alt="Quake II gameplay with a lit level, visible enemies and the player's weapon"> | **Playable · Completable** | Playthrough confirmed on September 16, 2026; rendering rechecked on September 25 with PPSA09477 v1.003. Level lighting, textures, weapons and NPCs are visible: the earlier dark-world and missing-model problems are resolved in the observed gameplay. Menus, HUD and controller input work. Buffer reuse and GPU clears reduce transfer overhead; the maintainer reports peaks of 60–70 FPS in lighter scenes, while busy combat scenes still run more slowly. Performance optimization continues; these peaks are not a stable minimum. [Gameplay capture](images/quake-ii-gameplay.png) · [Performance investigation](development/quake2-performance-2026-09-25.md) |
| **Jurassic Park Classic Games Collection** | **Playable · Completable** | Playthrough confirmed. Intro, animated title and collection selection work. Earlier sampled title/selection frames measured about 27/33 ms; performance varies by collection game and hardware |
| **REANIMAL** | Resolves the observed native and firmware modules, plays the company-logo sequence, and sustains the animated 3840×2160 title-menu render graph. Narrow Unity UI intermediates no longer replace the full scanout, dynamic R8 font atlases invalidate stale sampled images, and the buoy background, full title logo, water highlights, and `SELECT` prompt are visible in the live capture below | The central menu-option labels are still reduced to small red marks, so navigation and the transition into gameplay have not been verified. Performance and longer-run stability remain unmeasured, and gameplay is not claimed |
| **Mighty Morphin Power Rangers: Rita's Rewind**<br><img src="images/ritas-rewind-gameplay.png" width="240" alt="Rita's Rewind gameplay with the Red Ranger in the Command Center"> | **Playable · Completable** | Playthrough confirmed by the maintainer on September 24, 2026. The publisher sequence, title menu, and gameplay render and respond to controller input; the capture shows the Red Ranger in the Command Center training stage with the HUD, health bar, objectives, and button prompts. Native cooperative fibers retain suspended guest stacks, and exact `V_SAD_U32`, `V_MUL_HI_I32`, and `V_CVT_FLR_I32_F32` lowering removes the diagnostic shader fallback. The exact guest CRT composite still produces static on the current host, so a strict shader-signature fallback performs the observed 4× RGBA8 scene scale before post-processing. [Gameplay capture](images/ritas-rewind-gameplay.png) |
| **Ghost of Yōtei**<br><img src="images/yotei-null-images-bonus.png" width="240" alt="Ghost of Yotei Digital Deluxe Bonus notice before the October 1 GPU wait"> | **Intro playback · bonus notices · brightness calibration · reaches in-game scenes · not playable** | **October 1 follow-up:** proven all-zero textures now use unbound-image semantics instead of rejecting the shader. Scalar descriptor recovery reuses intermediate values within one call; a nested fixture drops from 504 reads to 18 and is about 4.6× faster in isolation. This is not a game FPS result. Fourteen scalar tests, 16 compute null-image configurations, seven graphics cases and seven neighboring GPU probes pass. Two checks of the installed runner stop before the tree, awaiting GPU completion at flips 740 and 748, and are deliberately terminated after diagnostics. Both record the same last compute program and wait path. Snapshots of 636 and 619 programs have no unknown decoded opcode, and eight retained SPIR-V modules pass validation; runtime correctness remains unverified. A transition frame takes 167.2 seconds, including 164.8 seconds creating 206 compute pipelines. Invalid indirect draws and the control run's corrupt-count failure remain unresolved. Prior runs reached the tree with streaks and excessive brightness; those defects are not established as fixed. Gameplay and 30 FPS remain unverified. Public release archives are unchanged. [Null-image correction, benchmark and live checks](development/yotei-null-images-2026-10-01.md) · [New bonus-notice capture](images/yotei-null-images-bonus.png) · [Earlier tree and command-write evidence](development/yotei-command-buffer-writes-2026-09-30.md) |

## Screenshots

![Subnautica Below Zero snowy opening area after the sRGB lighting fix](images/subnautica-below-zero-srgb.png)

*Subnautica: Below Zero, PPSA02457 v1.022.125, October 1, 2026. An unedited
1765×993 client-window capture with 1080p guest output after starting a new
Survival game. Correct sRGB attachment encoding restores visible material
detail and brighter lighting. The following 30.05-second world sample records
9.49 FPS. Rendering defects, an unresolved scalar binding and intermittent
loading failures remain under investigation; this run did not test a full
playthrough. [Run report](development/subnautica-backing-spans-2026-10-01.md).*

![Big Helmet Heroes opening movie playing in PS5PCEM](images/big-helmet-heroes-intro.png)

*The Exalted Studio logo during Big Helmet Heroes' opening movie, captured
from PS5PCEM's live 1920×1080 presentation output.*

![Big Helmet Heroes main menu with correct characters, lighting and colors](images/big-helmet-heroes-menu.png)

*Maintainer-approved visual reference, captured from the emulator's actual game
window on September 20, 2026. The menu, characters and 3D background render with
correct lighting and colors. Two clean menu-only launches reproduced this
result; gameplay has not been verified.*

![Big Helmet Heroes tutorial scene after the startup fixes](images/big-helmet-heroes-startup-tutorial.png)

*September 28, 2026: a 1765×993 capture of the actual game window after the
GPU-watched file-read and interrupted-save mount fixes. The character, HUD and
windmills render in the tutorial. This is a limited startup check; visual
artifacts remain and a complete playthrough has not been tested. The internal
captured framebuffer is still 3840×2160; this image does not demonstrate a
1080p internal-rendering change.*

![Big Helmet Heroes tutorial after the command-queue fix](images/big-helmet-heroes-coherence-tutorial.png)

*September 29, 2026: an unedited 1765×993 capture of the actual game window.
The character, HUD, windmills and Move/Sprint prompts render after the fix for
false command-header protection. Separate sampled runs measure 6.13 FPS in the
menu and 3.57 FPS in the tutorial. A repeatable FPS improvement is not established;
30 FPS has not been reached. Output is 1920×1080, with larger internal targets.
Visual artifacts remain, and full playability and long-session stability are
unverified.*

![Big Helmet Heroes tutorial after the texture-copy optimization](images/big-helmet-heroes-wide-tiles-tutorial.png)

*September 29, 2026: an unedited capture of the actual game window after the
shared CPU texture-copy optimization. Separate standard-setting runs measure
6.25 FPS in the menu versus 5.85–5.95 FPS in two controls; the completed tutorial
check measures 3.57 FPS without a valid matched comparison. 30 FPS has not been
reached. Output is 1920×1080, with larger internal targets. Visual artifacts
remain; full playability and long-session stability are unverified.*

![Ghost of Yotei intro video decoded and presented by PS5PCEM](images/yotei-intro-video.png)

*A live Ghost of Yotei intro frame decoded from the title's own H.264 stream
through `libSceVideodec2` and presented at 1920×1080. The host decoder receives
the title's Annex B access units, the picture is converted from NV12 with BT.709
coefficients, and playback follows the frame rate reported by the decoded
stream. Build with `zig build build-game-run -Doptimize=ReleaseFast` to reproduce
the measured playback speed. Later development reached the bonus notices,
brightness calibration and parts of the 3D scene/interface; full title-menu
composition and gameplay remain unverified.*

![Ghost of Yotei tree in the September 30 scalar-buffer table validation](images/yotei-scalar-tables-tree.png)

*September 30 development build, unedited game-window capture. This debugger-assisted run completes
all 920 background warmups naturally and reaches the tree, but vertical streaks,
excessive brightness, later block corruption and long pipeline compilation stalls
remain. The native relocation test proves pipeline reuse; a game FPS improvement
is not established. [Current findings and second capture](development/yotei-scalar-tables-2026-09-30.md).*

![Ghost of Yotei tree after the overlapping buffer publication fix](images/yotei-buffer-publication-tree.png)

*September 29, 2026: an unedited game-window capture from the 25-minute
buffer-publication diagnostic run. The wolf and tree were reached without a
logged guest fault; queued background warmups were cancelled during the run.
Vertical streaks, excessive brightness and stray elements remain. No FPS gain,
repeatable startup or playability is established. [Evidence and tests](development/yotei-buffer-publication-2026-09-29.md).*

![Ghost of Yotei wolf brightness screen in the September 29 diagnostic repeat](images/yotei-warmup-priority-wolf.png)

![Ghost of Yotei burning tree in the September 29 diagnostic repeat](images/yotei-warmup-priority-tree.png)

*September 29, 2026: unedited 1765×993 captures of the actual game window in
a diagnostic repeat with default buffer reuse. The updated development runner
reached both screens, but another launch exited with a guest read fault.
The intermittent failure remains unresolved. Diagnostic instrumentation
affects timing; these images do not establish an FPS improvement, 30 FPS or
stable gameplay. [Investigation and validation](development/yotei-warmup-priority-2026-09-29.md).*

![Ghost of Yotei tree scene captured from PS5PCEM](images/yotei-tree-scene.png)

*Captured directly from the emulator's live client area at 1624×941 on
September 23, 2026, using a development build.*

![Terminator 2D gameplay rendered by PS5PCEM](images/live-gameplay.png)

*A live Terminator 2D gameplay frame produced by the current guest VS/PS,
sampled-texture, render-target, and Vulkan presentation paths. Texture alpha,
component swizzles, and sRGB sampling now preserve the title's intended color
balance.*

![Jets 'n' Guns 2 tutorial gameplay rendered by PS5PCEM](images/jets-n-guns-2.png)

*A live 3840×2160 Jets 'n' Guns 2 tutorial frame reached through `START GAME`
and the title's loading screen. The ship, HUD, layered level art, lighting, and
text are produced by the guest multi-draw, sampled-texture,
persistent-render-target, compute, and VideoOut paths.*

![Asterix & Obelix: Slap Them All! gameplay rendered by PS5PCEM](images/asterix-obelix-gameplay.png)

*A live 1920×1080 Asterix & Obelix: Slap Them All! gameplay frame captured at
flip 512. The scene, characters, HUD, and prompt come from the title's guest
draws. The final fullscreen compositor remains GPU-resident, while scanout
preserves the guest viewport's vertical orientation without a per-frame
host-memory round trip.*

![Quake II (2023) gameplay with lighting, visible enemies and a weapon rendered by PS5PCEM](images/quake-ii-gameplay.png)

*Captured directly from the emulator's live client area at 1765×993 on
September 25, 2026. The attract demo shows the lit level, textured enemies,
player's hand and weapon. The earlier dark-world and missing-NPC rendering
problems are resolved in this scene. Frame rate still varies with scene
complexity; work on the remaining performance dips continues.*

![Mighty Morphin Power Rangers: Rita's Rewind intro rendered by PS5PCEM](images/ritas-rewind-intro.png)

*A live 1920×1080 Rita's Rewind publisher/title intro frame produced by the
guest indexed vertex, sampled fragment, render-target composition, and VideoOut
paths. The corresponding animation and audio remain smooth in the observed
run; this is an intro milestone rather than a gameplay claim.*

![Mighty Morphin Power Rangers: Rita's Rewind post-menu scene rendered by PS5PCEM](images/ritas-rewind-post-menu.png)

*Rita's Rewind after the title menu, rendered from the real 480×270 guest scene
target and carried through the 1920×1080 CRT/post-processing chain. The strict
CRT-composite compatibility path removes the former full-screen static while
preserving the title's pixel-art presentation.*

![Mighty Morphin Power Rangers: Rita's Rewind gameplay rendered by PS5PCEM](images/ritas-rewind-gameplay.png)

*Rita's Rewind gameplay: the Red Ranger in the Command Center training stage,
with the HUD, health bar, objective checklist, and `Double Jump` prompt,
captured from a live game-run window on September 24, 2026.*

![The Precinct title menu rendered by PS5PCEM](images/precinct-title-menu.png)

*The Precinct's live 1920×1080 title menu and `NEW GAME` confirmation, composed
by the guest graphics and compute passes after both SceAvPlayer intro movies.
Structured shader control flow restores the UI text, while fixed-function DCC
decompression no longer executes its constant-white helper shader over the
completed scene. This capture predates the now-verified transition into the
first in-engine gameplay scene.*

![Jurassic Park Classic Games Collection game selection rendered by PS5PCEM](images/jurassic-park-menu.png)

*Game selection with cover art, navigation arrows, and an animated preview.
This earlier development capture precedes the maintainer's full-playability
confirmation.*

![REANIMAL partial title menu rendered by PS5PCEM](images/reanimal-menu-partial.png)

*A live REANIMAL title-menu frame produced by the guest Unity render graph. The
animated buoy background, title logo, water highlights, and `SELECT` prompt are
visible without the former full-screen stretch. The missing central option
labels remain an active rendering issue, so this capture is not a complete menu
or gameplay claim.*

![Tetris Effect first guest-rendered particle frame](images/tetris-effect-first-render.png)

*The first recognizable Tetris Effect render produced by the title's startup
graph: 595 guest draws and 63 compute dispatches complete without a rejected
draw. This 1920×1080 `R11G11B10_FLOAT` intermediate is converted for display
because the registered 3840×2160 VideoOut target was still black in that run.
This historical capture predates the September 24 startup rendering fix; it
does not document gameplay.*


![Cat Quest III language modal rendered by PS5PCEM](images/cat-quest-iii-language.png)

*The language list now retains its text and clips it inside the panel; the
stencil pop no longer paints a white rectangle over the labels.*

![Cat Quest III opening island rendered by PS5PCEM](images/cat-quest-iii-world.png)

*Island gameplay with the HUD, restored mountains, blue sea and sky, and
correct character colors. Cat Quest III is fully playable according to the
project maintainer's September 8 playtest.*

![Cat Quest III opening gameplay dialogue rendered by PS5PCEM](images/cat-quest-iii-dialogue.png)

*Captain Cappey's dialogue remains readable over the rendered island scene.*

![Cat Quest III adventure selection cards rendered by PS5PCEM](images/cat-quest-iii-catventure.png)

*Catventure selection now displays the slot artwork, labels, add buttons and
scroll arrows, with the clipping mask linked to the correct shader export.*

![Big Helmet Heroes tutorial after the buffer-cache optimization](images/big-helmet-heroes-buffer-recency-tutorial.png)

*September 29, 2026: an unedited capture of the actual game window. Separate
matched runs measure 6.21 FPS in the menu and 3.61 FPS in the tutorial.
Sample ranges overlap the controls; a repeatable FPS gain is not established.
30 FPS has not been reached. Output is 1920×1080, with larger internal targets.
Visual artifacts remain; full playability and long-session stability are unverified.*

![Big Helmet Heroes tutorial after the page-watch optimization](images/big-helmet-heroes-page-watches-tutorial.png)

*September 29, 2026: an unedited capture of the actual game window. Separate
matched runs measure 6.54 FPS in the menu and 3.61 FPS in the tutorial.
Sample ranges overlap the controls; a repeatable FPS gain is not established.
30 FPS has not been reached. Output is 1920×1080, with larger internal targets.
Visual artifacts remain; full playability and long-session stability are unverified.*

![Big Helmet Heroes tutorial with completed Vulkan buffer reuse](images/big-helmet-heroes-buffer-pool-tutorial.png)

*September 29, 2026: an unedited 1765×993 capture from the actual game
window, after profiled flip 300. The default spare pool reuses compatible
Vulkan buffers after GPU completion. Separate matched samples measure 6.54 FPS
in the menu and 3.77 FPS in the tutorial; buffer creation and destruction time
in the tutorial falls from 28.8 to 15.8 ms. Frame ranges overlap, so a repeatable
FPS gain is not established. 30 FPS has not been reached. Output is 1920×1080,
with larger internal targets. Visual artifacts remain; full playability and
long-session stability are unverified.*

![Big Helmet Heroes tutorial after the scalar-load bookkeeping change](images/big-helmet-heroes-scalar-history-tutorial.png)

*September 29, 2026: an unedited 1765×993 capture of the actual game window,
about 67 seconds after launch following profiled flip 300. The HUD, windmills,
Move/Sprint prompts and a blue circular effect are visible. Separate matched
samples measure 6.37 FPS in the menu and 3.70 FPS in the tutorial. No game FPS
improvement is demonstrated. Longer isolated scalar-load fixtures are 9–45%
cheaper; short walks are effectively unchanged. 30 FPS has not been reached.
Output is 1920×1080, with larger internal targets. Visual artifacts remain;
full playability and long-session stability are unverified.*
