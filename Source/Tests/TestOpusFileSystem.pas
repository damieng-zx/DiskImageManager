unit TestOpusFileSystem;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Tests for Opus Discovery images and their file system.

  The disks are built here byte by byte, as the .opd file holds them, so the
  tests do not depend on the code that reads them to say where anything goes.
}

interface

uses
  Classes, SysUtils, FGL, ZStream, Zipper, fpcunit, testregistry,
  DskImage, DIMUtils, DiskArchive, FormatAnalysis, OpusFileSystem, SinclairBasic;

type
  TOpusFiles = specialize TFPGList<TOpusFile>;

  // An Opus disk being put together as the bytes of a .opd file
  TOpusBuilder = class
  private
    FTracks, FSides, FEntries: integer;
  public
    Bytes: TDiskByteArray;
    constructor Create(Tracks, Sides: integer);
    function Blocks: integer;
    // Where a block starts in the file: blocks fill side 0 then side 1, while
    // the file alternates sides track by track
    function Offset(Block: integer): integer;
    procedure Put(Block: integer; const Data: TDiskByteArray);
    procedure Entry(const Name: string; First, Last, LastBytes: integer);
    // Add a file starting at Block, stored exactly as given
    procedure AddFile(const Name: string; Block: integer; const Stored: TDiskByteArray);
    // Add the entry that ends the catalogue
    procedure Finish;
  end;

  TOpusFileSystemTest = class(TTestCase)
  private
    FImage: TDSKImage;
    FFileSystem: TOpusFileSystem;
    FFiles: TOpusFiles;
    function TempName(const Extension: string): string;
    // Bytes that differ from block to block, so a misplaced sector shows up
    function Pattern(Count: integer): TDiskByteArray;
    // A file as SAVE writes it: a 7-byte header and then the data
    function Saved(FileType, Param1, Param2: integer; const Data: TDiskByteArray): TDiskByteArray;
    function TextBytes(const Value: string): TDiskByteArray;
    function SingleSided: TOpusBuilder;
    procedure WriteBytes(const FileName: string; const Bytes: TDiskByteArray);
    function ReadBytes(const FileName: string): TDiskByteArray;
    // Replace the current image with one loaded from a file holding Bytes
    procedure Open(const Bytes: TDiskByteArray; const Extension: string = '.opd');
    procedure Reopen(const FileName: string);
    procedure ReadDirectory;
    procedure SaveAs(const FileName: string; Format: TDSKImageFormat);
    function NewDisk(Tracks: integer; Sides: TDSKSpecSide): TDSKImage;
    procedure AssertBytes(const Msg: string; const Expected, Actual: TDiskByteArray);
  protected
    procedure TearDown; override;
  published
    procedure TestBootSectorGeometry;
    procedure TestBlocksStartAtSectorOneAndFillSideZeroFirst;
    procedure TestImageGeometryComesFromTheBootSectorOrTheSize;
    procedure TestOpdAndOpuOpen;
    procedure TestListingDescribesEachFile;
    procedure TestExtractionStripsTheHeader;
    procedure TestBasicProgramStopsBeforeItsVariables;
    procedure TestHeaderRules;
    procedure TestNames;
    procedure TestFilesCrossTracksAndSides;
    procedure TestGeometryFallsBackToTheFileSize;
    procedure TestWrongSizeIsNotLoaded;
    procedure TestSpecification;
    procedure TestImagesRoundTrip;
    procedure TestUnformattedTracksPastTheEndAreLeftOut;
    procedure TestOnlyOpusShapedDisksSaveAsOpd;
    procedure TestSectorsNumberedFromOne;
    procedure TestOnlyACompleteOpusDiskIsDetected;
    procedure TestDamagedEntriesAreLeftOut;
    procedure TestNewDisk;
    procedure TestEveryGeometryCanBeFormatted;
    procedure TestOnlyOpusGeometryCanBeFormatted;
    procedure TestCompressedImages;
    procedure TestRenameChangesOnlyTheName;
    procedure TestFilesCarryOverToTape;
    procedure TestRenameRefusesNamesTheCatalogueCannotTake;
  end;

implementation

const
  SectorBytes = OpusSectorSize;
  SectorsEach = OpusSectorsPerTrack;

// Builder

constructor TOpusBuilder.Create(Tracks, Sides: integer);
var
  Flags: byte;
begin
  inherited Create;
  FTracks := Tracks;
  FSides := Sides;
  SetLength(Bytes, Tracks * Sides * SectorsEach * SectorBytes);
  FillChar(Bytes[0], Length(Bytes), $E5);
  if Sides = 2 then Flags := $50 else Flags := $40;
  Bytes[0] := $18;
  Bytes[1] := $05;
  Bytes[2] := Tracks;
  Bytes[3] := SectorsEach;
  Bytes[4] := Flags;
  // The disk's own entry covers the 7-block catalogue
  Entry('TestDisk', 0, 6, SectorBytes);
end;

function TOpusBuilder.Blocks: integer;
begin
  Result := FTracks * FSides * SectorsEach - 1;
end;

function TOpusBuilder.Offset(Block: integer): integer;
var
  Track, Index: integer;
begin
  Track := (Block + 1) div SectorsEach;
  Index := (Block + 1) mod SectorsEach;
  Result := (((Track mod FTracks) * FSides + Track div FTracks) * SectorsEach + Index) *
    SectorBytes;
end;

procedure TOpusBuilder.Put(Block: integer; const Data: TDiskByteArray);
var
  Done, Count: integer;
begin
  Done := 0;
  while Done < Length(Data) do
  begin
    Count := Length(Data) - Done;
    if Count > SectorBytes then Count := SectorBytes;
    Move(Data[Done], Bytes[Offset(Block + Done div SectorBytes)], Count);
    Inc(Done, Count);
  end;
end;

procedure TOpusBuilder.Entry(const Name: string; First, Last, LastBytes: integer);
var
  At, Idx: integer;

  procedure PutWord(Where, Value: integer);
  begin
    Bytes[Where] := Value and $FF;
    Bytes[Where + 1] := (Value shr 8) and $FF;
  end;

begin
  At := Offset(FEntries div 16) + (FEntries mod 16) * 16;
  PutWord(At, LastBytes - 1);
  PutWord(At + 2, First);
  PutWord(At + 4, Last);
  for Idx := 0 to 9 do
    if Idx < Length(Name) then
      Bytes[At + 6 + Idx] := Ord(Name[Idx + 1])
    else
      Bytes[At + 6 + Idx] := 32;
  Inc(FEntries);
end;

procedure TOpusBuilder.AddFile(const Name: string; Block: integer;
  const Stored: TDiskByteArray);
var
  Count: integer;
begin
  Count := (Length(Stored) + SectorBytes - 1) div SectorBytes;
  Put(Block, Stored);
  Entry(Name, Block, Block + Count - 1, Length(Stored) - (Count - 1) * SectorBytes);
end;

procedure TOpusBuilder.Finish;
begin
  Entry('TestDisk', Blocks, $FFFF, SectorBytes);
end;

// Helpers

procedure TOpusFileSystemTest.TearDown;
const
  Extensions: array[0..7] of string = ('.opd', '.opu', '.dsk', '.out.opd', '.out.opu',
    '.zip', '.opu.gz', '.std.dsk');
var
  Idx: integer;
begin
  if FFiles <> nil then
    for Idx := 0 to FFiles.Count - 1 do
      FFiles[Idx].Free;
  FreeAndNil(FFiles);
  FreeAndNil(FFileSystem);
  FreeAndNil(FImage);
  for Idx := 0 to High(Extensions) do
    DeleteFile(TempName(Extensions[Idx]));
end;

function TOpusFileSystemTest.TempName(const Extension: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'dim_opus_' + TestName + Extension;
end;

function TOpusFileSystemTest.Pattern(Count: integer): TDiskByteArray;
var
  Idx: integer;
begin
  Result := nil;
  SetLength(Result, Count);
  for Idx := 0 to Count - 1 do
    Result[Idx] := Idx mod 251;
end;

function TOpusFileSystemTest.Saved(FileType, Param1, Param2: integer;
  const Data: TDiskByteArray): TDiskByteArray;
begin
  Result := nil;
  SetLength(Result, 7 + Length(Data));
  Result[0] := FileType;
  Result[1] := Lo(word(Length(Data)));
  Result[2] := Hi(word(Length(Data)));
  Result[3] := Lo(word(Param1));
  Result[4] := Hi(word(Param1));
  Result[5] := Lo(word(Param2));
  Result[6] := Hi(word(Param2));
  if Length(Data) > 0 then
    Move(Data[0], Result[7], Length(Data));
end;

function TOpusFileSystemTest.TextBytes(const Value: string): TDiskByteArray;
begin
  Result := nil;
  SetLength(Result, Length(Value));
  Move(Value[1], Result[0], Length(Value));
end;

function TOpusFileSystemTest.SingleSided: TOpusBuilder;
begin
  Result := TOpusBuilder.Create(40, 1);
  Result.AddFile('program', 7, Saved(0, 10, 100, Pattern(100)));
  Result.AddFile('Code File', 8, Saved(3, 32768, 32768, Pattern(1000)));
  Result.AddFile('array', 12, Saved(1, $8100, 0, Pattern(20)));
  Result.AddFile('letters', 13, Saved(2, $C200, 0, Pattern(20)));
  Result.AddFile('stream', 14, TextBytes('written with PRINT #'));
  Result.Finish;
end;

procedure TOpusFileSystemTest.WriteBytes(const FileName: string; const Bytes: TDiskByteArray);
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
end;

function TOpusFileSystemTest.ReadBytes(const FileName: string): TDiskByteArray;
var
  Stream: TFileStream;
begin
  Result := nil;
  Stream := TFileStream.Create(FileName, fmOpenRead);
  try
    SetLength(Result, Stream.Size);
    Stream.ReadBuffer(Result[0], Length(Result));
  finally
    Stream.Free;
  end;
end;

procedure TOpusFileSystemTest.Open(const Bytes: TDiskByteArray; const Extension: string);
begin
  WriteBytes(TempName(Extension), Bytes);
  Reopen(TempName(Extension));
end;

procedure TOpusFileSystemTest.Reopen(const FileName: string);
begin
  FreeAndNil(FImage);
  FImage := TDSKImage.CreateFromFile(FileName);
end;

procedure TOpusFileSystemTest.ReadDirectory;
var
  Idx: integer;
begin
  if FFiles <> nil then
    for Idx := 0 to FFiles.Count - 1 do
      FFiles[Idx].Free;
  FreeAndNil(FFiles);
  FreeAndNil(FFileSystem);
  FFileSystem := TOpusFileSystem.Create(FImage.Disk);
  FFiles := FFileSystem.Directory;
end;

procedure TOpusFileSystemTest.SaveAs(const FileName: string; Format: TDSKImageFormat);
begin
  // SaveFile puts up a dialog when it fails, so ask first
  AssertTrue('can save: ' + FImage.Messages.Text, FImage.CanSave(Format));
  AssertTrue('saved', FImage.SaveFile(FileName, Format, True, False));
end;

function TOpusFileSystemTest.NewDisk(Tracks: integer; Sides: TDSKSpecSide): TDSKImage;
var
  Formatter: TDSKFormatSpecification;
begin
  Formatter := TDSKFormatSpecification.Create(9);
  try
    Formatter.TracksPerSide := Tracks;
    Formatter.Sides := Sides;
    AssertTrue('formattable', IsOpusFormattable(Formatter));
    Result := TDSKImage.Create;
    Result.FileFormat := diNotYetSaved;
    Result.Disk.Format(Formatter);
    WriteOpusFileSystem(Result.Disk, Formatter.DirBlocks);
  finally
    Formatter.Free;
  end;
end;

procedure TOpusFileSystemTest.AssertBytes(const Msg: string;
  const Expected, Actual: TDiskByteArray);
begin
  AssertEquals(Msg + ': length', Length(Expected), Length(Actual));
  if Length(Expected) > 0 then
    AssertTrue(Msg + ': content', CompareMem(@Expected[0], @Actual[0], Length(Expected)));
end;

// Tests

procedure TOpusFileSystemTest.TestBootSectorGeometry;
var
  Geometry: TOpusGeometry;
begin
  AssertTrue(OpusBootGeometry([$18, $05, 40, 18, $40], Geometry));
  AssertEquals(40, Geometry.Tracks);
  AssertEquals(1, Geometry.Sides);
  AssertEquals(18, Geometry.SectorsPerTrack);
  AssertEquals(256, Geometry.SectorSize);
  AssertEquals(184320, Geometry.Capacity);
  AssertEquals(719, Geometry.Blocks);

  AssertTrue(OpusBootGeometry([$18, $05, 80, 18, $50], Geometry));
  AssertEquals(2, Geometry.Sides);
  AssertEquals(737280, Geometry.Capacity);

  AssertFalse('no tracks', OpusBootGeometry([$18, $05, 0, 18, $40], Geometry));
  AssertFalse('no sectors', OpusBootGeometry([$18, $05, 40, 0, $40], Geometry));
  AssertFalse('too short', OpusBootGeometry([$18, $05], Geometry));
end;

procedure TOpusFileSystemTest.TestBlocksStartAtSectorOneAndFillSideZeroFirst;
var
  Geometry: TOpusGeometry;

  procedure Check(Block, Side, Track, Index: integer);
  var
    S, T, I: integer;
  begin
    AssertTrue(Geometry.BlockLocation(Block, S, T, I));
    AssertEquals(Format('block %d side', [Block]), Side, S);
    AssertEquals(Format('block %d track', [Block]), Track, T);
    AssertEquals(Format('block %d sector', [Block]), Index, I);
  end;

var
  S, T, I: integer;
begin
  AssertTrue(OpusBootGeometry([$18, $05, 40, 18, $50], Geometry));
  Check(0, 0, 0, 1);
  Check(16, 0, 0, 17);
  Check(17, 0, 1, 0);
  Check(718, 0, 39, 17);
  Check(719, 1, 0, 0);
  Check(1438, 1, 39, 17);
  AssertFalse('past the end', Geometry.BlockLocation(1439, S, T, I));
  AssertFalse('before the start', Geometry.BlockLocation(-1, S, T, I));
end;

procedure TOpusFileSystemTest.TestImageGeometryComesFromTheBootSectorOrTheSize;
var
  Geometry: TOpusGeometry;
  FromBoot: boolean;
begin
  // 80 tracks on one side is the same size as 40 on two
  AssertTrue(OpusImageGeometry([$18, $05, 80, 18, $40], 368640, Geometry, FromBoot));
  AssertTrue(FromBoot);
  AssertEquals(80, Geometry.Tracks);
  AssertEquals(1, Geometry.Sides);

  AssertTrue(OpusImageGeometry([0, 0, 0, 0, 0], 368640, Geometry, FromBoot));
  AssertFalse(FromBoot);
  AssertEquals(40, Geometry.Tracks);
  AssertEquals(2, Geometry.Sides);

  AssertFalse(OpusImageGeometry([0, 0, 0, 0, 0], 1000, Geometry, FromBoot));
  AssertFalse(OpusImageGeometry([0, 0, 0, 0, 0], 0, Geometry, FromBoot));
end;

procedure TOpusFileSystemTest.TestOpdAndOpuOpen;
const
  Extensions: array[0..1] of string = ('.opd', '.opu');
var
  Builder: TOpusBuilder;
  Extension: string;
begin
  Builder := SingleSided;
  try
    for Extension in Extensions do
    begin
      Open(Builder.Bytes, Extension);
      AssertEquals(Extension, Ord(diRawOPD), Ord(FImage.FileFormat));
      AssertFalse(FImage.Corrupt);
      AssertFalse(FImage.IsChanged);
      AssertEquals('no messages', '', FImage.Messages.Text);
      AssertEquals(1, FImage.Disk.Sides);
      AssertEquals(40, FImage.Disk.Side[0].Tracks);
      AssertEquals(18, FImage.Disk.Side[0].Track[0].Sectors);
      AssertEquals('first sector ID', 0, FImage.Disk.Side[0].Track[0].Sector[0].ID);
      AssertEquals(256, FImage.Disk.Side[0].Track[39].Sector[17].DataSize);
      AssertEquals(OpusFormatName, FImage.Disk.DetectFormat);
      AssertEquals(OpusFormatName, AnalyseFormat(FImage.Disk));
      AssertEquals('not bootable on anything else', '', FImage.Disk.BootableOn);
    end;
  finally
    Builder.Free;
  end;
end;

procedure TOpusFileSystemTest.TestListingDescribesEachFile;
const
  Names: array[0..4] of string = ('program', 'Code File', 'array', 'letters', 'stream');
  Sizes: array[0..4] of integer = (100, 1000, 20, 20, 20);
  Blocks: array[0..4] of integer = (1, 4, 1, 1, 1);
  Metas: array[0..4] of string = ('BASIC LINE 10', 'CODE 32768,1000', 'DATA a()',
    'DATA b$()', 'Data');
var
  Builder: TOpusBuilder;
  Idx: integer;
begin
  Builder := SingleSided;
  try
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  ReadDirectory;

  AssertTrue(FFileSystem.IsValid);
  AssertEquals('TestDisk', FFileSystem.DiskName);
  AssertEquals(719, FFileSystem.TotalBlocks);
  AssertEquals(719 - 7 - 8, FFileSystem.FreeBlocks);
  AssertEquals(5, FFiles.Count);
  for Idx := 0 to 4 do
  begin
    AssertEquals(Names[Idx], FFiles[Idx].FileName);
    AssertEquals(Names[Idx] + ' size', Sizes[Idx], FFiles[Idx].Size);
    AssertEquals(Names[Idx] + ' blocks', Blocks[Idx], FFiles[Idx].BlockCount);
    AssertEquals(Names[Idx] + ' allocated', Blocks[Idx] * 256, FFiles[Idx].AllocatedSize);
    AssertEquals(Names[Idx], Metas[Idx], FFiles[Idx].Meta);
    AssertEquals(Names[Idx] + ' index', Idx + 1, FFiles[Idx].EntryIndex);
    AssertEquals(Names[Idx] + ' header', Idx < 4, FFiles[Idx].HasHeader);
  end;
  AssertTrue('first sector', FFiles[0].FirstSector =
    FImage.Disk.Side[0].Track[0].Sector[8]);
end;

procedure TOpusFileSystemTest.TestExtractionStripsTheHeader;
var
  Builder: TOpusBuilder;
begin
  Builder := SingleSided;
  try
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  ReadDirectory;

  AssertBytes('contents', Pattern(1000), FFiles[1].GetData(False));
  AssertBytes('with header', Saved(3, 32768, 32768, Pattern(1000)), FFiles[1].GetData(True));
  // A file with no header comes back whole either way
  AssertBytes('stream', TextBytes('written with PRINT #'), FFiles[4].GetData(False));
  AssertBytes('stream', TextBytes('written with PRINT #'), FFiles[4].GetData(True));
end;

procedure TOpusFileSystemTest.TestFilesCarryOverToTape;
var
  Builder: TOpusBuilder;
  Tape: TTapeFile;

  procedure Check(Index: integer; const Name: string; FileType: TTapeFileType;
    Param1, Param2, Size: integer);
  var
    Stored: string;
  begin
    AssertTrue(Name + ' goes to tape', FFiles[Index].GetTapeFile(Tape));
    SetString(Stored, PAnsiChar(@Tape.Name[0]), SizeOf(Tape.Name));
    AssertEquals(Name, Stored.TrimRight);
    AssertEquals(Name + ' type', Ord(FileType), Ord(Tape.FileType));
    AssertEquals(Name + ' first parameter', Param1, Tape.Param1);
    AssertEquals(Name + ' second parameter', Param2, Tape.Param2);
    AssertBytes(Name + ' data', Pattern(Size), Tape.Data);
  end;

begin
  Builder := SingleSided;
  try
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  ReadDirectory;

  Check(0, 'program', tfProgram, 10, 100, 100);
  Check(1, 'Code File', tfCode, 32768, $8000, 1000);
  Check(2, 'array', tfNumberArray, $8100, $8000, 20);
  Check(3, 'letters', tfCharacterArray, $C200, $8000, 20);
  AssertFalse('a file with no header', FFiles[4].GetTapeFile(Tape));

  AssertTrue(FFileSystem.RenameFile(FFiles[0], 'renamed'));
  Check(0, 'renamed', tfProgram, 10, 100, 100);
end;

procedure TOpusFileSystemTest.TestBasicProgramStopsBeforeItsVariables;
const
  // 10 PRINT "HI", then four bytes of variables
  Prog: array[0..9] of byte = (0, 10, 6, 0, $F5, $22, $48, $49, $22, $0D);
var
  Builder: TOpusBuilder;
  Data, Wanted: TDiskByteArray;
  Parser: TSinclairBasicParser;
  Idx: integer;
begin
  Data := nil;
  SetLength(Data, Length(Prog) + 4);
  Move(Prog[0], Data[0], Length(Prog));
  for Idx := Length(Prog) to High(Data) do
    Data[Idx] := $41;
  Wanted := Copy(Data, 0, Length(Prog));

  Builder := TOpusBuilder.Create(40, 1);
  try
    Builder.AddFile('hi', 7, Saved(0, 10, Length(Prog), Data));
    Builder.AddFile('code', 8, Saved(3, 0, 0, Data));
    Builder.Finish;
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  ReadDirectory;

  AssertBytes('program', Wanted, FFiles[0].BasicProgram);
  AssertEquals('only BASIC has one', 0, Length(FFiles[1].BasicProgram));
  Parser := TSinclairBasicParser.Create(sbMode128K);
  try
    AssertEquals('listing', '10 PRINT "HI"', Trim(Parser.Decode(FFiles[0].BasicProgram)));
  finally
    Parser.Free;
  end;
end;

procedure TOpusFileSystemTest.TestHeaderRules;
var
  Builder: TOpusBuilder;
  Long, Short: TDiskByteArray;
begin
  // The header's length has to account for exactly the rest of the file
  Long := Saved(3, 0, 0, Pattern(5));
  SetLength(Long, Length(Long) + 1);
  Short := Saved(3, 0, 0, Pattern(5));
  SetLength(Short, Length(Short) - 1);

  Builder := TOpusBuilder.Create(40, 1);
  try
    Builder.AddFile('long', 7, Long);
    Builder.AddFile('short', 8, Short);
    Builder.AddFile('unknown', 9, Saved(4, 0, 0, Pattern(5)));
    Builder.AddFile('nolines', 10, Saved(0, $8000, 5, Pattern(5)));
    Builder.AddFile('zed', 11, Saved(2, $DA00, 0, Pattern(5)));
    Builder.AddFile('noname', 12, Saved(2, 0, 0, Pattern(5)));
    Builder.AddFile('empty', 13, Saved(3, 16384, 0, nil));
    Builder.Finish;
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  ReadDirectory;

  AssertEquals('Data', FFiles[0].Meta);
  AssertEquals('Data', FFiles[1].Meta);
  AssertEquals('Data', FFiles[2].Meta);
  AssertEquals('BASIC', FFiles[3].Meta);
  AssertEquals('DATA z$()', FFiles[4].Meta);
  AssertEquals('DATA ?$()', FFiles[5].Meta);
  AssertEquals('CODE 16384,0', FFiles[6].Meta);
  AssertEquals('empty', 0, Length(FFiles[6].GetData(False)));
end;

procedure TOpusFileSystemTest.TestNames;
var
  Builder: TOpusBuilder;
begin
  Builder := TOpusBuilder.Create(40, 1);
  try
    Builder.AddFile('a b'#$60#$7F#$90, 7, Pattern(5));
    Builder.AddFile('tencharact', 8, Pattern(5));
    Builder.Finish;
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  ReadDirectory;

  // Pound and copyright signs in UTF-8, and nothing to show a graphic as
  AssertEquals('a b'#$C2#$A3#$C2#$A9'?', FFiles[0].FileName);
  AssertEquals('tencharact', FFiles[1].FileName);
end;

procedure TOpusFileSystemTest.TestFilesCrossTracksAndSides;
var
  Builder: TOpusBuilder;
  Tracks: integer;
  Data: TDiskByteArray;
begin
  Data := Pattern(40 * 256);
  Tracks := 40;
  while Tracks <= 80 do
  begin
    Builder := TOpusBuilder.Create(Tracks, 2);
    try
      // Starts near the end of side 0 and finishes on side 1
      Builder.AddFile('across', Tracks * 18 - 20, Saved(3, 0, 0, Data));
      Builder.AddFile('last', Builder.Blocks - 1, TextBytes('end of disk'));
      Builder.Finish;
      Open(Builder.Bytes);

      AssertEquals(2, FImage.Disk.Sides);
      AssertEquals(Tracks, FImage.Disk.Side[1].Tracks);
      // The first block of side 1 comes after all of side 0
      AssertEquals('logical track', Tracks, FImage.Disk.Side[1].Track[0].Logical);
      AssertTrue('next sector crosses sides', FImage.Disk.GetNextLogicalSector(
        FImage.Disk.Side[0].Track[Tracks - 1].Sector[17]) =
        FImage.Disk.Side[1].Track[0].Sector[0]);

      ReadDirectory;
      AssertBytes(Format('%d tracks', [Tracks]), Data, FFiles[0].GetData(False));
      AssertBytes('last block', TextBytes('end of disk'), FFiles[1].GetData(False));
    finally
      Builder.Free;
    end;
    Tracks := Tracks * 2;
  end;
end;

procedure TOpusFileSystemTest.TestGeometryFallsBackToTheFileSize;
var
  Builder: TOpusBuilder;
begin
  Builder := SingleSided;
  try
    FillChar(Builder.Bytes[0], 5, 0);
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;

  AssertEquals(Ord(diRawOPD), Ord(FImage.FileFormat));
  AssertEquals(1, FImage.Disk.Sides);
  AssertEquals(40, FImage.Disk.Side[0].Tracks);
  AssertEquals('one warning', 1, FImage.Messages.Count);
  ReadDirectory;
  AssertFalse('nothing to read without a boot sector', FFileSystem.IsValid);
  AssertEquals(0, FFiles.Count);
end;

procedure TOpusFileSystemTest.TestWrongSizeIsNotLoaded;
var
  Stream: TMemoryStream;
begin
  Stream := TMemoryStream.Create;
  try
    Stream.Size := 1000;
    FillChar(Stream.Memory^, 1000, 0);
    // As an entry in a zip, which reports failures without a dialog
    FImage := TDSKImage.CreateFromArchive(Stream, 'a.zip', 'short.opd');
    AssertTrue(FImage.Corrupt);
    AssertEquals(Ord(diInvalid), Ord(FImage.FileFormat));
    AssertEquals(0, FImage.Disk.Sides);
  finally
    Stream.Free;
  end;
end;

procedure TOpusFileSystemTest.TestSpecification;
var
  Builder: TOpusBuilder;
  Spec: TDSKSpecification;
  Before: byte;
begin
  Builder := TOpusBuilder.Create(80, 2);
  try
    Builder.Finish;
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;

  Spec := FImage.Disk.Specification;
  Spec.Identify;
  AssertEquals(Ord(dsFormatOpus), Ord(Spec.Format));
  AssertEquals(Ord(dsSideDoubleSuccessive), Ord(Spec.Side));
  AssertEquals(Ord(dsTrackDouble), Ord(Spec.Track));
  AssertEquals(80, Spec.TracksPerSide);
  AssertEquals(18, Spec.SectorsPerTrack);
  AssertEquals(256, Spec.SectorSize);
  AssertEquals(256, Spec.GetBlockSize);
  AssertEquals(7, Spec.DirectoryBlocks);
  AssertEquals(0, Spec.ReservedTracks);
  AssertEquals(737280, Spec.GetUsableCapacity);

  // Writing a CP/M disk specification would destroy the boot sector
  Before := FImage.Disk.Side[0].Track[0].Sector[0].Data[0];
  AssertFalse(Spec.Write);
  AssertEquals(Before, FImage.Disk.Side[0].Track[0].Sector[0].Data[0]);
end;

procedure TOpusFileSystemTest.TestImagesRoundTrip;
var
  Builder: TOpusBuilder;
  Tracks, Sides: integer;
  Data: TDiskByteArray;
begin
  for Sides := 1 to 2 do
  begin
    Tracks := 40;
    while Tracks <= 80 do
    begin
      Builder := TOpusBuilder.Create(Tracks, Sides);
      try
        // Block 719 starts side 1 of a 40 track disk, and ends a single sided one
        Data := Pattern((Sides * 80 - 40) * 256 + 100);
        Builder.AddFile('across', 650, Data);
        Builder.Finish;
        Open(Builder.Bytes);

        SaveAs(TempName('.out.opu'), diRawOPD);
        AssertBytes('as .opu', Builder.Bytes, ReadBytes(TempName('.out.opu')));

        SaveAs(TempName('.dsk'), diExtendedDSK);
        Reopen(TempName('.dsk'));
        AssertEquals(Ord(diExtendedDSK), Ord(FImage.FileFormat));
        AssertEquals('found in a DSK', OpusFormatName, FImage.Disk.DetectFormat);
        ReadDirectory;
        AssertBytes('file in a DSK', Data, FFiles[0].GetData(False));

        SaveAs(TempName('.out.opd'), diRawOPD);
        AssertBytes('back from a DSK', Builder.Bytes, ReadBytes(TempName('.out.opd')));

        SaveAs(TempName('.std.dsk'), diStandardDSK);
        Reopen(TempName('.std.dsk'));
        SaveAs(TempName('.out.opd'), diRawOPD);
        AssertBytes('back from a standard DSK', Builder.Bytes,
          ReadBytes(TempName('.out.opd')));
      finally
        Builder.Free;
      end;
      Tracks := Tracks * 2;
    end;
  end;
end;

procedure TOpusFileSystemTest.TestUnformattedTracksPastTheEndAreLeftOut;
var
  Builder: TOpusBuilder;
begin
  Builder := SingleSided;
  try
    Open(Builder.Bytes);
    FImage.Disk.Side[0].Tracks := 42;
    FImage.Disk.Sides := 2;
    SaveAs(TempName('.out.opd'), diRawOPD);
    AssertBytes('the formatted disk', Builder.Bytes, ReadBytes(TempName('.out.opd')));
  finally
    Builder.Free;
  end;
end;

procedure TOpusFileSystemTest.TestOnlyOpusShapedDisksSaveAsOpd;
var
  Formatter: TDSKFormatSpecification;
  Builder: TOpusBuilder;
begin
  FImage := TDSKImage.Create;
  Formatter := TDSKFormatSpecification.Create(3);  // CPC data
  try
    FImage.Disk.Format(Formatter);
  finally
    Formatter.Free;
  end;
  AssertFalse('not a standard size', FImage.CanSave(diRawOPD));
  AssertEquals('says why', 1, FImage.Messages.Count);

  Builder := SingleSided;
  try
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  FImage.Disk.Side[0].Track[3].Sectors := 17;
  AssertFalse('a short track', FImage.CanSave(diRawOPD));
  AssertTrue(Pos('track 3', FImage.Messages[FImage.Messages.Count - 1]) > 0);

  FImage.Disk.Side[0].Track[3].Sectors := 0;
  AssertFalse('a gap', FImage.CanSave(diRawOPD));
end;

procedure TOpusFileSystemTest.TestSectorsNumberedFromOne;
var
  Builder: TOpusBuilder;
  Formatter: TDSKFormatSpecification;
  Track, Index: integer;
begin
  Builder := SingleSided;
  Formatter := TDSKFormatSpecification.Create(9);
  try
    Formatter.FirstSector := 1;
    FImage := TDSKImage.Create;
    FImage.Disk.Format(Formatter);
    for Track := 0 to 39 do
      for Index := 0 to 17 do
        Move(Builder.Bytes[(Track * 18 + Index) * 256],
          FImage.Disk.Side[0].Track[Track].Sector[Index].Data, 256);
  finally
    Formatter.Free;
    Builder.Free;
  end;

  AssertEquals(OpusFormatName, FImage.Disk.DetectFormat);
  ReadDirectory;
  AssertBytes('file', Pattern(1000), FFiles[1].GetData(False));
end;

procedure TOpusFileSystemTest.TestOnlyACompleteOpusDiskIsDetected;
var
  Builder: TOpusBuilder;
begin
  // Without the jump it is not claimed in a DSK, though an .opd is still read
  Builder := SingleSided;
  try
    Builder.Bytes[0] := 0;
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  AssertTrue(FImage.Disk.DetectFormat <> OpusFormatName);
  ReadDirectory;
  AssertEquals(5, FFiles.Count);

  // The right boot sector over a blank catalogue is not an Opus disk either
  Builder := SingleSided;
  try
    FillChar(Builder.Bytes[256], 7 * 256, $E5);
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  AssertTrue(FImage.Disk.DetectFormat <> OpusFormatName);
  ReadDirectory;
  AssertFalse(FFileSystem.IsValid);
  AssertEquals(0, FFiles.Count);
end;

procedure TOpusFileSystemTest.TestDamagedEntriesAreLeftOut;
var
  Builder: TOpusBuilder;
begin
  Builder := TOpusBuilder.Create(40, 1);
  try
    Builder.AddFile('first', 7, Pattern(600));
    Builder.Entry('outside', 700, 800, 10);
    Builder.Entry('backwards', 20, 19, 10);
    Builder.AddFile('second', 12, Pattern(10));
    // No end marker
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  ReadDirectory;

  AssertEquals(2, FFiles.Count);
  AssertEquals('first', FFiles[0].FileName);
  AssertEquals('second', FFiles[1].FileName);
  AssertEquals('slot of the second', 4, FFiles[1].EntryIndex);
  AssertEquals('blocks from the geometry', 719, FFileSystem.TotalBlocks);

  // A file on sectors the image does not have says so, and the same file system
  // sees the change when it is listed again
  FImage.Disk.Side[0].Track[0].Sectors := 9;
  ReadDirectory;
  AssertEquals('Data (incomplete)', FFiles[0].Meta);
  AssertEquals(600, Length(FFiles[0].GetData(False)));
end;

procedure TOpusFileSystemTest.TestNewDisk;
const
  LabelEntry: array[0..15] of byte = ($FF, 0, 0, 0, 6, 0,
    Ord('U'), Ord('n'), Ord('t'), Ord('i'), Ord('t'), Ord('l'), Ord('e'), Ord('d'), 32, 32);
  EndEntry: array[0..15] of byte = ($FF, 0, $CF, $02, $FF, $FF,
    Ord('U'), Ord('n'), Ord('t'), Ord('i'), Ord('t'), Ord('l'), Ord('e'), Ord('d'), 32, 32);
var
  Formatter: TDSKFormatSpecification;
  Boot, Catalogue: TDSKSector;
  Idx: integer;
begin
  Formatter := TDSKFormatSpecification.Create(9);
  try
    AssertTrue(Formatter.OpusDiscovery);
    AssertEquals(184320, Formatter.GetCapacityBytes);
    AssertEquals((720 - 8) * 256, Formatter.GetUsableBytes);
    AssertEquals(110, Formatter.GetDirectoryEntries);
  finally
    Formatter.Free;
  end;

  FImage := NewDisk(40, dsSideSingle);
  Boot := FImage.Disk.Side[0].Track[0].Sector[0];
  AssertEquals($18, Boot.Data[0]);
  AssertEquals($05, Boot.Data[1]);
  AssertEquals(40, Boot.Data[2]);
  AssertEquals(18, Boot.Data[3]);
  AssertEquals($40, Boot.Data[4]);
  // The interface calls the routine at 7, which ends in RET
  AssertEquals($7E, Boot.Data[7]);
  AssertEquals($C9, Boot.Data[30]);
  AssertEquals($FF, Boot.Data[31]);
  AssertEquals($FF, Boot.Data[255]);

  Catalogue := FImage.Disk.Side[0].Track[0].Sector[1];
  for Idx := 0 to 15 do
  begin
    AssertEquals(Format('label byte %d', [Idx]), LabelEntry[Idx], Catalogue.Data[Idx]);
    AssertEquals(Format('end byte %d', [Idx]), EndEntry[Idx], Catalogue.Data[16 + Idx]);
    AssertEquals('empty slot', $E5, Catalogue.Data[32 + Idx]);
  end;

  AssertEquals(OpusFormatName, FImage.Disk.DetectFormat);
  ReadDirectory;
  AssertEquals('Untitled', FFileSystem.DiskName);
  AssertEquals(0, FFiles.Count);
  AssertEquals(719, FFileSystem.TotalBlocks);
  AssertEquals(712, FFileSystem.FreeBlocks);
end;

procedure TOpusFileSystemTest.TestEveryGeometryCanBeFormatted;
const
  Sides: array[0..2] of TDSKSpecSide = (dsSideSingle, dsSideDoubleAlternate,
    dsSideDoubleSuccessive);
var
  Tracks, Idx, SideCount: integer;
begin
  for Idx := 0 to High(Sides) do
  begin
    Tracks := 40;
    while Tracks <= 80 do
    begin
      if Sides[Idx] = dsSideSingle then SideCount := 1 else SideCount := 2;
      FreeAndNil(FImage);
      FImage := NewDisk(Tracks, Sides[Idx]);
      SaveAs(TempName('.out.opd'), diRawOPD);
      Reopen(TempName('.out.opd'));
      AssertEquals('size', Tracks * SideCount * 18 * 256, FImage.FileSize);
      AssertEquals(OpusFormatName, FImage.Disk.DetectFormat);
      AssertEquals('no warnings', '', FImage.Messages.Text);
      ReadDirectory;
      AssertEquals('tracks', Tracks, FFileSystem.Geometry.Tracks);
      AssertEquals('sides', SideCount, FFileSystem.Geometry.Sides);
      AssertEquals('free', Tracks * SideCount * 18 - 8, FFileSystem.FreeBlocks);
      Tracks := Tracks * 2;
    end;
  end;
end;

procedure TOpusFileSystemTest.TestOnlyOpusGeometryCanBeFormatted;
var
  Formatter: TDSKFormatSpecification;
begin
  Formatter := TDSKFormatSpecification.Create(9);
  try
    AssertTrue(IsOpusFormattable(Formatter));
    Formatter.TracksPerSide := 42;
    AssertFalse('tracks', IsOpusFormattable(Formatter));
    Formatter.TracksPerSide := 80;
    Formatter.SectorsPerTrack := 10;
    AssertFalse('sectors', IsOpusFormattable(Formatter));
    Formatter.SectorsPerTrack := 18;
    Formatter.SectorSize := 512;
    AssertFalse('sector size', IsOpusFormattable(Formatter));
    Formatter.SectorSize := 256;
    Formatter.FirstSector := 1;
    AssertFalse('first sector', IsOpusFormattable(Formatter));
    Formatter.FirstSector := 0;
    Formatter.DirBlocks := 0;
    AssertFalse('no catalogue', IsOpusFormattable(Formatter));
  finally
    Formatter.Free;
  end;
end;

procedure TOpusFileSystemTest.TestCompressedImages;
var
  Builder: TOpusBuilder;
  GZ: TGZFileStream;
  Zip: TZipper;
  Images: TDSKImageList;
  Problems: TStringList;
  Idx: integer;
begin
  Builder := SingleSided;
  try
    GZ := TGZFileStream.Create(TempName('.opu.gz'), gzopenwrite);
    try
      GZ.WriteBuffer(Builder.Bytes[0], Length(Builder.Bytes));
    finally
      GZ.Free;
    end;
    WriteBytes(TempName('.opd'), Builder.Bytes);
  finally
    Builder.Free;
  end;

  Reopen(TempName('.opu.gz'));
  AssertEquals('gzipped', Ord(diRawOPD), Ord(FImage.FileFormat));

  Zip := TZipper.Create;
  try
    Zip.FileName := TempName('.zip');
    Zip.Entries.AddFileEntry(TempName('.opd'), 'one.opd');
    Zip.Entries.AddFileEntry(TempName('.opu.gz'), 'two.opu.gz');
    Zip.ZipAllFiles;
  finally
    Zip.Free;
  end;

  Images := TDSKImageList.Create;
  Problems := TStringList.Create;
  try
    LoadZipImages(TempName('.zip'), Images, Problems);
    AssertEquals('no problems', '', Problems.Text);
    AssertEquals('both opened', 2, Images.Count);
    AssertEquals(Ord(diRawOPD), Ord(Images[0].FileFormat));
    AssertEquals(Ord(diRawOPD), Ord(Images[1].FileFormat));
  finally
    for Idx := 0 to Images.Count - 1 do
      Images[Idx].Free;
    Images.Free;
    Problems.Free;
  end;
end;

procedure TOpusFileSystemTest.TestRenameChangesOnlyTheName;
const
  // A pound sign, a five, a space and a copyright sign, as UTF-8
  NewName = #$C2#$A3'5 '#$C2#$A9;
  Stored: array[0..9] of byte = ($60, $35, 32, $7F, 32, 32, 32, 32, 32, 32);
var
  Builder: TOpusBuilder;
  Expected, Data: TDiskByteArray;
begin
  Builder := SingleSided;
  try
    Open(Builder.Bytes);
    Expected := Copy(Builder.Bytes, 0, Length(Builder.Bytes));
    // The second file's entry is the third, after the disk's own
    Move(Stored, Expected[Builder.Offset(0) + 2 * 16 + 6], SizeOf(Stored));
  finally
    Builder.Free;
  end;
  ReadDirectory;
  Data := FFiles[1].GetData(True);

  AssertFalse('same name', FFileSystem.RenameFile(FFiles[1], 'Code File'));
  AssertFalse('same name leaves the image alone', FImage.IsChanged);

  AssertTrue('renamed', FFileSystem.RenameFile(FFiles[1], NewName + '  '));
  AssertEquals('name of the file in hand', NewName, FFiles[1].FileName);
  AssertTrue('image is changed', FImage.IsChanged);

  SaveAs(TempName('.out.opd'), diRawOPD);
  AssertBytes('saved image', Expected, ReadBytes(TempName('.out.opd')));

  Reopen(TempName('.out.opd'));
  ReadDirectory;
  AssertEquals('name listed', NewName, FFiles[1].FileName);
  AssertBytes('contents', Data, FFiles[1].GetData(True));
end;

procedure TOpusFileSystemTest.TestRenameRefusesNamesTheCatalogueCannotTake;

  procedure Refused(const Name: string);
  begin
    try
      FFileSystem.RenameFile(FFiles[0], Name);
      Fail('accepted "' + Name + '"');
    except
      on EConvertError do ;
    end;
    AssertEquals('name kept after "' + Name + '"', 'program', FFiles[0].FileName);
    AssertFalse('image untouched after "' + Name + '"', FImage.IsChanged);
  end;

var
  Builder: TOpusBuilder;
begin
  Builder := SingleSided;
  try
    Open(Builder.Bytes);
  finally
    Builder.Free;
  end;
  ReadDirectory;

  Refused('');
  Refused('   ');
  Refused('elevenchars');
  Refused('back`tick');
  Refused('caf'#$C3#$A9);
  Refused('tab'#9'bed');
  Refused('Code File');
  // The interface tells names that differ only in case apart
  AssertTrue(FFileSystem.RenameFile(FFiles[0], 'code file'));
end;

initialization
  RegisterTest(TOpusFileSystemTest);
end.
