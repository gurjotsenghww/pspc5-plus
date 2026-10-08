# Big Helmet Heroes startup and GPU-watched file destinations — September 28, 2026

Big Helmet Heroes could stop on its first black frame or later during resource
loading while the process and audio threads remained alive. The guest's loading
thread waited indefinitely after an APR file read returned `EIO` (`0x80020005`).

## Reproduction

Three launches of the previous installed runner (`6822be6`) reproduced the
startup stall at different points. A run with `PS5_SYNC_SUBMISSIONS=1`, the
preceding `0c44bf5` runner, an older September 27 runner, and a clean working
directory also stalled. Disabling GPU page tracking allowed startup to continue
into the tutorial scene. The final fix keeps page tracking enabled.

The file trace identifies an APR read of 1,048,725 bytes followed by a failed
`sceKernelAprSubmitCommandBufferAndGetResult`. A regression test reproduced the
same `IoFailed` result when reading a regular file into GPU-watched guest pages.

Fixing I/O alone exposed a second startup problem in the existing working
directory: zero-byte save payloads from interrupted runs. Save enumeration
already hid these slots, but a mount by name treated them as existing saves.
The title entered its save recovery path, including an unsupported
`sceSaveDataDelete` call, and remained on its loading overlay. The named mount
check removes the invalid existing-save result; it does not add that deletion
API. A clean save directory could proceed into the tutorial with the I/O fix alone.

## Cause and fix

The GPU cache temporarily makes observed guest pages read-only at the host
level. Native CPU stores trigger the emulator's write-fault handler, which
restores write access and invalidates the page's cached generation. Windows
file I/O writes from the kernel and returns an error for that protected buffer;
it does not take the same user-mode fault path. The file layer previously passed
the guest destination directly to the operating system.

Reads into writable guest mappings now use a bounded 64 KiB host TLS buffer.
HLE calls can execute on guest stacks, so keeping scratch in host thread-local
storage avoids watched stack pages and an extra 64 KiB guest-stack requirement.
Each returned chunk is copied through `AddressSpace.write`, which restores page
access and updates GPU tracking. This also covers a page rearmed by a renderer
while the operating system is reading the scratch buffer. Ordinary host buffers
keep the existing direct I/O path. The mapping attachment follows libkernel's
address-space lifetime.

The shared `read` and `pread` path covers normal file calls, AIO and APR without
a title-ID condition. Positional reads, sequential offsets, short reads and EOF
semantics are preserved. There is no allocation proportional to the file size,
and no cache reset or modification of installed game assets.

Named save mounts now apply the same payload check as save enumeration. A
non-creating mount reports an incomplete slot as missing and leaves the active
mount unchanged. A creating mount reports it as new so the title can initialize
it. Existing nonempty payloads, including nested files, remain loadable. No
save files are deleted; the pre-test save directory was also backed up locally.
This does not implement general recovery or deletion of nonempty corrupt saves.

## Validation

The new file regression fails with `IoFailed` before the read-path change and
passes afterward. It covers a read spanning multiple scratch chunks, an unaligned
destination, positional and sequential offsets, short reads, EOF, rearming and
unchanged neighboring page generations. A separate APR regression checks that
the mapping attachment is used, the byte count is published, and a successful
submission can be waited and retired. The save regression initially reports
`expected .missing, found .existed`.
It checks metadata-only and zero-byte payloads, preservation of an active mount
and on-disk metadata, initialization and successful remount after writing data.
All 539 HLE tests pass in ReleaseSafe.

Three consecutive launches of the final runner used the existing repository
working directory, shader cache and save files, with GPU page tracking enabled:

| Run | Duration | Input mode | Observed result |
| --- | --- | --- | --- |
| 1 | 90 seconds | Default CLI automatic input | Tutorial character, HUD and windmills render. |
| 2 | 90 seconds | Controller mode, no automatic input | Main menu shows New Game and Options. |
| 3 | 90 seconds | Default CLI automatic input | Tutorial scene renders again. |

Each run was stopped by the test harness at its time limit. All three have a
visually inspected game-window capture and no reported guest fault or device
loss. The first run also enabled failed APR/save-call tracing: the failed APR
submission no longer appears. Unsupported save deletion is still reported on a
separate save path; this work does not claim general save support.

Before moving the scratch buffer to host TLS, the same two fixes also passed two
180-second default launches and a 120-second menu-only launch. The new captures
linked below come from the final executable, whose hash is recorded here.

A 120-second Subnautica: Below Zero regression run on the same executable
reached the 1920×1080 title screen and, after Enter at the prompt, displayed
Play, Options and Credits. No guest fault or device loss was reported. This
check covers startup and menu loading, not gameplay or a new FPS comparison.

This is startup validation, not a controlled FPS comparison. Scene loading can
still pause for shader compilation, and these changes do not establish 30 FPS.

[New menu capture](../images/big-helmet-heroes-startup-menu.png) ·
[New tutorial capture](../images/big-helmet-heroes-startup-tutorial.png). Both
are unedited 1765×993 captures of the actual game window. The internal
framebuffer remains 3840×2160; these fixes do not lower internal resolution.

The existing [menu reference](../images/big-helmet-heroes-menu.png) is retained.
Long-session stability and a complete playthrough are not established by these
startup checks. The public 0.3.2 download predates this development fix.

The installed runner is `zig-out/bin/game-run.exe`, built in ReleaseFast on
September 28, 2026 at 15:21:11 (Europe/Minsk), 38,427,136 bytes. SHA-256:

```text
CA4A6997CD78B5EB8469FC0F352FC4A378F2A97119DB4EFC35BC713BA9647965
```
