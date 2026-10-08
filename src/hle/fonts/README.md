# Font rasterizer assets

`NotoSans-Regular.ttf` is an unmodified, freely licensed fallback for firmware
system-font requests. It is not a console firmware font. The current fallback
covers Latin, Greek and Cyrillic; it does not substitute every system font or
provide CJK coverage. Games can supply their own TrueType/OpenType fonts through
`sceFontOpenFontMemory`.

- Source: [notofonts/noto-fonts](https://github.com/notofonts/noto-fonts/blob/ffebf8c1ee449e544955a7e813c54f9b73848eac/hinted/ttf/NotoSans/NotoSans-Regular.ttf)
- Commit: `ffebf8c1ee449e544955a7e813c54f9b73848eac`
- SHA-256: `b85c38ecea8a7cfb39c24e395a4007474fa5a4fc864f6ee33309eb4948d232d5`
- License: [SIL OFL 1.1](../../../docs/licenses/NotoSans-OFL.txt)

FreeType 2.14.3 is fetched with a pinned content hash in `build.zig.zon` and
statically linked. `ps5pcem_ft_modules.h` selects TrueType, CFF, SFNT and their
support modules. GPOS pair kerning is enabled. No external font DLL or host font
installation is required. See the [FreeType license](../../../docs/licenses/FreeType-FTL.txt).
