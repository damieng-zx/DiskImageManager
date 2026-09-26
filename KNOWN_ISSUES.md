# Known issues

Open, actionable findings after the six high-priority fixes. Historical issue
IDs are retained for reference; resolved items are removed. The application
enables overflow checks but not range checks
(`Source/DiskImageManager.lpi:53-56,249-252`): unchecked array indices can read
or write outside an array without a Pascal range exception. The test project has
its own compiler settings. Do not infer that every read beyond a sector's
`DataSize` is a heap overread: `TDSKSector.Data` is a separately allocated,
32,769-byte buffer.

## Medium — incorrect results and unhandled malformed input

- **3. Find skips its starting sector.** `TDSKImage.FindText` advances past
  non-nil `From` (`Source/DskImage.pas:679-702`), while `dlgFindFind` passes the
  first sector when searching from an image, side, or track
  (`Source/Main.pas:2144-2174`). The first sector is never searched. Distinguish
  a new search from Find Next before changing the start semantics.

- **4. The logical-sector walker stops before MGT side 1.** MGT side-1 tracks
  use logical IDs `128 + track` (`Source/DskImage.pas:1085-1088`), but
  `GetNextLogicalSector` asks for `Logical + 1` (`2130`). After side-0 track 79,
  it seeks track 80, not 128. Update traversal for MGT numbering and check
  Find, Strings, and file extraction across the side boundary.

- **5. XDPB sector sizes over 512 bytes are rejected.**
  `TDSKSpecification.Identify` (`Source/DskImage.pas:3236-3253`) accepts a
  sector size only up to 512, so a legitimate larger CP/M size falls back to
  the default +3/PCW specification. Support the range the model can represent
  (the analysis probe in `Source/FormatAnalysis.pas:54-58` allows 128-8192).

- **6. Multi-extent files with headers show inflated sizes.** The extent merge
  adds directory-record sizes onto the primary (`Source/filesystem.pas:154-172`)
  even when a PLUS3DOS/AMSDOS header has already supplied the whole-file size.
  Keep the header's authoritative length while still merging allocated blocks.

- **7. CP/M extents ignore the high extent byte.** `ReadFileEntry` takes only
  `EX` at `Source/filesystem.pas:221`; extent order also needs `S2` (commonly
  `EX + 32*S2`). Past extent 31, continuation entries can be treated as new
  primary files. Decode and sort using the full extent number.

- **8. Empty CP/M files disappear from directory listings.**
  `Source/filesystem.pas:133-145` retains entries only if `Blocks.Count > 0`.
  A legitimate empty file can have no blocks. Preserve valid named, zero-length
  primary entries while still filtering deleted/invalid entries.

- **9. Extraction can overwrite the last partial sector.**
  `TCPMFile.GetData` (`Source/filesystem.pas:409-435`) copies `BytesLeft` on the
  short-final-sector branch, but neither clears `BytesLeft` nor exits the outer
  block loop. An additional allocated block can overwrite that tail. Stop
  copying once the requested length is reached.

- **10. MGT lists erased entries as files.** Type 0 becomes `Erased`
  (`Source/mgtfilesystem.pas:116-118`), but `Directory` can still add it when
  its old name and allocation count remain (`80-86`). Exclude erased entries
  before adding them.

- **11. PLUS3DOS headers are trusted despite a bad checksum.**
  `Source/filesystem.pas:318-352` records a failing checksum but still uses
  its size, type, and metadata; the AMSDOS path rejects bad checksums at `272`.
  Decide whether to treat a failing PLUS3DOS header as plain data or expose
  it as suspect without trusting its fields. The size is capped elsewhere.

- **12. Spectrum graphics, UDG, and pound-sign mapping is wrong.**
  `Source/SinclairBasic.pas:164-176` labels `$80..$8F` as UDG instead of block
  graphics, treats `$90..$A2` as graphics/ASCII rather than UDGs, and
  represents `$A1` as `£` instead of the Spectrum's `$5C`. Correct the ranges,
  character mapping, and the pound-sign assertion in `TestSinclairBasic.pas`;
  account for the mode-dependent `$A3..$A4` tokens when doing so.

- **13. BASIC colour/position control parameters leak into text.**
  `Source/SinclairBasic.pas:189-253` skips control bytes without consuming
  their one- or two-byte parameters. Decode or skip each complete control
  sequence so parameter bytes cannot appear as program text.

- **14. `DecodeFile` includes the BASIC variable area.** Both output paths
  read the program length from header bytes 20-21
  (`Source/SinclairBasic.pas:318,546`), which describe program plus variables,
  instead of program-only bytes 18-19. Limit decoding to the program area.

- **15. Protected AMSDOS BASIC cannot be opened in the viewer.** Protected
  files are tagged `BASIC (protected)` (`Source/filesystem.pas:289-295`), but
  viewing requires `Meta = 'BASIC'` (`Source/AmstradBasic.pas:408,638` and
  `Source/Main.pas:2379`). Supporting them also requires descrambling the
  protected token stream; loosening the menu check alone is insufficient.

- **16. A double-sided CPC format writes a PCW DS spec block.**
  `Source/New.pas:367-378` chooses CPC System/Data and then overrides it with
  PCW DS whenever there are two sides. Preserve the CPC selection when writing
  the first-sector specification.

- **17. Protection signature scans ignore `DataSize`.**
  `Source/FormatAnalysis.pas` passes entire fixed sector arrays to `StrBufPos`,
  starting at `581-670` and recurring at `761,766,865,907,915,1028,1038,1049`,
  `1117-1118,1135-1137,1169,1182,1293,1300,1504`. Scans can inspect bytes
  outside the sector's logical data, for example after editing/shortening a
  sector. Add a length-aware search and use each sector's `DataSize` at every
  signature call, not just the first group. The separate `StrBlockClean` at
  `879` already has a sufficient length guard and is not part of this issue.

- **26. `GetAllStrings` mishandles empty sectors and the final run.**
  `Source/DskImage.pas:2321-2360` reads `Data[Index]` before checking
  `DataSize`. For a zero-length sector this consumes one byte outside its
  logical data (but inside its allocated buffer). A qualifying printable run
  ending at the last sector is never flushed. Skip empty sectors before
  reading and apply the same finish logic at end of traversal.

- **27. A truncated TD0 leaves unpopulated sectors in its last track.**
  The failure exits at `Source/DskImage.pas:1333-1345` do not reduce the
  track's count to the number read, unlike `1301-1306`. The image is marked
  corrupt, and `SaveFile` refuses it (`1404-1408`), so this is inconsistent
  in-memory geometry, **not** a normal-save corruption path. Trim the track on
  every incomplete-sector exit.

- **28. Offset-Info parsing has no complete-block length checks.**
  `Source/DskImage.pas:1036-1049` checks only that one byte remains before
  `ReadBuffer` of the 14-byte marker. If the marker matches, it reads a track
  entry and sector offsets for every track without checking remaining bytes.
  Validate the marker and each entry/offset before consuming them, marking a
  truncated image corrupt instead of letting a stream-read exception escape.

- **29. A short recognized DSK raises on its Disk-Info block.**
  `CreateFromStream` detects a format using a partial header
  (`Source/DskImage.pas:576-602`); `LoadFileDSK` then unconditionally reads all
  256 bytes at `774`. Check the remaining length and report a corrupt/truncated
  image rather than raising a raw stream-read exception.

- **30. The disk specification reads beyond a short sector's `DataSize`.**
  `Identify` checks for 11 bytes at `Source/DskImage.pas:3194`,
  then reads `Data[15]` at `3247`. `Write` (`3267-3304`) checks for a first
  sector, not 16 usable bytes; changes beyond `DataSize` may not be persisted.
  Require the full 16-byte spec block before reading or writing it. These
  indexes are inside the fixed buffer, not heap out-of-bounds accesses.

- **31. INI map dimensions bypass the Options dialog's limits.**
  `Source/settings.pas:204-205` reads width and height without validation;
  `Source/Main.pas:1053,1912-1913` passes them to `TSpinDiskMap.CreateImage`
  (`Source/DiskMap.pas:676-689`). Zero, negative, or excessive dimensions can
  make rendering fail or request excessive memory. Clamp on load and at the
  bitmap boundary, consistent with the Options control limits.

## Low — UI, interoperability, and hardening

- **18. Rename file has no effect.** `Source/Main.pas:456-459` calls
  `EditCaption`, but the list is set read-only at `1460`, with no edit handler
  or filesystem rename operation. Implement the operation or remove the menu
  action.

- **19. `.GZ` and gzipped raw MGT files do not load.** The gzip-extension test
  is case-sensitive (`Source/DskImage.pas:531`), and MGT detection later checks
  the unstripped original extension (`612`). Normalize extension case and
  identify the decompressed payload using its underlying filename/type.

- **20. Options Reset persists despite Cancel.** `Settings.Reset` deletes the
  INI immediately (`Source/settings.pas:323-327`), when Reset is clicked
  (`Source/Options.pas:286-289`). Reset only the pending dialog values and
  persist them on OK.

- **21. The Win32 list-width constants emit range warnings.**
  `Source/Utils.pas:447-455` assigns `LVSCW_AUTOSIZE*` constants to column
  widths. Check the intended signed/API types and remove the conversion
  warnings without changing the autosize behaviour.

- **32. The sort comparer can index a negative subitem.**
  `Source/Comparers.pas:21-26` subtracts one from `SortColumn`, handles `-1`
  for the caption, but sends `-2` to `SubItems` when the current view sets
  `SortColumn := -1` (`Source/Main.pas:1449-1451`). Treat any unset/negative
  column as the caption, and check subitem counts before indexing.

- **33. Size parsing can overflow during a list sort.**
  `TryStrToFileBytes` multiplies an arbitrary parsed integer by 1024 or
  1,048,576 (`Source/Comparers.pas:79-104`) under overflow checks. Current
  display values usually avoid that range, but a large `KB`/`MB` value would
  raise in the sort callback. Parse into `int64`, check the representable
  range, and fall back to text comparison if it will not fit.

- **34. TD0 comments above 65,535 bytes get an incorrect length.**
  `Source/DskImage.pas:1804-1821` casts the full comment length to `word`
  for the TD0 header while writing the full text. Reject or deliberately
  truncate an over-limit comment before calculating its length/CRC and
  writing the body.

## Test coverage to add when changing the codec

- **35. Huffman reconstruction has no targeted regression test.**
  `THuffTree.Reconst` runs only when the root frequency reaches `$8000`
  (`Source/LZHuf.pas:95-145`). The largest noise round trip in
  `Source/Tests/TestLZHuf.pas:132-146` is 20,000 bytes; repetitive long inputs
  produce too few symbols. Add a reproducible, sufficiently long
  incompressible round trip (e.g. at least 40,000 bytes) that reaches
  reconstruction, ideally checking a known compatible compressed result too.

- **36. Position-code lengths lack deliberate coverage.**
  `Source/LZHuf.pas:44-54,216-250,473-480` defines 64 position prefixes of
  lengths 3-8. Existing tests do not explicitly exercise every length,
  particularly the longer prefixes and decoder's extra-bit loop. Add
  deterministic data/fixtures that cover each prefix length and assert the
  decoded bytes; do not rely on an encoder/decoder round trip alone to detect
  matching regressions on both sides.

- **37. The real Teledisk fixture checks only its opening bytes.**
  `TestDecodesRealTelediskStream` (`Source/Tests/TestLZHuf.pas:175-207`)
  asserts a few header fields and a 37-byte comment, rather than the complete
  decoded output. Use a complete, trusted compressed fixture and compare its
  expected decoded payload, or add independent assertions later in the stream.
