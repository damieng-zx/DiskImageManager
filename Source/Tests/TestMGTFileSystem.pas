unit TestMGTFileSystem;

{$mode objfpc}{$H+}

{
  Disk Image Manager - MGT, DISCiPLE and SAM Coupe disk tests.

  The samples in data/mgtdisklib are Simon Owen's, from the test suite of
  mgtdisklib (https://github.com/simonowen/mgtdisklib, MIT, see LICENSE.txt
  beside them), and the expected values are the ones its tests assert. Sector
  placement and file contents are also checked against a decoder written here
  from the layout, so that the app's reader is not marking its own work.
}

interface

uses
  Classes, SysUtils, FGL, ZStream, fpcunit, testregistry,
  DskImage, DIMUtils, MGTFileSystem, SinclairBasic;

type
  TMGTFiles = specialize TFPGList<TMGTFile>;

  TMGTFileSystemTest = class(TTestCase)
  private
    function DataDir: string;
    function SampleNames: TStringList;
    function Unpack(const Path: string): TDiskByteArray;
    function LoadSample(const Name: string): TDSKImage;
    function LoadBytes(const Bytes: TDiskByteArray; const Extension: string): TDSKImage;
    function SavedBytes(Image: TDSKImage; SaveFormat: TDSKImageFormat;
      const Extension: string): TDiskByteArray;
    function TempName(const Extension: string): string;
    procedure FreeFiles(Files: TMGTFiles);
    procedure AssertBytes(const Context: string; const Expected, Actual: TDiskByteArray);
    procedure AssertSameSectors(const Context: string; Expected, Actual: TDSKImage);
    procedure CheckEntry(const Sample: string; Index: integer; const Name: string;
      FileType, Sectors, Size: integer; const Meta, HeaderHex, DataHex: string);
    procedure CheckDisk(const Sample: string; DosType: TMGTDosType;
      const DiskLabel, FormatName: string);
  published
    procedure TestEverySampleLoadsAsMGT;
    procedure TestEverySectorComesFromTheInterleavedLayout;
    procedure TestSavingReproducesEverySample;
    procedure TestSpectrumEntries;
    procedure TestSAMEntries;
    procedure TestWhichFilesCanBeViewed;
    procedure TestBasicProgramStopsBeforeItsVariables;
    procedure TestStringArraysAreListed;
    procedure TestRenameChangesOnlyTheName;
    procedure TestRenameRefusesNamesTheDiskCannotTake;
    procedure TestRenameAllowsANameUsedInAnotherDirectory;
    procedure TestDosTypeAndLabel;
    procedure TestMasterDOSExtendedDirectory;
    procedure TestFileDataMatchesTheSectorChain;
    procedure TestDamagedChainsFallBackToTheSectorMap;
    procedure TestContiguousFileIsReadInWholeSectors;
    procedure TestEveryContainerOpens;
    procedure TestSequentialContainersLayOutSideAfterSide;
    procedure TestConvertingBetweenContainersKeepsTheDisk;
    procedure TestSequentialDumpNamedMGTIsReadAsIMG;
    procedure TestSADHeaderCheck;
    procedure TestNewDiskIsEmptyInEveryContainer;
    procedure TestDiskOfFillerListsNoFiles;
    procedure TestDiskCarriedInATeleDiskImage;
  end;

implementation

// Where the layout puts a disk address in an .mgt file
function MGTOffset(TrackByte, SectorID: integer): integer;
begin
  Result := (((TrackByte and $7F) * 2 + (TrackByte shr 7)) * 10 + SectorID - 1) * 512;
end;

// Where it puts the same address in an .img file
function IMGOffset(TrackByte, SectorID: integer): integer;
begin
  Result := (((TrackByte shr 7) * 80 + (TrackByte and $7F)) * 10 + SectorID - 1) * 512;
end;

function HexBytes(const Hex: string): TDiskByteArray;
var
  Idx: integer;
begin
  Result := nil;
  SetLength(Result, Length(Hex) div 2);
  for Idx := 0 to High(Result) do
    Result[Idx] := StrToInt('$' + Copy(Hex, Idx * 2 + 1, 2));
end;

function Slice(const Bytes: TDiskByteArray; Start, Count: integer): TDiskByteArray;
begin
  Result := nil;
  if Start + Count > Length(Bytes) then Count := Length(Bytes) - Start;
  if Count <= 0 then exit;
  SetLength(Result, Count);
  Move(Bytes[Start], Result[0], Count);
end;

procedure Append(var Bytes: TDiskByteArray; const Source: TDiskByteArray;
  Start, Count: integer);
var
  Used: integer;
begin
  Used := Length(Bytes);
  SetLength(Bytes, Used + Count);
  Move(Source[Start], Bytes[Used], Count);
end;

// Follow a file's chain through the bytes of an .mgt file
function RawChain(const Raw: TDiskByteArray; TrackByte, SectorID: integer): TDiskByteArray;
var
  Seen: array[0..255, 0..255] of boolean;
  Offset: integer;
begin
  Result := nil;
  FillChar(Seen, SizeOf(Seen), 0);
  while ((TrackByte <> 0) or (SectorID <> 0)) and ((TrackByte and $7F) < 80) and
    (SectorID >= 1) and (SectorID <= 10) and not Seen[TrackByte, SectorID] do
  begin
    Seen[TrackByte, SectorID] := True;
    Offset := MGTOffset(TrackByte, SectorID);
    Append(Result, Raw, Offset, 510);
    TrackByte := Raw[Offset + 510];
    SectorID := Raw[Offset + 511];
  end;
end;

// Gather the sectors a directory entry's map claims from the bytes of an .mgt
function RawMapped(const Raw: TDiskByteArray; const Entry: array of byte;
  Payload: integer): TDiskByteArray;
var
  Index, Linear: integer;
begin
  Result := nil;
  for Index := 0 to 1559 do
    if Entry[15 + Index div 8] and (1 shl (Index mod 8)) <> 0 then
    begin
      Linear := 4 + Index div 10;
      Append(Result, Raw,
        MGTOffset((Linear div 80) * 128 + Linear mod 80, Index mod 10 + 1), Payload);
    end;
end;

function TMGTFileSystemTest.DataDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'data' + PathDelim + 'mgtdisklib' + PathDelim;
end;

function TMGTFileSystemTest.SampleNames: TStringList;
var
  Search: TSearchRec;
begin
  Result := TStringList.Create;
  if FindFirst(DataDir + '*.mgt.gz', faAnyFile, Search) = 0 then
    try
      repeat
        Result.Add(Copy(Search.Name, 1, Length(Search.Name) - Length('.mgt.gz')));
      until FindNext(Search) <> 0;
    finally
      FindClose(Search);
    end;
  Result.Sort;
end;

function TMGTFileSystemTest.Unpack(const Path: string): TDiskByteArray;
var
  Input: TGZFileStream;
  Buffer: array[0..65535] of byte;
  BytesRead: integer;
begin
  Result := nil;
  Input := TGZFileStream.Create(Path, gzopenread);
  try
    repeat
      BytesRead := Input.Read(Buffer, SizeOf(Buffer));
      if BytesRead > 0 then
      begin
        SetLength(Result, Length(Result) + BytesRead);
        Move(Buffer[0], Result[Length(Result) - BytesRead], BytesRead);
      end;
    until BytesRead < SizeOf(Buffer);
  finally
    Input.Free;
  end;
end;

function TMGTFileSystemTest.LoadSample(const Name: string): TDSKImage;
begin
  Result := TDSKImage.CreateFromFile(DataDir + Name + '.mgt.gz');
end;

function TMGTFileSystemTest.TempName(const Extension: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'dim_mgt_' + TestName + Extension;
end;

function TMGTFileSystemTest.LoadBytes(const Bytes: TDiskByteArray;
  const Extension: string): TDSKImage;
var
  Stream: TFileStream;
  FileName: string;
begin
  FileName := TempName(Extension);
  Stream := TFileStream.Create(FileName, fmCreate);
  try
    Stream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
  end;
  try
    Result := TDSKImage.CreateFromFile(FileName);
  finally
    DeleteFile(FileName);
  end;
end;

function TMGTFileSystemTest.SavedBytes(Image: TDSKImage; SaveFormat: TDSKImageFormat;
  const Extension: string): TDiskByteArray;
var
  Stream: TFileStream;
  FileName: string;
begin
  Result := nil;
  FileName := TempName(Extension);
  try
    AssertTrue('saved as ' + Extension,
      Image.SaveFile(FileName, SaveFormat, True, False));
    Stream := TFileStream.Create(FileName, fmOpenRead);
    try
      SetLength(Result, Stream.Size);
      Stream.ReadBuffer(Result[0], Length(Result));
    finally
      Stream.Free;
    end;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TMGTFileSystemTest.FreeFiles(Files: TMGTFiles);
var
  Idx: integer;
begin
  for Idx := 0 to Files.Count - 1 do
    Files[Idx].Free;
  Files.Free;
end;

procedure TMGTFileSystemTest.AssertBytes(const Context: string;
  const Expected, Actual: TDiskByteArray);
var
  Idx: integer;
begin
  AssertEquals(Context + ' length', Length(Expected), Length(Actual));
  if (Length(Expected) = 0) or CompareMem(@Expected[0], @Actual[0], Length(Expected)) then
    exit;
  for Idx := 0 to High(Expected) do
    if Expected[Idx] <> Actual[Idx] then
      Fail(Format('%s: first differs at byte %d', [Context, Idx]));
end;

procedure TMGTFileSystemTest.AssertSameSectors(const Context: string;
  Expected, Actual: TDSKImage);
var
  SIdx, TIdx, ID: integer;
  Want, Got: TDSKSector;
begin
  AssertEquals(Context + ' sides', 2, Actual.Disk.Sides);
  for SIdx := 0 to 1 do
    for TIdx := 0 to 79 do
      for ID := 1 to 10 do
      begin
        Want := Expected.Disk.Side[SIdx].Track[TIdx].GetLogicalSectorByID(ID);
        Got := Actual.Disk.Side[SIdx].Track[TIdx].GetLogicalSectorByID(ID);
        if (Got = nil) or (Got.DataSize <> 512) or
          not CompareMem(@Want.Data, @Got.Data, 512) then
          Fail(Format('%s: side %d track %d sector %d differs', [Context, SIdx, TIdx, ID]));
      end;
end;

procedure TMGTFileSystemTest.CheckEntry(const Sample: string; Index: integer;
  const Name: string; FileType, Sectors, Size: integer;
  const Meta, HeaderHex, DataHex: string);
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
  Item: TMGTFile;
  Data, WithHeader: TDiskByteArray;
begin
  Image := LoadSample(Sample);
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    AssertTrue(Sample + ' has the entry', Files.Count > Index);
    Item := Files[Index];
    AssertEquals(Sample + ' name', Name, Item.FileName);
    AssertEquals(Sample + ' type', FileType, Item.FileType);
    AssertEquals(Sample + ' sectors', Sectors, Item.SectorsAllocated);
    AssertEquals(Sample + ' size', Size, Item.Size);
    AssertEquals(Sample + ' description', Meta, Item.Meta);

    Data := Item.GetData(False);
    AssertEquals(Sample + ' data length', Size, Length(Data));
    AssertBytes(Sample + ' data start', HexBytes(DataHex),
      Slice(Data, 0, Length(DataHex) div 2));

    AssertEquals(Sample + ' has a header', HeaderHex <> '', Item.HasHeader);
    WithHeader := Item.GetData(True);
    AssertEquals(Sample + ' length with header', Size + Length(HeaderHex) div 2,
      Length(WithHeader));
    AssertBytes(Sample + ' header', HexBytes(HeaderHex),
      Slice(WithHeader, 0, Length(HeaderHex) div 2));
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.CheckDisk(const Sample: string; DosType: TMGTDosType;
  const DiskLabel, FormatName: string);
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
begin
  Image := LoadSample(Sample);
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  try
    AssertEquals(Sample + ' system', Ord(DosType), Ord(FileSystem.DosType));
    AssertEquals(Sample + ' label', DiskLabel, FileSystem.DiskLabel);
    AssertEquals(Sample + ' format', FormatName, Image.Disk.DetectFormat);
  finally
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestEverySampleLoadsAsMGT;
var
  Names: TStringList;
  Image: TDSKImage;
  Name: string;
begin
  Names := SampleNames;
  try
    AssertEquals('every sample is there', 50, Names.Count);
    for Name in Names do
    begin
      Image := LoadSample(Name);
      try
        AssertFalse(Name + ' loads cleanly', Image.Corrupt);
        AssertEquals(Name + ' format', Ord(diRawMGT), Ord(Image.FileFormat));
        AssertTrue(Name + ' is recognised', Image.Disk.DetectFormat.StartsWith('MGT '));
      finally
        Image.Free;
      end;
    end;
  finally
    Names.Free;
  end;
end;

procedure TMGTFileSystemTest.TestEverySectorComesFromTheInterleavedLayout;
var
  Names: TStringList;
  Image: TDSKImage;
  Raw: TDiskByteArray;
  Name: string;
  SIdx, TIdx, ID: integer;
  Sector: TDSKSector;
begin
  Names := SampleNames;
  try
    for Name in Names do
    begin
      Raw := Unpack(DataDir + Name + '.mgt.gz');
      Image := LoadSample(Name);
      try
        for SIdx := 0 to 1 do
          for TIdx := 0 to 79 do
            for ID := 1 to 10 do
            begin
              Sector := Image.Disk.Side[SIdx].Track[TIdx].GetLogicalSectorByID(ID);
              if not CompareMem(@Sector.Data,
                @Raw[MGTOffset(SIdx * 128 + TIdx, ID)], 512) then
                Fail(Format('%s: side %d track %d sector %d is out of place',
                  [Name, SIdx, TIdx, ID]));
            end;
      finally
        Image.Free;
      end;
    end;
  finally
    Names.Free;
  end;
end;

procedure TMGTFileSystemTest.TestSavingReproducesEverySample;
var
  Names: TStringList;
  Image: TDSKImage;
  Name: string;
begin
  Names := SampleNames;
  try
    for Name in Names do
    begin
      Image := LoadSample(Name);
      try
        AssertBytes(Name, Unpack(DataDir + Name + '.mgt.gz'),
          SavedBytes(Image, diRawMGT, '.mgt'));
      finally
        Image.Free;
      end;
    end;
  finally
    Names.Free;
  end;
end;

procedure TMGTFileSystemTest.TestSpectrumEntries;
begin
  CheckEntry('zx_basic_vars', 0, 'basic_vars', 1, 1, 78,
    'BASIC', '004e00cb5c1a00ffff', '000a');
  CheckEntry('zx_basic_auto', 0, 'basic_auto', 1, 1, 189,
    'BASIC LINE 1234', '00bd00cb5cbd00d204', '000a');
  CheckEntry('zx_data', 0, 'data_x_10', 2, 1, 53,
    'Numeric array x()', '013500425d98ffffff', '010a0000007b0000');
  CheckEntry('zx_data_str1', 0, 'x$_5', 3, 1, 8,
    'String array x$()', '020800085dd8ffffff', '0105006162636465');
  CheckEntry('zx_data_str2', 0, 'x$_5,10', 3, 1, 55,
    'String array x$()', '023700325dd8ffffff', '0205000a0068656c6c6f');
  CheckEntry('zx_code', 0, 'code', 4, 47, 23456,
    'CODE 32768,23456', '03a05b0080ffff0000', '3e02d3fe');
  CheckEntry('zx_code_auto', 0, 'code_auto', 4, 1, 5,
    'CODE 32768,5,32768', '0305000080ffff0080', '3e02d3fe');
  CheckEntry('zx_snap_48k', 0, 'Snap A', 5, 97, 49152, 'Snapshot (48K)', '', '');
  CheckEntry('mdrv', 0, 'SOURCE', 6, 2, 1020,
    'Microdrive', '', '00000000000000000000ffff');
  CheckEntry('unidos_mdrv', 0, 'SOURCE', 6, 1, 45, 'Microdrive', '', '');
  CheckEntry('zx_screen', 0, 'Snap A', 7, 14, 6912,
    'SCREEN', '03001b00400000ffff', '');
  CheckEntry('emptycpm', 0, 'CP/M DISK', 8, 1440, 737280, 'Special', '', 'e5e5e5e5');
  CheckEntry('zx_snap_128k', 0, 'Snap A', 9, 258, 131073, 'Snapshot (128K)', '', '');
  CheckEntry('zx_opentype', 0, 'opentype', 10, 24, 12220, 'Opentype', '', '');
  CheckEntry('zx_execute', 0, 'execute', 11, 1, 510, 'ZX execute', '', '');
  CheckEntry('unidos_dir', 0, 'subdir', 12, 24, 12288,
    'UNI-DOS subdirectory (protected)', '', '');
  CheckEntry('unidos_create', 0, 'pic_code', 13, 4, 1706,
    'UNI-DOS create (protected)', '', '');
end;

procedure TMGTFileSystemTest.TestSAMEntries;
begin
  CheckEntry('basic_vars', 0, 'basic', 16, 2, 682,
    'SAM BASIC', '10aa02d59cffff0000', '');
  CheckEntry('basic_auto', 0, 'basic_auto', 16, 2, 625,
    'SAM BASIC LINE 12345', '107102d59cffff0000', '');
  CheckEntry('data', 0, 'abc_10', 17, 1, 67,
    'SAM numeric array abc()', '114300ad9fffff0000', '');
  CheckEntry('data_str', 0, 'abc$_5,10', 18, 1, 69,
    'SAM string array abc$', '1245009c9fffff0000', '');
  CheckEntry('data_str1', 0, 'abc$', 18, 1, 26,
    'SAM string array abc$', '121a005c9fffff0000', '');
  CheckEntry('code', 0, 'code', 19, 1, 5,
    'SAM CODE 32768,5', '1305000080ffff0061', '');
  CheckEntry('code_auto', 0, 'code_auto', 19, 1, 5,
    'SAM CODE 32768,5,32768', '1305000080ffff0061', '');
  CheckEntry('screen_1', 0, 'mode1', 20, 14, 6953,
    'SAM SCREEN mode 1', '14291b0080ffff001e', '');
  CheckEntry('screen_2', 0, 'mode2', 20, 29, 14377,
    'SAM SCREEN mode 2', '1429380080ffff003e', '');
  CheckEntry('screen_3', 0, 'mode3', 20, 49, 24617,
    'SAM SCREEN mode 3', '1429200080ffff015e', '');
  CheckEntry('screen_4', 0, 'mode4', 20, 49, 24617,
    'SAM SCREEN mode 4', '1429200080ffff017e', '');
  // A MasterDOS subdirectory takes no sectors and is still listed
  CheckEntry('dir', 0, 'subdir', 21, 0, 0, 'MasterDOS subdirectory', '', '');
  CheckEntry('dir', 1, 'code', 19, 1, 5, 'SAM CODE 32768,5,32768',
    '1305000080ffff0061', '');
  CheckEntry('driver_app', 0, 'driverapp', 22, 21, 10240,
    'SAM Driver application', '1600280080ffff0001', '');
  CheckEntry('driver_boot', 0, 'driverboot', 23, 1, 500,
    'SAM Driver bootstrap', '17f40100bdffff0000', '');
end;

procedure TMGTFileSystemTest.TestWhichFilesCanBeViewed;

  procedure Check(const Sample: string; Expected: TMGTViewKind);
  var
    Image: TDSKImage;
    FileSystem: TMGTFileSystem;
    Files: TMGTFiles;
  begin
    Image := LoadSample(Sample);
    FileSystem := TMGTFileSystem.Create(Image.Disk);
    Files := FileSystem.Directory;
    try
      AssertEquals(Sample, Ord(Expected), Ord(Files[0].ViewKind));
    finally
      FreeFiles(Files);
      FileSystem.Free;
      Image.Free;
    end;
  end;

begin
  Check('zx_basic_vars', mvBasic);
  Check('zx_basic_auto', mvBasic);
  Check('zx_data_str1', mvStringArray);
  Check('zx_data_str2', mvStringArray);
  Check('zx_screen', mvScreen);
  Check('zx_data', mvNone);
  // CODE of any other size than a screen's
  Check('zx_code', mvNone);
  Check('zx_snap_48k', mvNone);
  Check('zx_opentype', mvNone);
  Check('basic_auto', mvNone);
  Check('data_str', mvNone);
  Check('screen_1', mvNone);
end;

procedure TMGTFileSystemTest.TestBasicProgramStopsBeforeItsVariables;

  procedure Check(const Sample: string; ProgramLength: integer);
  var
    Image: TDSKImage;
    FileSystem: TMGTFileSystem;
    Files: TMGTFiles;
    Parser: TSinclairBasicParser;
    Listing: string;
  begin
    Image := LoadSample(Sample);
    FileSystem := TMGTFileSystem.Create(Image.Disk);
    Files := FileSystem.Directory;
    Parser := TSinclairBasicParser.Create(sbMode128K);
    try
      AssertBytes(Sample + ' program',
        Slice(Files[0].GetData(False), 0, ProgramLength), Files[0].BasicProgram);
      Listing := Parser.Decode(Files[0].BasicProgram);
      AssertEquals(Sample + ' first line', '  10 ', Copy(Listing, 1, 5));
    finally
      Parser.Free;
      FreeFiles(Files);
      FileSystem.Free;
      Image.Free;
    end;
  end;

var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
begin
  // 78 bytes stored, of which the last 52 are variables
  Check('zx_basic_vars', 26);
  Check('zx_basic_auto', 189);

  Image := LoadSample('zx_code');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    AssertEquals('only BASIC has one', 0, Length(Files[0].BasicProgram));
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestStringArraysAreListed;
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
  Parser: TSinclairBasicParser;
begin
  Image := LoadSample('zx_data_str2');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  Parser := TSinclairBasicParser.Create(sbMode128K);
  try
    AssertEquals('first of x$(5,10)', 'hello',
      Copy(Parser.DecodeStringArray(Files[0].GetData(False)), 1, 5));
  finally
    Parser.Free;
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestRenameChangesOnlyTheName;
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files, Renamed: TMGTFiles;
  Original, Expected, Data: TDiskByteArray;
  Name: string;
  Idx: integer;
begin
  Original := Unpack(DataDir + 'zx_code.mgt.gz');
  Image := LoadSample('zx_code');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    Data := Files[0].GetData(True);

    AssertFalse('same name', FileSystem.RenameFile(Files[0], 'code'));
    AssertFalse('same name leaves the image alone', Image.IsChanged);

    AssertTrue('renamed', FileSystem.RenameFile(Files[0], 'New Name  '));
    AssertEquals('name of the file in hand', 'New Name', Files[0].FileName);
    AssertTrue('image is changed', Image.IsChanged);
    // A second rename of the same object, as its entry was kept up to date
    AssertTrue('renamed again', FileSystem.RenameFile(Files[0], 'abcdefghij'));

    Renamed := FileSystem.Directory;
    try
      AssertEquals('name listed', 'abcdefghij', Renamed[0].FileName);
      AssertBytes('contents', Data, Renamed[0].GetData(True));
    finally
      FreeFiles(Renamed);
    end;

    // The first entry's name is bytes 1 to 10 of the image
    Expected := Copy(Original, 0, Length(Original));
    Name := 'abcdefghij';
    for Idx := 1 to Length(Name) do
      Expected[Idx] := Ord(Name[Idx]);
    AssertBytes('saved image', Expected, SavedBytes(Image, diRawMGT, '.mgt'));
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestRenameRefusesNamesTheDiskCannotTake;
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;

  procedure Refused(const Name: string);
  begin
    try
      FileSystem.RenameFile(Files[0], Name);
      Fail('accepted "' + Name + '"');
    except
      on EConvertError do ;
    end;
    AssertEquals('name kept after "' + Name + '"', '1', Files[0].FileName);
    AssertFalse('image untouched after "' + Name + '"', Image.IsChanged);
  end;

begin
  Image := LoadSample('masterdos_dir_5trk');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    Refused('');
    Refused('   ');
    Refused('elevenchars');
    Refused('a*');
    Refused('a?');
    Refused('tab'#9'bed');
    Refused('caf'#$C3#$A9);
    Refused('2');
    // Past the standard directory, where the longer one carries on
    Refused('98');
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestRenameAllowsANameUsedInAnotherDirectory;
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
begin
  // The file 'code' is inside the directory 'subdir', which is in the root
  Image := LoadSample('dir');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    AssertTrue(FileSystem.RenameFile(Files[1], 'SubDir'));
    AssertEquals('SubDir', Files[1].FileName);
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestDosTypeAndLabel;
begin
  CheckDisk('samdos2', mdSAMDOS, '', 'MGT SAM Coupe SAMDOS');
  CheckDisk('image', mdSAMDOS, '', 'MGT SAM Coupe SAMDOS');
  CheckDisk('emptycpm', mdSAMDOS, '', 'MGT SAM Coupe SAMDOS');
  CheckDisk('masterdos_label', mdMasterDOS, 'ABCDEFGHIJ', 'MGT SAM Coupe MasterDOS');
  CheckDisk('masterdos_short_label', mdMasterDOS, 'abc', 'MGT SAM Coupe MasterDOS');
  CheckDisk('masterdos_no_label', mdMasterDOS, '', 'MGT SAM Coupe MasterDOS');
  CheckDisk('bdos_label', mdBDOS, 'ABCDEFGHIJKLMNOP', 'MGT SAM Coupe BDOS');
  CheckDisk('zx_code', mdPlusD, '', 'MGT +D/DISCiPLE');
  CheckDisk('unidos_dir', mdPlusD, '', 'MGT +D/DISCiPLE');
  // The length's top byte sits where MasterDOS would mark its disk
  CheckDisk('zx_snap_128k', mdPlusD, '', 'MGT +D/DISCiPLE');
end;

procedure TMGTFileSystemTest.TestMasterDOSExtendedDirectory;
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
begin
  Image := LoadSample('masterdos_dir_5trk');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    AssertEquals('directory tracks', 5, FileSystem.DirectoryTracks);
    AssertEquals('directory slots', 98, FileSystem.DirectorySlots);
    AssertEquals('files on both sides of the boot sector', 98, Files.Count);
    AssertEquals('last of the standard slots', '80', Files[79].FileName);
    AssertEquals('first slot past track 4 sector 1', '81', Files[80].FileName);
    AssertEquals('last slot', '98', Files[97].FileName);
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;

  Image := LoadSample('masterdos_dir_39trk');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  try
    AssertEquals('directory tracks', 39, FileSystem.DirectoryTracks);
    AssertEquals('directory slots', 778, FileSystem.DirectorySlots);
  finally
    FileSystem.Free;
    Image.Free;
  end;
end;

// Every file on every sample whose chain holds all of it reads as that chain
procedure TMGTFileSystemTest.TestFileDataMatchesTheSectorChain;
var
  Names: TStringList;
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
  Raw, Chain: TDiskByteArray;
  Name: string;
  Idx, Header, Checked: integer;
begin
  Checked := 0;
  Names := SampleNames;
  try
    for Name in Names do
    begin
      Raw := Unpack(DataDir + Name + '.mgt.gz');
      Image := LoadSample(Name);
      FileSystem := TMGTFileSystem.Create(Image.Disk);
      Files := FileSystem.Directory;
      try
        for Idx := 0 to Files.Count - 1 do
        begin
          if Files[Idx].IsContiguous then continue;
          Header := 0;
          if Files[Idx].HasHeader then Header := 9;
          Chain := RawChain(Raw, Files[Idx].Entry[13], Files[Idx].Entry[14]);
          if (Files[Idx].Size = 0) or (Length(Chain) < Header + Files[Idx].Size) then
            continue;
          AssertBytes(Name + '/' + Files[Idx].FileName,
            Slice(Chain, Header, Files[Idx].Size), Files[Idx].GetData(False));
          Inc(Checked);
        end;
      finally
        FreeFiles(Files);
        FileSystem.Free;
        Image.Free;
      end;
    end;
  finally
    Names.Free;
  end;
  AssertTrue(Format('only %d files were compared', [Checked]), Checked >= 40);
end;

procedure TMGTFileSystemTest.TestDamagedChainsFallBackToTheSectorMap;
const
  Damaged: array[0..2] of string = ('chain_short', 'chain_bad', 'chain_loop');
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
  Raw: TDiskByteArray;
  Name: string;
begin
  for Name in Damaged do
  begin
    Raw := Unpack(DataDir + Name + '.mgt.gz');
    Image := LoadSample(Name);
    FileSystem := TMGTFileSystem.Create(Image.Disk);
    Files := FileSystem.Directory;
    try
      AssertEquals(Name + ' chain really is short', 5100,
        Length(RawChain(Raw, Files[0].Entry[13], Files[0].Entry[14])));
      AssertBytes(Name, Slice(RawMapped(Raw, Files[0].Entry, 510), 9, 24617),
        Files[0].GetData(False));
    finally
      FreeFiles(Files);
      FileSystem.Free;
      Image.Free;
    end;
  end;

  // With the map shorter still, what the chain found is all there is
  Raw := Unpack(DataDir + 'chain_and_map_short.mgt.gz');
  Image := LoadSample('chain_and_map_short');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    AssertBytes('chain_and_map_short',
      Slice(RawChain(Raw, Files[0].Entry[13], Files[0].Entry[14]), 9, 5091),
      Files[0].GetData(False));
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestContiguousFileIsReadInWholeSectors;
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
  Data: TDiskByteArray;
  Idx: integer;
begin
  Image := LoadSample('emptycpm');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    Data := Files[0].GetData(False);
    AssertEquals('every mapped sector, link bytes and all', 737280, Length(Data));
    for Idx := 0 to High(Data) do
      if Data[Idx] <> $E5 then
        Fail(Format('byte %d is not the CP/M filler', [Idx]));
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestEveryContainerOpens;
const
  Samples: array[0..4] of string = ('image.mgt', 'image.img', 'image.sad',
    'image.dsk', 'image_short.img');
  Formats: array[0..4] of TDSKImageFormat = (diRawMGT, diRawIMG, diRawSAD,
    diExtendedDSK, diRawIMG);
var
  Image: TDSKImage;
  Idx: integer;
begin
  for Idx := 0 to High(Samples) do
  begin
    Image := TDSKImage.CreateFromFile(DataDir + 'formats' + PathDelim +
      Samples[Idx] + '.gz');
    try
      AssertFalse(Samples[Idx] + ' loads cleanly', Image.Corrupt);
      AssertEquals(Samples[Idx] + ' format', Ord(Formats[Idx]), Ord(Image.FileFormat));
      AssertEquals(Samples[Idx] + ' sides', 2, Image.Disk.Sides);
      AssertEquals(Samples[Idx] + ' tracks', 80, Image.Disk.Side[0].Tracks);
      AssertEquals(Samples[Idx] + ' sectors', 10, Image.Disk.Side[1].Track[79].Sectors);
      AssertTrue(Samples[Idx] + ' is recognised',
        Image.Disk.DetectFormat.StartsWith('MGT '));
    finally
      Image.Free;
    end;
  end;
end;

procedure TMGTFileSystemTest.TestSequentialContainersLayOutSideAfterSide;
const
  Samples: array[0..2] of string = ('image.img', 'image_short.img', 'image.sad');
var
  Image: TDSKImage;
  Raw: TDiskByteArray;
  Idx, SIdx, TIdx, ID, Header: integer;
  Sector: TDSKSector;
begin
  for Idx := 0 to High(Samples) do
  begin
    Raw := Unpack(DataDir + 'formats' + PathDelim + Samples[Idx] + '.gz');
    Header := Length(Raw) - MGTRawSize;
    Image := TDSKImage.CreateFromFile(DataDir + 'formats' + PathDelim +
      Samples[Idx] + '.gz');
    try
      for SIdx := 0 to 1 do
        for TIdx := 0 to 79 do
          for ID := 1 to 10 do
          begin
            Sector := Image.Disk.Side[SIdx].Track[TIdx].GetLogicalSectorByID(ID);
            if not CompareMem(@Sector.Data,
              @Raw[Header + IMGOffset(SIdx * 128 + TIdx, ID)], 512) then
              Fail(Format('%s: side %d track %d sector %d is out of place',
                [Samples[Idx], SIdx, TIdx, ID]));
          end;
    finally
      Image.Free;
    end;
  end;
end;

procedure TMGTFileSystemTest.TestConvertingBetweenContainersKeepsTheDisk;
const
  Extensions: array[0..3] of string = ('.mgt', '.img', '.sad', '.dsk');
  Formats: array[0..3] of TDSKImageFormat = (diRawMGT, diRawIMG, diRawSAD,
    diExtendedDSK);
var
  Source, Converted: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
  Original, Written, Expected: TDiskByteArray;
  Idx: integer;
begin
  Original := Unpack(DataDir + 'formats' + PathDelim + 'image.img.gz');
  Source := LoadBytes(Original, '.img');
  try
    FileSystem := TMGTFileSystem.Create(Source.Disk);
    Files := FileSystem.Directory;
    try
      AssertEquals('one file to carry', 1, Files.Count);
      AssertEquals('hello', Files[0].FileName);
      Expected := Files[0].GetData(True);
    finally
      FreeFiles(Files);
      FileSystem.Free;
    end;

    for Idx := 0 to High(Extensions) do
    begin
      Written := SavedBytes(Source, Formats[Idx], Extensions[Idx]);
      Converted := LoadBytes(Written, Extensions[Idx]);
      try
        AssertEquals(Extensions[Idx] + ' format', Ord(Formats[Idx]),
          Ord(Converted.FileFormat));
        AssertSameSectors(Extensions[Idx], Source, Converted);
        FileSystem := TMGTFileSystem.Create(Converted.Disk);
        Files := FileSystem.Directory;
        try
          AssertEquals(Extensions[Idx] + ' files', 1, Files.Count);
          AssertBytes(Extensions[Idx] + ' file', Expected, Files[0].GetData(True));
        finally
          FreeFiles(Files);
          FileSystem.Free;
        end;
      finally
        Converted.Free;
      end;

      // A raw image holds each sector where its own layout says
      case Formats[Idx] of
        diRawMGT:
          AssertBytes('.mgt track 4', Slice(Original, IMGOffset(4, 1), 512),
            Slice(Written, MGTOffset(4, 1), 512));
        diRawIMG:
          AssertBytes('.img matches the sample', Original, Written);
        diRawSAD:
        begin
          AssertEquals('.sad size', SADHeaderSize + MGTRawSize, Length(Written));
          AssertBytes('.sad header',
            HexBytes('416c65792773206469736b206261636b7570' + '02500a08'),
            Slice(Written, 0, SADHeaderSize));
          AssertBytes('.sad sectors', Original, Slice(Written, SADHeaderSize, MGTRawSize));
        end;
      end;
    end;
  finally
    Source.Free;
  end;
end;

// Earlier versions of the app saved .mgt files in .img order
procedure TMGTFileSystemTest.TestSequentialDumpNamedMGTIsReadAsIMG;
var
  Image: TDSKImage;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
  Original: TDiskByteArray;
begin
  Original := Unpack(DataDir + 'formats' + PathDelim + 'image.img.gz');
  Image := LoadBytes(Original, '.mgt');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    AssertEquals('read in the layout it is really in', Ord(diRawIMG), Ord(Image.FileFormat));
    AssertEquals('and says so', 1, Image.Messages.Count);
    AssertEquals('hello', Files[0].FileName);
    AssertTrue('the file has its data', Length(Files[0].GetData(False)) > 0);
    // Saved back as it was found, not rewritten in the other order
    AssertBytes('unchanged', Original, SavedBytes(Image, Image.FileFormat, '.mgt'));
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

procedure TMGTFileSystemTest.TestSADHeaderCheck;
var
  Header: TDiskByteArray;
begin
  Header := HexBytes('416c65792773206469736b206261636b7570' + '02500a08');
  AssertTrue('the standard header', IsMGTSADHeader(Header));
  Header[19] := 40;
  AssertFalse('another geometry', IsMGTSADHeader(Header));
  Header[19] := 80;
  Header[0] := Ord('X');
  AssertFalse('not the signature', IsMGTSADHeader(Header));
  FillChar(Header[0], Length(Header), 0);
  AssertTrue('a header left blank', IsMGTSADHeader(Header));
  AssertFalse('too short', IsMGTSADHeader(Slice(Header, 0, 10)));
end;

// A new disk must list as empty and not be taken for another layout on reload
procedure TMGTFileSystemTest.TestNewDiskIsEmptyInEveryContainer;
const
  Extensions: array[0..2] of string = ('.mgt', '.img', '.sad');
  Formats: array[0..2] of TDSKImageFormat = (diRawMGT, diRawIMG, diRawSAD);
var
  Image, Reloaded: TDSKImage;
  Spec: TDSKFormatSpecification;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
  Idx: integer;
begin
  Image := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(8);
  try
    Image.Disk.Format(Spec);
    for Idx := 0 to High(Extensions) do
    begin
      Reloaded := LoadBytes(SavedBytes(Image, Formats[Idx], Extensions[Idx]),
        Extensions[Idx]);
      FileSystem := TMGTFileSystem.Create(Reloaded.Disk);
      Files := FileSystem.Directory;
      try
        AssertEquals(Extensions[Idx] + ' format', Ord(Formats[Idx]),
          Ord(Reloaded.FileFormat));
        AssertEquals(Extensions[Idx] + ' files', 0, Files.Count);
        AssertEquals(Extensions[Idx] + ' system', 'MGT SAM Coupe SAMDOS',
          Reloaded.Disk.DetectFormat);
      finally
        FreeFiles(Files);
        FileSystem.Free;
        Reloaded.Free;
      end;
    end;
  finally
    Spec.Free;
    Image.Free;
  end;
end;

// Disks formatted by something that left E5 behind, as earlier versions did
procedure TMGTFileSystemTest.TestDiskOfFillerListsNoFiles;
var
  Image: TDSKImage;
  Bytes: TDiskByteArray;
  FileSystem: TMGTFileSystem;
  Files: TMGTFiles;
begin
  Bytes := nil;
  SetLength(Bytes, MGTRawSize);
  FillChar(Bytes[0], Length(Bytes), $E5);
  Image := LoadBytes(Bytes, '.mgt');
  FileSystem := TMGTFileSystem.Create(Image.Disk);
  Files := FileSystem.Directory;
  try
    AssertEquals('layout', Ord(diRawMGT), Ord(Image.FileFormat));
    AssertEquals('files', 0, Files.Count);
    AssertEquals('directory tracks', 4, FileSystem.DirectoryTracks);
    AssertEquals('system', Ord(mdSAMDOS), Ord(FileSystem.DosType));
  finally
    FreeFiles(Files);
    FileSystem.Free;
    Image.Free;
  end;
end;

// A Teledisk image numbers its tracks with the sides alternating, which an MGT
// disk address does not follow
procedure TMGTFileSystemTest.TestDiskCarriedInATeleDiskImage;
var
  Source, Converted: TDSKImage;
  SourceSystem, ConvertedSystem: TMGTFileSystem;
  SourceFiles, ConvertedFiles: TMGTFiles;
  Idx: integer;
begin
  Source := LoadSample('masterdos_dir_5trk');
  Converted := LoadBytes(SavedBytes(Source, diTeleDisk, '.td0'), '.td0');
  SourceSystem := TMGTFileSystem.Create(Source.Disk);
  ConvertedSystem := TMGTFileSystem.Create(Converted.Disk);
  SourceFiles := SourceSystem.Directory;
  ConvertedFiles := ConvertedSystem.Directory;
  try
    AssertEquals('files', SourceFiles.Count, ConvertedFiles.Count);
    for Idx := 0 to SourceFiles.Count - 1 do
      AssertBytes(SourceFiles[Idx].FileName, SourceFiles[Idx].GetData(True),
        ConvertedFiles[Idx].GetData(True));
  finally
    FreeFiles(SourceFiles);
    FreeFiles(ConvertedFiles);
    SourceSystem.Free;
    ConvertedSystem.Free;
    Source.Free;
    Converted.Free;
  end;
end;

initialization
  RegisterTest(TMGTFileSystemTest);

end.
