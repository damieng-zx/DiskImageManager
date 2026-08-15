# Known issues

Open findings from the August 2026 review and a second review that followed it,
merged and renumbered. Everything ticked off has been removed, so what is here
is what is still true of `dev`; each item has been re-checked against the
sources and the test suite passes (110 tests). Claims from either review that
the code no longer has are gone too, and are not worth raising again.

## High — data loss

- **1. A track of 64KB or more overflows its own size.**
  `TDSKTrack.GetTrackSizeFromSectors` returns a `word` (`DskImage.pas:2036`)
  while a sector holds up to `MaxSectorSize` (32768). Two full-size sectors on
  one track sum to 65536, and the project builds with `OverflowChecks` on
  (`DiskImageManager.lpi:55`), so viewing or saving such an image raises
  `EIntOverflow`. Copy-protected images are exactly where oversized sectors
  turn up. Returning an `integer` costs nothing - `TDSKSide.GetLargestTrackSize`
  already takes one.

- **2. A save that throws leaves a truncated file where a good one was.**
  `TDSKImage.SaveFile` (`DskImage.pas:1083-1104`) opens the target with
  `fmCreate`, which empties it before a byte is written. A `False` result is
  handled - the partial file is deleted - but an exception out of
  `SaveFileDSK`/`SaveFileMGT` walks straight past that and out of `SaveFile`,
  leaving the truncated file behind. Issue 1 is one way to raise one. Writing
  to a temporary name and renaming on success, or deleting in an `except`,
  closes it.

## Medium — wrong results

- **3. Find never searches the sector it starts from.** `TDSKImage.FindText`
  begins at `GetNextLogicalSector(From)` (`DskImage.pas:661`), and
  `dlgFindFind` always passes a sector: the disk's first for an image, side or
  track selection, or the selected sector itself (`Main.pas:2142-2162`). So a
  find from the disk cannot match anything in track 0 sector 0, and a find from
  a sector skips that whole sector. Find and Find Next share the handler with
  no state between them, so searching from the start and continuing from a hit
  have to be told apart before this can just be changed.

- **4. `GetNextLogicalSector` cannot reach MGT side 1.** Raw MGT images number
  side-1 tracks `128 + track` (`DskImage.pas:1046`), matching the directory's
  start-track byte. The walker asks for `Logical + 1` (`DskImage.pas:1605`), so
  after track 79 it looks for logical 80, finds nothing and stops. Everything
  built on it - Find, Strings, `GetData`'s sector walk - sees only side 0 of a
  double-sided MGT disk.

- **5. XDPB sector sizes above 512 are thrown away.** `TDSKSpecification.
  Identify` accepts `128 shl Data[4]` only up to 512 (`DskImage.pas:2704-2708`)
  and otherwise sets `FSectorSize := 0`, which the validity test below then
  reads as "not a spec block at all", falling back to the default 180K +3/PCW.
  PSH=3 (1024 bytes) is ordinary CP/M. `FormatAnalysis`'s own XDPB test already
  allows 128-8192.

- **6. Multi-extent files with headers get inflated sizes.** The extent merge
  adds each extent's record-count size onto the primary's size
  (`filesystem.pas:168`), which for PLUS3DOS and AMSDOS is already the whole
  file. Files over 16KB show an inflated "Actual" size. Extraction itself is
  right - `GetData` clamps to the blocks the file holds.

- **7. CP/M extent numbers ignore the high byte.** `Extent := Data[Offset +
  EXTENT_LOW]` (`filesystem.pas:221`); the real extent number is `EX + 32*S2`.
  Past extent 31 the number wraps to 0, so the continuation is taken for a
  second primary file and listed under the same name instead of being merged.

- **8. Empty CP/M files are dropped from the listing.** A file is kept only if
  it has at least one block (`filesystem.pas:137`), and a zero-length file has
  none. It exists on the disk and takes a directory entry, but never appears.

- **9. `GetData` keeps going after the last partial copy.** The final short
  sector is moved into place but `BytesLeft` and `TargetIdx` are left where
  they were and only the inner loop ends (`filesystem.pas:417-421`). Another
  allocated block after that one writes over the same tail again. The buffer
  cannot overrun - the length is clamped first - but the end of an
  over-allocated file comes out holding the wrong block.

- **10. MGT lists erased entries as live files.** Type 0 is labelled `'Erased'`
  and then added like any other (`mgtfilesystem.pas:83-86,118`), so deleted
  files appear in the listing and can be extracted from blocks another file may
  since have taken.

- **11. PLUS3DOS headers are trusted with a failing checksum.**
  `TryPlus3DOSHeader` records `Checksum` but goes on to take the size, type and
  meta from the header regardless (`filesystem.pas:325-336`); `TryAMSDOSHeader`
  returns early unless its checksum matches (`filesystem.pas:272`). The size is
  clamped to the disk's capacity, so this is a wrong-size/wrong-strip problem
  rather than an unsafe one, but the two paths should agree.

- **12. Spectrum character mapping is wrong.** `GetSpecialChar`
  (`SinclairBasic.pas:164-176`) has the two ranges the wrong way round: $80-$8F
  are the block graphics (rendered `[UDG]`) and $90-$A4 are UDGs A-U (rendered
  `[GRAPH]`, with $A0-$A2 given as space/£/$). The real £ is code $5C, which
  currently prints as a backslash. `TestPoundSign` asserts the wrong code ($A1)
  and has to move with it.

- **13. Colour control parameters are decoded as text.** `DecodeLine` drops any
  byte it does not recognise (`SinclairBasic.pas:249-251`), but INK, PAPER,
  FLASH, BRIGHT, INVERSE and OVER each carry one parameter byte and AT and TAB
  carry two. The control goes, the parameters stay, and turn up in the listing
  as stray characters.

- **14. `DecodeFile` decodes into the variable area.** It takes the length from
  header bytes 20-21, which is program *and* variables, instead of 18-19
  (`SinclairBasic.pas:318,546`), so everything after the program is decoded as
  though it were more BASIC.

- **15. AMSDOS protected BASIC never opens.** The viewer gates on
  `Meta = 'BASIC'` exactly (`AmstradBasic.pas:408,638`, `Main.pas:2367`) while
  a protected file is `'BASIC (protected)'` (`filesystem.pas:291`); the
  Sinclair side uses `StartsWith` and does not have this. Note the tokens in a
  protected file are encrypted, so opening it means implementing the AMSDOS
  descramble as well - otherwise the menu is better left disabled for them.

- **16. A double-sided CPC format is written as PCW DS.** `TfrmNew.GetFormat`
  works out the CPC system/data format from the selected row and then
  overwrites it whenever `Sides <> dsSideSingle` (`New.pas:352-353`), so a
  double-sided CPC disk gets a PCW spec block written to track 0.

- **17. Protection fingerprints search past `DataSize`.** `StrBufPos` is handed
  `Sector.Data`, the whole fixed 32KB buffer, rather than the bytes the sector
  actually holds (`FormatAnalysis.pas:581-650`). Bytes left over from a longer
  sector loaded before it, or never written at all, can match a signature.

## Low

- **18. Rename file does nothing.** `itmRenameFileClick` calls `EditCaption`
  (`Main.pas:456-459`), but `lvwMain.ReadOnly` is set to True on every refresh
  (`Main.pas:1460`), there is no `OnEdited` handler, and no file system write
  path behind it. Either implement it or take the menu item out.

- **19. `.GZ` and gzipped MGT images will not load.** The unpack test is
  case-sensitive (`DskImage.pas:522`), so an upper-case `.GZ` is read as raw
  DSK. After unpacking, the original name is passed on, so the MGT test sees
  `.gz` as the extension (`DskImage.pas:591`) and a gzipped raw MGT image is
  never recognised - DSK survives this only because it is detected by
  signature.

- **20. Options Reset deletes the INI on the spot.** `Settings.Reset` deletes
  the file and reloads defaults (`settings.pas:323-327`) the moment the button
  is pressed (`Options.pas:286-289`); Cancel afterwards has nothing to put
  back. It should move the controls only, like the other options do now, and
  land on OK.

- **21. Range-check warnings from the `LVSCW_AUTOSIZE` constants**
  (`Utils.pas:447-455`) - the only warnings the build still issues.

## Notes

- Systemic themes: untrusted image bytes used directly as sizes or indices;
  a fixed 32KB sector buffer read past what the sector holds; MGT handled as an
  afterthought in code written for DSK.
- Items 1 and 2 compound each other and are the ones worth fixing first.
