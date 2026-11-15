# Known issues and hardening risks

Historical issue IDs are retained for reference; resolved items are removed.
No unresolved user-facing defects are currently tracked. One open hardening risk
remains:

- Range checks are disabled (`Source/DiskImageManager.lpi:53-56,249-252`), so
  an invalid range or array index can access memory without raising a Pascal
  range exception. Overflow checks are on and do work. The test project has
  independent compiler settings, so its checks do not change the application's
  behavior. This is a defense-in-depth concern, not a report of a specific
  observed failure.

  Enabling range checks is not just a settings change. `Utils.AutoResizeColumn`
  has its range check stood down, because the win32 autosize sentinels it must
  assign to `TListColumn.Width` are negative and that property starts at zero;
  that is the same thing the LCL does for them, and without it the unit does not
  compile under range checks. With that in place the suite still raises
  `ERangeError` in three areas whose narrowing is deliberate: the sector-ID
  wrap in `TDSKFormatSpecification.BuildSectorIDs` (`Inc` on a `byte`), the
  `longword` file lengths narrowed into `integer`/`word` in `CPMFileSystem`,
  and the Huffman and CRC word arithmetic in `LZHuf`/`TeleDisk`. Each needs
  looking at before the checks can be turned on.

Do not infer that every read beyond a sector's `DataSize` is a heap overread:
`TDSKSector.Data` is a separately allocated, 32,769-byte buffer.
