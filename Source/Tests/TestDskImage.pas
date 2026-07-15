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
  Classes, SysUtils, fpcunit, testregistry, DskImage, DSKFormat;

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
    procedure TestLoadWarnsTooManyTrackSizes;
    procedure TestReloadEmptyStandardDSK;
    procedure TestLoadTruncatedSectorData;
    procedure TestFormatClampsSectorSize;
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

initialization
  RegisterTest(TDskImageTest);
end.
