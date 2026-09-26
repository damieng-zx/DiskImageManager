# Known issues

Open, actionable findings after the six high-priority fixes. Historical issue
IDs are retained for reference; resolved items are removed. The application
enables overflow checks but not range checks
(`Source/DiskImageManager.lpi:53-56,249-252`): unchecked array indices can read
or write outside an array without a Pascal range exception. The test project has
its own compiler settings. Do not infer that every read beyond a sector's
`DataSize` is a heap overread: `TDSKSector.Data` is a separately allocated,
32,769-byte buffer.

## Low — UI, interoperability, and hardening

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
