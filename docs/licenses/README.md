# Bundled dependency notices

The Windows runner links the following dependencies. These files reproduce the
upstream notices from the source versions pinned in `build.zig.zon`.

| Dependency | Pinned source | Notices |
|---|---|---|
| LibAtrac9 | `shadps4-emu/ext-LibAtrac9`, commit `946e05a9212976626a9f5e52f29c0a7202871f29` | [MIT license](LibAtrac9-LICENSE.txt) |
| minimp3 | `lieff/minimp3`, commit `7b590fdcfa5a79c033e76eacc05d0c3e4c79f536` | [CC0 text](minimp3-LICENSE.txt) |
| FAAD2 | `knik0/faad2`, version `2.11.2` | [GPL text](FAAD2-COPYING.txt), [upstream README and copyright notices](FAAD2-README.txt) |
| Opus | `xiph/opus`, version `1.5.2` | [BSD license](Opus-COPYING.txt), [upstream licensing note](Opus-LICENSE_PLEASE_READ.txt) |
| FreeType | `freetype/freetype`, version `2.14.3` | [FreeType License](FreeType-FTL.txt) |
| Noto Sans Regular | `notofonts/noto-fonts`, commit `ffebf8c1ee449e544955a7e813c54f9b73848eac` | [SIL Open Font License 1.1 and copyright notice](NotoSans-OFL.txt) |

Portions of this software are copyright © 2026 The FreeType Project
(https://freetype.org). All rights reserved.

The unmodified Noto Sans font is embedded as a substitute for system-font
requests. Its source, checksum and scope are recorded in
[the font asset notes](../../src/hle/fonts/README.md).

PS5PCEM's own license is provided in the package's root `LICENSE` file.
