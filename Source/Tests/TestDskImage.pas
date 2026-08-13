unit TestDskImage;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the core TDSKImage model.

  Fixtures are generated synthetically in-code: a blank image is formatted with
  a known TDSKFormatSpecification, then saved and reloaded to prove the
  load/save round-trip preserves geometry. No binary blobs are committed.

  Format indices passed to TDSKFormatSpecification.Create (see DskImage.pas):
    0 = Amstrad PCW/Spectrum +3 (40T, SS, 9 x 512)
    1 = Amstrad PCW CF2DD       (80T, DS, 9 x 512)
    8 = MGT Sam Coupe           (80T, DS, 10 x 512)
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, DskImage, DSKFormat, Utils;

type
  TDskImageTest = class(TTestCase)
  private
    function MakeFormatted(FormatIndex: integer): TDSKImage;
    function TempName(const Ext: string): string;
    function FileLen(const FileName: string): int64;
    procedure WriteText(Sector: TDSKSector; Offset: integer; const Text: string);
    function CountOf(List: TStringList; const Text: string): integer;
    function HasMessageLike(List: TStringList; const Text: string): boolean;
  published
    procedure TestFormatGeometryPCW;
    procedure TestFormatSectorData;
    procedure TestFormattedCapacity;
    procedure TestRoundTripExtendedDSK;
    procedure TestRoundTripStandardDSK;
    procedure TestRoundTripMGT;
    procedure TestDetectFormatNotEmpty;
    procedure TestLoadUnformattedExtendedDSK;
    procedure TestGetAllStringsDropsDuplicates;
    procedure TestGetAllStringsKeepsDifferentCase;
    procedure TestGetAllStringsOnEmptyDisk;
    procedure TestHighTrackCountOnEmptySide;
    procedure TestIdentifyOnEmptyDisk;
    procedure TestLoadClampsSectorCount;
    procedure TestSectorLayoutUnchangedWhenNumberingFromZero;
    procedure TestSectorLayoutUnchangedWhenNumberingWraps;
    procedure TestSectorIDsSurviveANegativeTrackSkew;
    procedure TestToDataRateRejectsValuesOutsideTheEnum;
    procedure TestToRecordingModeRejectsValuesOutsideTheEnum;
    procedure TestLoadClampsTrackDataRateAndRecordingMode;
    procedure TestLoadWarnsTooManyTrackSizes;
    procedure TestReloadEmptyStandardDSK;
    procedure TestLoadTruncatedSectorData;
    procedure TestFormatClampsSectorSize;
    procedure TestFindText;
    procedure TestExtendedDSKPadsTracksToTrackSizeTable;
    procedure TestStandardDSKSizesTracksByTheLargest;
    procedure TestSaveRefusesSidesWithDifferentTrackCounts;
    procedure TestIdentifyOnASectorTooShortToHoldASpec;
    procedure TestFDCSizeBytesRejectsUnknownCodes;
    procedure TestCopyCountOnUnknownFDCSize;
    procedure TestTrackSizeUniformOnSideWithNoTracks;
    procedure TestLoadImageWithNoTracks;
    procedure TestIdentifyRejectsImpossibleBlockShift;
    procedure TestLoadedImageIsNotChanged;
    procedure TestSectorEditMarksImageChanged;
    procedure TestSectorFillMarksImageChanged;
    procedure TestTrackUnformatMarksImageChanged;
  end;

implementation

function TDskImageTest.MakeFormatted(FormatIndex: integer): TDSKImage;
var
  Spec: TDSKFormatSpecification;
begin
  Result := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(FormatIndex);
  try
    Result.Disk.Format(Spec);
  finally
    Spec.Free;
  end;
end;

function TDskImageTest.TempName(const Ext: string): string;
begin
  // A unique-ish name in the temp directory; the test name keeps parallel
  // suites from colliding.
  Result := IncludeTrailingPathDelimiter(GetTempDir) +
    'dim_test_' + TestName + Ext;
end;

// Plant readable text in a sector. A formatted sector is filled with E5, which
// is outside the printable range, so the text is terminated at both ends.
procedure TDskImageTest.WriteText(Sector: TDSKSector; Offset: integer;
  const Text: string);
var
  Idx: integer;
begin
  for Idx := 1 to Length(Text) do
    Sector.Data[Offset + Idx - 1] := Ord(Text[Idx]);
end;

function TDskImageTest.CountOf(List: TStringList; const Text: string): integer;
var
  Idx: integer;
begin
  Result := 0;
  for Idx := 0 to List.Count - 1 do
    if List[Idx] = Text then Inc(Result);
end;

function TDskImageTest.HasMessageLike(List: TStringList; const Text: string): boolean;
var
  Idx: integer;
begin
  Result := True;
  for Idx := 0 to List.Count - 1 do
    if Pos(Text, List[Idx]) > 0 then exit;
  Result := False;
end;

function TDskImageTest.FileLen(const FileName: string): int64;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    Result := Stream.Size;
  finally
    Stream.Free;
  end;
end;

procedure TDskImageTest.TestFormatGeometryPCW;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    AssertEquals('sides', 1, Img.Disk.Sides);
    AssertEquals('tracks', 40, Img.Disk.Side[0].Tracks);
    AssertEquals('sectors per track', 9, Img.Disk.Side[0].Track[0].Sectors);
  finally
    Img.Free;
  end;
end;

procedure TDskImageTest.TestFormatSectorData;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := MakeFormatted(0);
  try
    Sec := Img.Disk.Side[0].Track[0].Sector[0];
    AssertEquals('sector size', 512, Sec.DataSize);
    // A freshly formatted PCW/+3 sector is filled with E5 (229)
    AssertEquals('filler byte', 229, Sec.Data[0]);
  finally
    Img.Free;
  end;
end;

procedure TDskImageTest.TestFormattedCapacity;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    // 40 tracks x 9 sectors x 512 bytes = 184320 bytes of sector data
    AssertEquals(40 * 9 * 512, Img.Disk.FormattedCapacity);
  finally
    Img.Free;
  end;
end;

procedure TDskImageTest.TestRoundTripExtendedDSK;
var
  Img, Reloaded: TDSKImage;
  FileName: string;
begin
  FileName := TempName('.dsk');
  Img := MakeFormatted(1); // 80T DS
  try
    AssertTrue('save succeeded',
      Img.SaveFile(FileName, diExtendedDSK, False, False));
  finally
    Img.Free;
  end;

  Reloaded := TDSKImage.CreateFromFile(FileName);
  try
    AssertFalse('not corrupt', Reloaded.Corrupt);
    AssertEquals('format', Ord(diExtendedDSK), Ord(Reloaded.FileFormat));
    AssertEquals('sides', 2, Reloaded.Disk.Sides);
    AssertEquals('tracks', 80, Reloaded.Disk.Side[0].Tracks);
    AssertEquals('sectors', 9, Reloaded.Disk.Side[0].Track[0].Sectors);
    AssertEquals('sector size', 512, Reloaded.Disk.Side[0].Track[0].Sector[0].DataSize);
    // The track header carries a sector size of its own, which came back as 0
    // and was written back out as a size code meaning 128 bytes
    AssertEquals('track sector size', 512, Reloaded.Disk.Side[0].Track[0].SectorSize);
  finally
    Reloaded.Free;
    DeleteFile(FileName);
  end;
end;

procedure TDskImageTest.TestRoundTripStandardDSK;
var
  Img, Reloaded: TDSKImage;
  FileName: string;
begin
  FileName := TempName('.dsk');
  Img := MakeFormatted(0); // 40T SS
  try
    AssertTrue('save succeeded',
      Img.SaveFile(FileName, diStandardDSK, False, False));
  finally
    Img.Free;
  end;

  Reloaded := TDSKImage.CreateFromFile(FileName);
  try
    AssertFalse('not corrupt', Reloaded.Corrupt);
    AssertEquals('format', Ord(diStandardDSK), Ord(Reloaded.FileFormat));
    AssertEquals('sides', 1, Reloaded.Disk.Sides);
    AssertEquals('tracks', 40, Reloaded.Disk.Side[0].Tracks);
    AssertEquals('sectors', 9, Reloaded.Disk.Side[0].Track[0].Sectors);
  finally
    Reloaded.Free;
    DeleteFile(FileName);
  end;
end;

procedure TDskImageTest.TestRoundTripMGT;
var
  Img, Reloaded: TDSKImage;
  FileName: string;
begin
  FileName := TempName('.mgt');
  Img := MakeFormatted(8); // MGT Sam Coupe, 80T DS 10 x 512
  try
    AssertTrue('save succeeded',
      Img.SaveFile(FileName, diRawMGT, False, False));
  finally
    Img.Free;
  end;

  // Raw MGT images are recognised by extension + exact size (819200 bytes)
  AssertEquals('raw MGT size', MGTRawSize, FileLen(FileName));

  Reloaded := TDSKImage.CreateFromFile(FileName);
  try
    AssertFalse('not corrupt', Reloaded.Corrupt);
    AssertEquals('format', Ord(diRawMGT), Ord(Reloaded.FileFormat));
    AssertEquals('sides', 2, Reloaded.Disk.Sides);
    AssertEquals('tracks', 80, Reloaded.Disk.Side[0].Tracks);
    AssertEquals('sectors', 10, Reloaded.Disk.Side[0].Track[0].Sectors);
  finally
    Reloaded.Free;
    DeleteFile(FileName);
  end;
end;

procedure TDskImageTest.TestDetectFormatNotEmpty;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    // We don't pin the exact string, only that detection produces something
    AssertTrue('format detected', Trim(Img.Disk.DetectFormat) <> '');
  finally
    Img.Free;
  end;
end;

// An Extended DSK that declares tracks but carries no track data at all (a
// 256-byte header with an all-zero track-size table, as emitted by HxC for an
// unformatted disk). Loading one used to crash in format detection when it
// dereferenced the non-existent first sector; it should now load cleanly and
// report itself as unformatted.
procedure TDskImageTest.TestLoadUnformattedExtendedDSK;
var
  Header: TDSKInfoBlock;
  Stream: TFileStream;
  FileName: string;
  Img: TDSKImage;
begin
  FileName := TempName('.dsk');
  FillChar(Header, SizeOf(Header), 0);
  Move(DiskInfoExtended[1], Header.DiskInfoBlock, Length(DiskInfoExtended));
  Header.Disk_NumTracks := 43;
  Header.Disk_NumSides := 1;
  // Disk_ExtTrackSize left all zero: every declared track is unformatted.

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Header, SizeOf(Header));
  finally
    Stream.Free;
  end;

  try
    Img := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('sides', 1, Img.Disk.Sides);
      AssertEquals('tracks', 43, Img.Disk.Side[0].Tracks);
      AssertEquals('no formatted sectors', 0, Img.Disk.Side[0].Track[0].Sectors);
      // Regression: this call previously dereferenced a nil first sector.
      AssertEquals('format', 'Unformatted', Img.Disk.DetectFormat);
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TDskImageTest.TestGetAllStringsDropsDuplicates;
var
  Img: TDSKImage;
  Sec: TDSKSector;
  Strings: TStringList;
begin
  Img := MakeFormatted(0);
  try
    Sec := Img.Disk.Side[0].Track[0].Sector[0];
    WriteText(Sec, 100, 'HELLO WORLD');
    WriteText(Sec, 200, 'HELLO WORLD');
    WriteText(Sec, 300, 'GOODBYE CRUEL WORLD');

    Strings := Img.Disk.GetAllStrings(5, 4);
    try
      AssertEquals('repeated string listed once', 1,
        CountOf(Strings, 'HELLO WORLD'));
      AssertEquals('other strings kept', 1,
        CountOf(Strings, 'GOODBYE CRUEL WORLD'));
    finally
      Strings.Free;
    end;
  finally
    Img.Free;
  end;
end;

procedure TDskImageTest.TestGetAllStringsKeepsDifferentCase;
var
  Img: TDSKImage;
  Sec: TDSKSector;
  Strings: TStringList;
begin
  Img := MakeFormatted(0);
  try
    Sec := Img.Disk.Side[0].Track[0].Sector[0];
    WriteText(Sec, 100, 'HELLO WORLD');
    WriteText(Sec, 200, 'hello world');

    // Different bytes on the disk, so both are worth reporting
    Strings := Img.Disk.GetAllStrings(5, 4);
    try
      AssertEquals('upper kept', 1, CountOf(Strings, 'HELLO WORLD'));
      AssertEquals('lower kept', 1, CountOf(Strings, 'hello world'));
    finally
      Strings.Free;
    end;
  finally
    Img.Free;
  end;
end;

// A disk with no sides at all has no first sector to start the walk from.
// GetAllStrings used to reach straight for Side[0].Track[0].Sector[0].
procedure TDskImageTest.TestGetAllStringsOnEmptyDisk;
var
  Img: TDSKImage;
  Strings: TStringList;
begin
  Img := TDSKImage.Create;
  try
    AssertEquals('no sides to walk', 0, Img.Disk.Sides);
    Strings := Img.Disk.GetAllStrings(5, 4);
    try
      AssertEquals('nothing found', 0, Strings.Count);
    finally
      Strings.Free;
    end;
  finally
    Img.Free;
  end;
end;

// A side can exist with no tracks on it. GetHighTrackCount counts down from
// Tracks, and used to read the track before testing the count, so an empty
// side indexed Track[-1] on its way to answering 0.
procedure TDskImageTest.TestHighTrackCountOnEmptySide;
var
  Img: TDSKImage;
begin
  Img := TDSKImage.Create;
  try
    Img.Disk.Sides := 1;
    AssertEquals('side has no tracks', 0, Img.Disk.Side[0].Tracks);
    AssertEquals('high track count', 0, Img.Disk.Side[0].HighTrackCount);
  finally
    Img.Free;
  end;
end;

// Identify fingerprints the first logical sector, but an image need not have a
// logical track 0 to take one from; it used to dereference the missing track.
procedure TDskImageTest.TestIdentifyOnEmptyDisk;
var
  Img: TDSKImage;
begin
  Img := TDSKImage.Create;
  try
    AssertTrue('no logical track 0', Img.Disk.GetLogicalTrack(0) = nil);
    Img.Disk.Specification.Identify;
    AssertTrue('format left invalid',
      Img.Disk.Specification.Format = dsFormatInvalid);
  finally
    Img.Free;
  end;
end;

// A track states its sector count in a byte, but a 256-byte Track-Info block
// only has room to describe MaxTrackInfoSectors of them. Reading the entries a
// malformed count claimed ran off the end of the block, a local on the stack.
procedure TDskImageTest.TestLoadClampsSectorCount;
var
  Header: TDSKInfoBlock;
  TrackInfo: TTRKInfoBlock;
  Stream: TFileStream;
  FileName: string;
  Img: TDSKImage;
begin
  FileName := TempName('.dsk');

  FillChar(Header, SizeOf(Header), 0);
  Move(DiskInfoExtended[1], Header.DiskInfoBlock, Length(DiskInfoExtended));
  Header.Disk_NumTracks := 1;
  Header.Disk_NumSides := 1;
  Header.Disk_ExtTrackSize[0] := 2; // 512: the Track-Info block, and no sectors

  FillChar(TrackInfo, SizeOf(TrackInfo), 0);
  Move(DiskInfoTrack[1], TrackInfo.TrackData, Length(DiskInfoTrack));
  TrackInfo.TIB_NumSectors := 255;
  // SectorInfoList left zero, so the entries there really are read as empty

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Header, SizeOf(Header));
    Stream.WriteBuffer(TrackInfo, SizeOf(TrackInfo));
  finally
    Stream.Free;
  end;

  try
    Img := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('sectors capped at what a track can describe',
        MaxTrackInfoSectors, Img.Disk.Side[0].Track[0].Sectors);
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

// The Extended header holds one track size per track per side, so a double
// sided image can only carry half as many tracks as the table has entries. The
// guard tested the track count on its own and let the rest index past it.
procedure TDskImageTest.TestLoadWarnsTooManyTrackSizes;
var
  Header: TDSKInfoBlock;
  Stream: TFileStream;
  FileName: string;
  Img: TDSKImage;
begin
  FileName := TempName('.dsk');

  FillChar(Header, SizeOf(Header), 0);
  Move(DiskInfoExtended[1], Header.DiskInfoBlock, Length(DiskInfoExtended));
  Header.Disk_NumTracks := 200;
  Header.Disk_NumSides := 2; // 400 track sizes wanted, from a table holding 204
  // Disk_ExtTrackSize left zero, so there is no track data to go looking for

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Header, SizeOf(Header));
  finally
    Stream.Free;
  end;

  try
    Img := TDSKImage.CreateFromFile(FileName);
    try
      AssertTrue('warned that the header holds fewer track sizes than that',
        HasMessageLike(Img.Messages, 'track sizes a header holds'));
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

// A standard image with nothing formatted on it records a track size of 0,
// which is what this app writes for one. Reading it back took the 256 byte
// Track-Info block off that, and the size is unsigned, so the track came back
// as 65280 bytes long and the load ran off the end of its own output.
procedure TDskImageTest.TestReloadEmptyStandardDSK;
var
  Img: TDSKImage;
  FileName: string;
begin
  FileName := TempName('.dsk');
  try
    Img := TDSKImage.Create;
    try
      Img.Disk.Sides := 1;
      Img.Disk.Side[0].Tracks := 40; // declared, but never formatted
      AssertTrue('saved', Img.SaveFile(FileName, diStandardDSK, True, False));
    finally
      Img.Free;
    end;

    Img := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('tracks', 40, Img.Disk.Side[0].Tracks);
      AssertEquals('still unformatted', 0, Img.Disk.Side[0].Track[0].Sectors);
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

// A track can promise more sector data than the file has left. The truncation
// was noticed and reported, but the read went ahead for the whole sector
// anyway and raised instead.
procedure TDskImageTest.TestLoadTruncatedSectorData;
const
  Written = 100; // of the 512 the sector claims
var
  Header: TDSKInfoBlock;
  TrackInfo: TTRKInfoBlock;
  SectorInfo: TSCTInfoBlock;
  Stream: TFileStream;
  FileName: string;
  Img: TDSKImage;
  Pad: array[0..Written - 1] of byte;
begin
  FileName := TempName('.dsk');

  FillChar(Header, SizeOf(Header), 0);
  Move(DiskInfoExtended[1], Header.DiskInfoBlock, Length(DiskInfoExtended));
  Header.Disk_NumTracks := 1;
  Header.Disk_NumSides := 1;
  Header.Disk_ExtTrackSize[0] := 3; // 768: the Track-Info block and 512 of data

  FillChar(TrackInfo, SizeOf(TrackInfo), 0);
  Move(DiskInfoTrack[1], TrackInfo.TrackData, Length(DiskInfoTrack));
  TrackInfo.TIB_NumSectors := 1;

  FillChar(SectorInfo, SizeOf(SectorInfo), 0);
  SectorInfo.SIB_ID := 1;
  SectorInfo.SIB_Size := 2;
  SectorInfo.SIB_DataLength := 512;
  Move(SectorInfo, TrackInfo.SectorInfoList[0], SizeOf(SectorInfo));

  FillChar(Pad, SizeOf(Pad), 0);

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Header, SizeOf(Header));
    Stream.WriteBuffer(TrackInfo, SizeOf(TrackInfo));
    Stream.WriteBuffer(Pad, SizeOf(Pad)); // the sector cut short
  finally
    Stream.Free;
  end;

  try
    Img := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('sector cut to what the file had left', Written,
        Img.Disk.Side[0].Track[0].Sector[0].DataSize);
      AssertEquals('size it claimed kept as advertised', 512,
        Img.Disk.Side[0].Track[0].Sector[0].AdvertisedSize);
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

// A sector's buffer is a fixed MaxSectorSize but a format specification states
// its sector size in a word, and formatting filled each sector to that size
// without checking it fit.
procedure TDskImageTest.TestFormatClampsSectorSize;
var
  Img: TDSKImage;
  Spec: TDSKFormatSpecification;
begin
  Img := TDSKImage.Create;
  try
    Img.Disk.Sides := 1;
    Img.Disk.Side[0].Tracks := 1;

    Spec := TDSKFormatSpecification.Create(0);
    try
      Spec.SectorSize := High(word);
      Img.Disk.Side[0].Track[0].Format(Spec);
    finally
      Spec.Free;
    end;

    AssertEquals('sector size capped at the buffer', MaxSectorSize,
      Img.Disk.Side[0].Track[0].Sector[0].DataSize);
  finally
    Img.Free;
  end;
end;

procedure TDskImageTest.TestFindText;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := MakeFormatted(0);
  try
    Sec := Img.Disk.Side[0].Track[0].Sector[0];
    WriteText(Sec, 100, 'AAB');
    WriteText(Sec, 200, 'HELLO');

    // The search walked the data once and restarted the needle on a mismatch
    // without retrying the byte it failed on, so a match whose start repeats
    // its own first byte was stepped over: AB really is in AAB, at 101.
    AssertEquals('AB found in AAB', 102, Sec.FindText('AB', True));

    AssertEquals('plain match', 204, Sec.FindText('HELLO', True));
    AssertEquals('matches without case', 204, Sec.FindText('hello', False));
    AssertEquals('case sensitive misses', -1, Sec.FindText('hello', True));
    AssertEquals('absent text', -1, Sec.FindText('NOTHERE', True));
    // Text[1] of an empty needle is not a character at all
    AssertEquals('empty needle finds nothing', -1, Sec.FindText('', True));
  finally
    Img.Free;
  end;
end;

// An extended image's track size table is written in whole 256-byte blocks and
// rounded up to reach one, but only the sectors were written, so the file fell
// short of what the table promised and every track after a short one sat
// somewhere other than where the table said.
procedure TDskImageTest.TestExtendedDSKPadsTracksToTrackSizeTable;
var
  Img: TDSKImage;
  FileName: string;
  Header: TDSKInfoBlock;
  Stream: TFileStream;
  Promised: int64;
  Idx: integer;
begin
  FileName := TempName('.dsk');
  try
    Img := MakeFormatted(0); // 40 tracks, 1 side, 9 x 512
    try
      // Leave track 0 short of filling its last block
      Img.Disk.Side[0].Track[0].Sector[0].DataSize := 300;
      AssertTrue('saved', Img.SaveFile(FileName, diExtendedDSK, True, False));
    finally
      Img.Free;
    end;

    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Stream.ReadBuffer(Header, SizeOf(Header));
    finally
      Stream.Free;
    end;

    Promised := SizeOf(Header);
    for Idx := 0 to (Header.Disk_NumTracks * Header.Disk_NumSides) - 1 do
      Promised := Promised + (Header.Disk_ExtTrackSize[Idx] * TrackBlockSize);
    AssertEquals('file holds every byte the track size table promises',
      Promised, FileLen(FileName));

    Img := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('short sector kept its length', 300,
        Img.Disk.Side[0].Track[0].Sector[0].DataSize);
      AssertEquals('the track after it is still whole', 9,
        Img.Disk.Side[0].Track[1].Sectors);
      AssertEquals('and holds its own data', 512,
        Img.Disk.Side[0].Track[1].Sector[0].DataSize);
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

// A standard image gives every track the one size, and it was taken from track
// 0 alone: the test meant to raise it for a larger track compared sector data
// against a size that counts the track header too, so it never fired. The
// tracks were written at their own sizes regardless, so nothing after the first
// one differing landed where the header said.
procedure TDskImageTest.TestStandardDSKSizesTracksByTheLargest;
var
  Img: TDSKImage;
  FileName: string;
  Header: TDSKInfoBlock;
  Stream: TFileStream;
begin
  FileName := TempName('.dsk');
  try
    Img := MakeFormatted(0); // 40 tracks, 1 side, 9 x 512
    try
      // Make track 0 the smallest, so the largest track is not the one asked
      Img.Disk.Side[0].Track[0].Sector[0].FDCSize := 1; // 256 bytes
      Img.Disk.Side[0].Track[0].Sector[0].DataSize := 256;
      AssertTrue('saved', Img.SaveFile(FileName, diStandardDSK, True, False));
    finally
      Img.Free;
    end;

    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Stream.ReadBuffer(Header, SizeOf(Header));
    finally
      Stream.Free;
    end;

    AssertEquals('track size fits the largest track', 4864, Header.Disk_StdTrackSize);
    AssertEquals('every track takes the size the header gives',
      SizeOf(Header) + (Header.Disk_NumTracks * Header.Disk_NumSides *
      Header.Disk_StdTrackSize), FileLen(FileName));

    Img := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('the largest track is still whole', 9,
        Img.Disk.Side[0].Track[39].Sectors);
      AssertEquals('and holds its own data', 512,
        Img.Disk.Side[0].Track[39].Sector[0].DataSize);
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

// A sector's FDC size code is a raw byte off the disk, and the sector
// properties window will set any of the 256 of them. Only nine are defined, so
// the rest have no size to report and must not be looked up in the table.
procedure TDskImageTest.TestFDCSizeBytesRejectsUnknownCodes;
begin
  AssertEquals('code 0 is 128 bytes', 128, GetFDCSizeBytes(0));
  AssertEquals('code 2 is 512 bytes', 512, GetFDCSizeBytes(2));
  AssertEquals('code 8 is the largest defined', MaxSectorSize, GetFDCSizeBytes(8));
  AssertEquals('one past the last defined code', 0, GetFDCSizeBytes(9));
  AssertEquals('the largest a byte holds', 0, GetFDCSizeBytes(255));
end;

procedure TDskImageTest.TestCopyCountOnUnknownFDCSize;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := MakeFormatted(0);
  try
    Sec := Img.Disk.Side[0].Track[0].Sector[0];
    Sec.FDCSize := 200;
    AssertEquals('a size code with no size declares one copy', 1, Sec.GetCopyCount);
    AssertEquals('and the whole record is that copy', Sec.DataSize, Sec.GetCopySize);
  finally
    Img.Free;
  end;
end;

// A header can claim a side and no tracks at all. Reading the size of the first
// of none went through a track array that had never been allocated.
procedure TDskImageTest.TestTrackSizeUniformOnSideWithNoTracks;
var
  Img: TDSKImage;
begin
  Img := TDSKImage.Create;
  try
    Img.Disk.Sides := 1;
    AssertEquals('a side with no tracks has nothing to disagree about',
      True, Img.Disk.IsTrackSizeUniform);
  finally
    Img.Free;
  end;
end;

procedure TDskImageTest.TestLoadImageWithNoTracks;
var
  Header: TDSKInfoBlock;
  Stream: TFileStream;
  FileName: string;
  Img: TDSKImage;
begin
  FileName := TempName('.dsk');

  FillChar(Header, SizeOf(Header), 0);
  Move(DiskInfoExtended[1], Header.DiskInfoBlock, Length(DiskInfoExtended));
  Header.Disk_NumTracks := 0;
  Header.Disk_NumSides := 1;

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Header, SizeOf(Header));
  finally
    Stream.Free;
  end;

  try
    Img := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('the side the header claimed', 1, Img.Disk.Sides);
      AssertEquals('with no tracks on it', 0, Img.Disk.Side[0].Tracks);
      // What the image view asks of every image it opens
      AssertEquals('track size is uniform', True, Img.Disk.IsTrackSizeUniform);
      AssertEquals('nothing formatted', 0, Img.Disk.FormattedCapacity);
      AssertEquals('and no largest track', 0, Img.Disk.Side[0].GetLargestTrackSize);
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

// The block shift is a raw byte off the boot sector. Past MaxBlockShift the
// block size shifted out of a 32-bit integer and came back 0, which the block
// count then divided by.
procedure TDskImageTest.TestIdentifyRejectsImpossibleBlockShift;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := MakeFormatted(0);
  try
    Sec := Img.Disk.Side[0].Track[0].Sector[0];
    Sec.Data[0] := 0;   // PCW single sided
    Sec.Data[1] := 0;   // single sided, single track
    Sec.Data[2] := 40;  // tracks per side
    Sec.Data[3] := 9;   // sectors per track
    Sec.Data[4] := 2;   // 512 byte sectors
    Sec.Data[5] := 1;   // reserved tracks
    Sec.Data[6] := 25;  // block shift: 2 shl 31 is 0
    Sec.Data[7] := 2;   // directory blocks
    Sec.Data[8] := 42;
    Sec.Data[9] := 82;

    Img.Disk.Specification.Identify;

    AssertEquals('an impossible shift is not believed', True,
      Img.Disk.Specification.BlockShift <= MaxBlockShift);
    AssertEquals('so there is always a block size to divide by', True,
      Img.Disk.Specification.GetBlockSize > 0);
    // Would have raised EDivByZero on a block size of 0
    AssertEquals('and a block count to report', True,
      Img.Disk.Specification.GetBlockCount > 0);
  finally
    Img.Free;
  end;
end;

// Only the image is asked whether there is anything worth saving, so an edit
// that marks a sector but not the image was thrown away on close without a
// prompt. These pin both halves: loading marks nothing, editing marks the image.

procedure TDskImageTest.TestLoadedImageIsNotChanged;
var
  Img, Reloaded: TDSKImage;
  FileName: string;
begin
  FileName := TempName('.dsk');
  Img := MakeFormatted(0);
  try
    Img.SaveFile(FileName, diExtendedDSK, False, False);
  finally
    Img.Free;
  end;

  try
    Reloaded := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('an image straight off disk has nothing to save',
        False, Reloaded.IsChanged);
    finally
      Reloaded.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TDskImageTest.TestSectorEditMarksImageChanged;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    // Formatting marks the image, which is the state the New dialog leaves it
    // in; start from saved so the edit below is the only thing under test
    Img.IsChanged := False;
    Img.Disk.Side[0].Track[0].Sector[0].IsChanged := True;
    AssertEquals('a changed sector is a changed image', True, Img.IsChanged);
  finally
    Img.Free;
  end;
end;

procedure TDskImageTest.TestSectorFillMarksImageChanged;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := MakeFormatted(0);
  try
    Img.IsChanged := False;
    Sec := Img.Disk.Side[0].Track[0].Sector[0];
    Sec.FillSector(Sec.ParentTrack.Filler + 1);
    AssertEquals('refilling a sector is a change to the image', True, Img.IsChanged);
  finally
    Img.Free;
  end;
end;

procedure TDskImageTest.TestTrackUnformatMarksImageChanged;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    Img.IsChanged := False;
    Img.Disk.Side[0].Track[0].Unformat;
    AssertEquals('the track is gone', 0, Img.Disk.Side[0].Track[0].Sectors);
    // Nothing on a track carries a changed flag, so this is the only place the
    // fact that it was unformatted can be recorded
    AssertEquals('and the image knows it', True, Img.IsChanged);
  finally
    Img.Free;
  end;
end;

// A track's data rate and recording mode are single bytes on the disk cast
// straight to four- and three-value enums. An ordinal the enum has no value for
// then indexes past DSKDataRate/DSKRecordingMode, which are arrays of strings,
// so the "name" that comes back is whatever follows the table read as a string.

procedure TDskImageTest.TestToDataRateRejectsValuesOutsideTheEnum;
begin
  AssertEquals('0 is unknown', Ord(drUnknown), Ord(ToDataRate(0)));
  AssertEquals('1 is single/double', Ord(drSingleOrDoubleDensity), Ord(ToDataRate(1)));
  AssertEquals('3 is the last defined', Ord(drExtendedDensity), Ord(ToDataRate(3)));
  AssertEquals('4 is past the end', Ord(drUnknown), Ord(ToDataRate(4)));
  AssertEquals('a whole byte', Ord(drUnknown), Ord(ToDataRate(255)));
  // What a combo box answers with nothing picked
  AssertEquals('-1 from a combo box', Ord(drUnknown), Ord(ToDataRate(-1)));
end;

procedure TDskImageTest.TestToRecordingModeRejectsValuesOutsideTheEnum;
begin
  AssertEquals('0 is unknown', Ord(rmUnknown), Ord(ToRecordingMode(0)));
  AssertEquals('1 is FM', Ord(rmFM), Ord(ToRecordingMode(1)));
  AssertEquals('2 is the last defined', Ord(rmMFM), Ord(ToRecordingMode(2)));
  AssertEquals('3 is past the end', Ord(rmUnknown), Ord(ToRecordingMode(3)));
  AssertEquals('a whole byte', Ord(rmUnknown), Ord(ToRecordingMode(255)));
  AssertEquals('-1 from a combo box', Ord(rmUnknown), Ord(ToRecordingMode(-1)));
end;

procedure TDskImageTest.TestLoadClampsTrackDataRateAndRecordingMode;
var
  Header: TDSKInfoBlock;
  TrackInfo: TTRKInfoBlock;
  Stream: TFileStream;
  FileName: string;
  Img: TDSKImage;
  Track: TDSKTrack;
begin
  FileName := TempName('.dsk');

  FillChar(Header, SizeOf(Header), 0);
  Move(DiskInfoExtended[1], Header.DiskInfoBlock, Length(DiskInfoExtended));
  Header.Disk_NumTracks := 1;
  Header.Disk_NumSides := 1;
  Header.Disk_ExtTrackSize[0] := 2; // the Track-Info block, and no sectors

  FillChar(TrackInfo, SizeOf(TrackInfo), 0);
  Move(DiskInfoTrack[1], TrackInfo.TrackData, Length(DiskInfoTrack));
  TrackInfo.TIB_NumSectors := 0;
  TrackInfo.TIB_DataRate := 200;      // no such data rate
  TrackInfo.TIB_RecordingMode := 99;  // no such recording mode

  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Header, SizeOf(Header));
    Stream.WriteBuffer(TrackInfo, SizeOf(TrackInfo));
  finally
    Stream.Free;
  end;

  try
    Img := TDSKImage.CreateFromFile(FileName);
    try
      Track := Img.Disk.Side[0].Track[0];
      AssertEquals('an undefined data rate reads as unknown',
        Ord(drUnknown), Ord(Track.DataRate));
      AssertEquals('and so does an undefined recording mode',
        Ord(rmUnknown), Ord(Track.RecordingMode));
      // Both are within their tables, so the names can be looked up at all
      AssertEquals('Unknown', DSKDataRate[Track.DataRate]);
      AssertEquals('Unknown', DSKRecordingMode[Track.RecordingMode]);
      AssertEquals('and the image says it saw them', True,
        HasMessageLike(Img.Messages, 'does not define'));
    finally
      Img.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

// Whatever the interleave and skew do to the order, a track has to end up
// holding each of its sector IDs exactly once. The table used to say a position
// was free by the ID stored there being 0, so writing the ID 0 left its
// position looking free and a later sector took it: an ID went missing, another
// appeared twice, and one that should not exist at all turned up.
//
// Asserted through GetSectorID, which is what TDSKTrack.Format calls, rather
// than reaching into the table it builds.

// Collect the IDs a format hands out for one track, in physical order
function CollectIDs(Spec: TDSKFormatSpecification; LogicalTrack: word;
  Side: byte): TStringList;
var
  Idx: integer;
begin
  Result := TStringList.Create;
  for Idx := 0 to Spec.SectorsPerTrack - 1 do
    Result.Add(IntToStr(Spec.GetSectorID(Side, LogicalTrack, Idx)));
end;

// The IDs a format hands out with FirstSector set to Start
function LayoutFrom(Start: byte; Interleave: shortint; SectorsPerTrack: byte;
  SkewTrack: shortint; LogicalTrack: word): TStringList;
var
  Spec: TDSKFormatSpecification;
begin
  Spec := TDSKFormatSpecification.Create(0);
  try
    Spec.SectorsPerTrack := SectorsPerTrack;
    Spec.FirstSector := Start;
    Spec.Interleave := Interleave;
    Spec.SkewTrack := SkewTrack;
    Spec.SkewSide := 0;
    Result := CollectIDs(Spec, LogicalTrack, 0);
  finally
    Spec.Free;
  end;
end;

// Which physical sector gets which ID is decided by the interleave alone, so
// starting the numbering somewhere else must shift every ID and move nothing.
// Starting at 1 is the case that always worked, so it is the shape to compare
// against.

procedure TDskImageTest.TestSectorLayoutUnchangedWhenNumberingFromZero;
var
  FromOne, FromZero: TStringList;
  Idx: integer;
begin
  // Ten sectors at 2:1, the layout the +3 formats use, but numbered from 0 as
  // the TS2068 format this app identifies elsewhere does
  FromOne := LayoutFrom(1, 2, 10, 0, 0);
  FromZero := LayoutFrom(0, 2, 10, 0, 0);
  try
    AssertEquals('one ID per sector', 10, FromZero.Count);
    for Idx := 0 to 9 do
      AssertEquals(Format('sector %d is one lower than numbering from 1', [Idx]),
        StrToInt(FromOne[Idx]) - 1, StrToInt(FromZero[Idx]));
  finally
    FromOne.Free;
    FromZero.Free;
  end;
end;

procedure TDskImageTest.TestSectorLayoutUnchangedWhenNumberingWraps;
var
  FromOne, FromHigh: TStringList;
  Idx, Expected: integer;
begin
  // High enough that the numbering runs past 255 and wraps onto 0
  FromOne := LayoutFrom(1, 2, 10, 0, 0);
  FromHigh := LayoutFrom(250, 2, 10, 0, 0);
  try
    AssertEquals('one ID per sector', 10, FromHigh.Count);
    for Idx := 0 to 9 do
    begin
      Expected := (StrToInt(FromOne[Idx]) - 1 + 250) mod 256;
      AssertEquals(Format('sector %d keeps its place across the wrap', [Idx]),
        Expected, StrToInt(FromHigh[Idx]));
    end;
  finally
    FromOne.Free;
    FromHigh.Free;
  end;
end;

// A negative track skew made the index negative, because Pascal's mod keeps the
// sign of what it divides, and the table was read from before its start
procedure TDskImageTest.TestSectorIDsSurviveANegativeTrackSkew;
var
  IDs: TStringList;
  Idx, ID, Seen: integer;
begin
  // Track 5 at a skew of -2 is what sent the index below the start of the table
  IDs := LayoutFrom(1, 1, 9, -2, 5);
  try
    AssertEquals('one ID per sector', 9, IDs.Count);
    for ID := 1 to 9 do
    begin
      Seen := 0;
      for Idx := 0 to IDs.Count - 1 do
        if IDs[Idx] = IntToStr(ID) then Inc(Seen);
      AssertEquals(Format('ID %d used exactly once', [ID]), 1, Seen);
    end;
  finally
    IDs.Free;
  end;
end;

// Neither DSK format can say that one side holds more tracks than another, so
// the count was taken from side 0 and used to index every side. A side with
// fewer tracks was read past the end of, and whatever that found went into the
// file as a track.
procedure TDskImageTest.TestSaveRefusesSidesWithDifferentTrackCounts;
var
  Img: TDSKImage;
begin
  // Asked of CanSave rather than SaveFile: a refused save puts a dialog on the
  // screen, which there is no window station for here
  Img := MakeFormatted(1); // 80 tracks, two sides
  try
    AssertEquals('both sides start equal', Img.Disk.Side[0].Tracks,
      Img.Disk.Side[1].Tracks);
    AssertEquals('as saved as extended', True, Img.CanSave(diExtendedDSK));
    AssertEquals('and as standard', True, Img.CanSave(diStandardDSK));

    // Shorten side 1, which the format has no way of recording
    Img.Disk.Side[1].Tracks := 40;

    AssertEquals('extended save refuses', False, Img.CanSave(diExtendedDSK));
    AssertEquals('and says why', True,
      HasMessageLike(Img.Messages, 'one track count'));
    AssertEquals('standard save refuses too', False, Img.CanSave(diStandardDSK));
  finally
    Img.Free;
  end;
end;

// The spec probe compares the first eleven bytes of the boot sector, so a
// sector shorter than that has nothing to compare and must not be read anyway
procedure TDskImageTest.TestIdentifyOnASectorTooShortToHoldASpec;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := MakeFormatted(0);
  try
    Sec := Img.Disk.Side[0].Track[0].Sector[0];
    Sec.DataSize := 10;

    // Ten bytes cannot hold the eleven the probe compares, so there is nothing
    // to identify. Reading them anyway is what it used to do.
    Img.Disk.Specification.Identify;
    AssertEquals('no spec can be read from ten bytes',
      Ord(dsFormatInvalid), Ord(Img.Disk.Specification.Format));
  finally
    Img.Free;
  end;
end;

initialization
  RegisterTest(TDskImageTest);
end.
