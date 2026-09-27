# Automated tests

Unit tests for Disk Image Manager, built on **FPCUnit** — the xUnit-style
framework that ships with Free Pascal and Lazarus (no external dependencies).

## What's covered

Most tests target non-UI domain logic; the small `Utils` suite covers font
configuration helpers. Forms and viewers are out of scope.

| Test unit | Unit under test | Notes |
|---|---|---|
| `TestDIMUtils.pas` | `DIMUtils.pas` | portable string / byte / hex / size helpers |
| `TestUIUtils.pas` | `Utils.pas` | font-description parsing |
| `TestComparers.pas` | `Comparers.pas` | file-size parsing & column sorting |
| `TestSinclairBasic.pas` | `SinclairBasic.pas` | Spectrum BASIC detokeniser |
| `TestAmstradBasic.pas` | `AmstradBasic.pas` | Locomotive BASIC detokeniser |
| `TestDskImage.pas` | `DskImage.pas` | format / save / reload round-trips |
| `TestCPMFileSystem.pas` | `filesystem.pas` | directory parsing, header size clamping |
| `TestFormatAnalysis.pas` | `FormatAnalysis.pas` | disk format and protection identification |
| `TestLZHuf.pas` | `LZHuf.pas` | Teledisk LZHUF compression and decompression |
| `TestTeleDisk.pas` | `TeleDisk.pas` | CRC, header validation, sector encoding |

The BASIC tests feed hand-built tokenised byte streams straight into the
decoders. The `DskImage` tests generate their fixtures **synthetically in
code**: a blank image is formatted with a known `TDSKFormatSpecification`, then
saved and reloaded to prove the load/save round-trip preserves geometry. No
binary disk images are committed to the repo.

## Running

From this directory:

```powershell
# Build (the win32 widgetset links the LCL bits the logic units pull in;
# the runner is a console app and never opens a window)
lazbuild --ws=win32 DiskImageManagerTests.lpi

# Run everything (plain text)
.\DiskImageManagerTests.exe

# JUnit-style XML (for tooling)
.\DiskImageManagerTests.exe --format=xml --file=results.xml

# List or run a single suite/test
.\DiskImageManagerTests.exe --suite=TDskImageTest
```

Or use the helper to build and run the suite. Pass `-Xml` to also write
`results.xml`:

```powershell
.\run-tests.ps1
.\run-tests.ps1 -Xml
```

## Adding tests

1. Create `TestXxx.pas` with a `TTestCase` descendant and `published` test
   methods, calling `RegisterTest(TXxxTest)` in the unit's `initialization`.
2. Add the unit to the `uses` clause of `DiskImageManagerTests.lpr` and to the
   `<Units>` list in `DiskImageManagerTests.lpi`.

> **Naming gotcha:** don't name a test unit `TestUtils` — `fcl-fpcunit` already
> ships a unit called `testutils`, and Pascal unit names are case-insensitive,
> so it collides and breaks the `fpcunit` build. (That's why the Utils tests
> live in `TestDIMUtils.pas`.)

## Why win32, not nogui

The portable helpers live in `DIMUtils`, but the suite still links UI-dependent
code: `Comparers.CompareItems` accepts LCL list-view objects, `Utils` contains
visual helpers, and `DskImage` currently depends on LCL dialogs. Those
dependencies require widgetset classes that `nogui` does not implement, so the
build fails at link time
(`Undefined symbol: WSRegister...`). Linking the native win32 widgetset resolves
them; the runner remains a console app and never creates a window. Decoupling
those UI adapters and diagnostics from the tested logic would allow the suite
to use `nogui`.
