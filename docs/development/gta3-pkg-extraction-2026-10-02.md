# GTA III: Definitive Edition package extraction — October 2, 2026

The debug package for **PPSA03527 v1.007**, content ID
`UP1004-PPSA03527_00-GTATHREE00000001`, now extracts completely. The installed
extractor previously wrote the 27 CNT metadata files and then returned
`InvalidPfs` before writing the application tree.

## Cause and correction

The NAPS reader aligned the end of the u2c lookup table to 16 bytes. This
package's CblockInfo table starts on an 8-byte boundary instead:

| Field | Observed value |
|---|---|
| Package size | 5,362,543,328 bytes |
| NAPS layout size | 867,968 bytes |
| File-offset entries | 24 |
| u2c entries | 2,538 |
| End of u2c data | `0xa4464` |
| Correct CblockInfo start | `0xa4468` |
| Previous calculated start | `0xa4470` |
| CblockInfo records | 21,676 |

Starting eight bytes late corrupts the record interpretation and produces
adjacent apparent run-base markers, which the block walker rejects. Both the
parser and its required-length calculation now use 8-byte alignment after
u2c. The file-offset table handling and payload decoder are unchanged. This
is a shared format correction, with no title-ID or package-size exception.

## Validation

- Reproduced the original failure with the previously installed extractor.
- All **21 package tests pass** in ReleaseSafe, including a new fixture whose
  CblockInfo start is 8-byte aligned but not 16-byte aligned. It covers exact
  and padded blobs and rejects a truncated final record.
- The retained Big Helmet Heroes NAPS layout still starts CblockInfo at
  `0x925b0`; all 43,581 record slices are unchanged. This is a mapping check,
  not another full extraction of that title.
- The ReleaseFast extractor build succeeds. GTA III extraction exits **0**:
  27 CNT files plus 21 application files, including `eboot.bin` and six PRX
  modules. Application output totals **5,314,993,203 bytes**; all 48 files
  together total **5,364,623,921 bytes**.
- The inner superblock matches logical mount size `0x13d260000`. Its block
  map contains 20,310 blocks: 20,003 stored and 307 Kraken-compressed.
- Both Unreal PAK index SHA-1 hashes match their archive footers. The main
  PAK is 5,111,879,883 bytes; the second is 17,614,663 bytes. The executable
  and all six modules have SELF headers. A SHA-256 output manifest is retained
  locally; the PAK index check does not independently verify every asset.

## Installed tool and local output

The matching EXE and PDB replace `zig-out/bin/pkgextractor.exe` and
`zig-out/bin/pkgextractor.pdb`, so the local launcher's Extract PKG action
uses the correction. The extractor EXE SHA-256 is
`2b8aa47a1ef038698bdde2fdf97160841db8f1d3de0682d11062130b1ef2a5f7`.

The complete application is available locally at `E:\PS5 GTA III`.
Evidence, the previous binary, build/test logs and the output manifest are in
the ignored `out/gta3-pkg-20261002/` directory. Package and application bytes
are not committed. The separate RusSound package was not applied.

This check covers **extraction only**. The title was not launched, and no
boot, rendering or playability status is claimed. Public release archives
have not been replaced; this correction is in the development source and
the local installed tool.
