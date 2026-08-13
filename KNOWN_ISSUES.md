# Known issues

Working list from the August 2026 review, to be ticked off as they are fixed.
Findings are verified against the sources; the test suite passed (83 tests)
before fixes started.

## High — crashes/OOM on malformed or corrupt images

- [x] **1. Unclamped +3DOS file size.** `filesystem.pas` — the 32-bit PLUS3DOS
  length was read straight from untrusted header bytes into `Size`
  (`TryPlus3DOSHeader`) and used as the `SetLength` size in `GetData`. Values
  >= $80000000 wrap negative (ERangeError), large values attempt multi-GB
  allocations. Headerless extents could also compute negative sizes (RC=0
  with BYTES_IN_LAST_RECORD > 0).
  _Fixed on `dev`: header sizes clamped to disk capacity at parse time
  (PLUS3DOS and AMSDOS), `GetData` clamps to the blocks the file actually
  holds, extent sizes floored at zero. Covered by `TestCPMFileSystem` (5
  tests)._

- [x] **2. Unclamped FDCSize table index.** `DskImage.pas:886` reads `FDCSize`
  as a raw byte; `ListViewPresenter.pas:173,414` index
  `FDCSectorSizes[Sector.FDCSize]` which is `array[0..8]`. Sector Properties
  even lets the user set 0–255.
  _Fixed: `GetFDCSizeBytes` answers 0 for a code the controller does not define; the sector list says "invalid" rather than printing whatever followed the table. Covered by 2 tests._

- [x] **3. Unguarded empty-disk access.** `IsTrackSizeUniform` reads
  `Side[0].Track[0]` unconditionally (`DskImage.pas:1599`); called from
  Save-As-Standard (`Main.pas:1722`, no guard) and the image info view
  (`ListViewPresenter.pas:272`, guards sides but not tracks). Same family:
  `BootableOn` via `itmCloseAllExceptBootSectors` (`Main.pas:1060`) and
  `SaveFileDSK` (`DskImage.pas:1118`).
  _Fixed: `IsTrackSizeUniform` walks the tracks it has, so no tracks is trivially uniform, and the image view asks the side for its largest track instead of indexing the first of none. Covered by 2 tests._

- [x] **4. Uncasted data rate / recording mode.** File bytes cast straight to
  enums (`DskImage.pas:873-874`); invalid ordinals then index
  `DSKDataRate[...]/DSKRecordingMode[...]` (`ListViewPresenter.pas:149-150`),
  and Track Properties applies `ItemIndex` (-1) back to the track
  (`TrackProperties.pas:196`).
  _Fixed: `ToDataRate`/`ToRecordingMode` in `DskImage.pas` answer Unknown for
  anything outside the enum, used at the load site and at all three combo box
  writes (Track Properties, and both in New). The image records one message
  when a file held such a value. Covered by 3 tests in `TestDskImage`._

## Medium — wrong results

- [ ] **5. Multi-extent files with headers get inflated sizes.** The extent
  merge adds each extent's record-count size onto the primary's header size
  (`filesystem.pas:168`), which is already the whole file for
  PLUS3DOS/AMSDOS; files > 16 KB show an inflated "Actual" size and extract
  trailing garbage zeros.
  _Note: the issue-1 `GetData` clamp stopped the garbage-zeros extraction;
  the inflated displayed size remains._

- [x] ~~**6. +3DOS BASIC meta reads the wrong header fields.**~~ Withdrawn —
  output verified correct against real disks. The header stores the program
  length at 16-17 and the autostart line at 18-19, which is what the code
  reads; the CODE "start,length" order is right too.

- [ ] **7. Spectrum character mapping wrong in `GetSpecialChar`.**
  `SinclairBasic.pas:164-176` — $80-$8F are block graphics (rendered
  `[UDG]`), $90-$A4 are UDG A-U (rendered `[GRAPH]`, and UDG Q/R/S $A0-$A2 as
  space/£/$); the real £ (code $5C) prints as backslash. `TestPoundSign`
  asserts the wrong code ($A1).

- [x] **8. Disk map holds a dangling side after close.** Nothing sets
  `DiskMap.Side := nil` when an image closes (`Main.pas:1620-1642`); with the
  last image closed while its map is shown the map stays visible, and
  `SetSide`'s pointer-equality shortcut (`DiskMap.pas:611`) won't clear stale
  hits if the address is reused → use-after-free on repaint/hover/click.
  _Fixed: `DetachImageProperties` now also drops the map's side and hides it
  when the image being closed owns it, and `SetSide` clears the hit regions
  and hover unconditionally rather than only when the side pointer differs.
  `itmSaveMapAsClick` no longer assumes there is a side. Not unit tested - it
  is form wiring; worth exercising by closing an image with its map on show._

- [x] **9. SmallInt truncation for sector-size default.** `SectorProperties.pas:255`
  assigns `SectorSize * 256` to `TUpDown.Position` (512→0, 128→−32768);
  should be `SectorSize` itself.
  _Fixed: the track sector size is already a byte count, so it is used as-is._

- [ ] **10. Viewer forms leak (and nil-deref) on decode errors.**
  `FileViewer.pas:51-76`, `ZXScreenViewer.pas:68-75`, `CPCScreenViewer.pas`
  do Create → Load* → Show with no try/except; an exception mid-load leaks the
  form. `EnsureViewer` can also leave `FViewer = nil` before
  `FViewer.LoadRTF` (`FileViewer.pas:99-103,163`).

## Low

- [ ] **11. DarkBlankSectors setting round-trip broken.** Menu toggles update
  only the control (`Main.pas:1753-1757,1775-1779`); the Options checkbox
  writes settings immediately, bypassing OK/Cancel (`Options.pas:292-295`).
- [x] **12. Copy-paste .lfm wiring.** `SectorProperties.lfm:427`
  (`edtFDCSize.OnChange = edtSizeChange`); `Options.lfm:448`
  (`edtMinString.OnChange = edtTrackMarksChange`).
- [x] **13. Malformed save dialog extension.** `dlgSave.DefaultExt = '.*.dsk'`
  (`Main.lfm:496,783`); should be `dsk`.
- [ ] **14. Nav-history index not remapped** after unresolvable entries are
  dropped (`Main.pas:896-901`).
- [x] **15. Temp folder leak on every drag-out** (`Main.pas:2139-2166`).
- [x] **16. INI values read unvalidated.** `BytesPerLine`/`DiskMapTrackMark`
  of 0 from a hand-edited INI → mod-by-zero crashes
  (`ListViewPresenter.pas:430`, `DiskMap.pas:517`).
- [x] **17. Nil `tvwMain.Selected` dereference** in
  `itmExpandChildrenClick`/`itmCollapseChildrenClick` (`Main.pas:1007,1105`).
- [x] **18. `FileExists` vs `FileExistsUTF8`** for recent files
  (`Main.pas:434`).
- [ ] **19. `DecodeFile` decodes into the variable area** — uses header bytes
  20-21 (program + variables) instead of 18-19 (`SinclairBasic.pas:318,546`).
- [ ] **20. Protection fingerprints search past `DataSize`.** `StrBufPos`
  scans the full 32 KB sector buffer (`FormatAnalysis.pas`); after a sector is
  shrunk, stale bytes beyond `DataSize` can false-positive.
- [ ] **21. Minor.** CP/M `Extent` ignores S2 high-extent bits
  (`filesystem.pas:221`); Utils.pas:362-375 range-check warnings from the
  `LVSCW_AUTOSIZE` constants.
  _Fixed: both stray `OnChange` handlers removed._
  _Fixed: both `dlgOpen` and `dlgSave` now use `'.dsk'`._
  _Fixed: the temp folder is removed once the drag returns. The names written into it also go through `SafeFileName`, which the extract paths already used - this one was missed._
  _Fixed: `BytesPerLine` floored at 8 where it is used, `DiskMapTrackMark` floored at 1 in its setter._
  _Fixed: both check for a selection first._
  _Fixed: `FileExistsUTF8`, and removing an entry no longer deletes index -1 when the name has already gone._

## Notes

- Systemic themes: untrusted image bytes used directly as enum/array indices
  or allocation sizes; settings read without validation; copy-paste wirings.
- Items 1-3 are the ones worth fixing first — reachable in normal use with
  corrupt images.
