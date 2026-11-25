unit TestDiskArchive;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Tests for disk images read from .gz and .zip files.

  The zips in data/mgtdisklib/archives are samples from Simon Owen's mgtdisklib
  (MIT, see LICENSE.txt above them). The awkward ones, a zip with folders and
  strays in it or with an entry that cannot be unpacked, are built here.
}

interface

uses
  Classes, SysUtils, ZStream, Zipper, fpcunit, testregistry,
  DskImage, DIMUtils, DiskArchive;

type
  TDiskArchiveTest = class(TTestCase)
  private
    FImages: TDSKImageList;
    FProblems: TStringList;
    function SamplePath(const Name: string): string;
    function TempName(const Extension: string): string;
    function PlusThreeBytes: TMemoryStream;
    function Zeroes(Count: integer): TMemoryStream;
    procedure MakeZip(const ZipName: string; const Names: array of string;
      const Contents: array of TStream; Compress: boolean);
    function ReadBytes(const FileName: string): TDiskByteArray;
    procedure WriteBytes(const FileName: string; const Bytes: TDiskByteArray);
    function FindSignature(const Bytes: TDiskByteArray; Third, Fourth: byte): integer;
    procedure Load(const FileName: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestZipHoldingOneImage;
    procedure TestEntryExtensionInCapitals;
    procedure TestGzippedImageInsideAZip;
    procedure TestEveryImageInAZipIsOpened;
    procedure TestFoldersAndStraysAreHandled;
    procedure TestStoredEntries;
    procedure TestBadEntryDoesNotStopTheOthers;
    procedure TestUnsupportedCompressionIsReported;
    procedure TestDamagedStoredEntryIsReported;
    procedure TestOversizeEntryIsRefused;
    procedure TestOversizeGzipIsRefused;
    procedure TestFileThatIsNotAZipRaises;
    procedure TestSaveAsNamesForCompressedImages;
    procedure TestSavingAZippedImageLeavesTheZip;
  end;

implementation

procedure TDiskArchiveTest.SetUp;
begin
  FImages := TDSKImageList.Create;
  FProblems := TStringList.Create;
end;

procedure TDiskArchiveTest.TearDown;
var
  Idx: integer;
begin
  for Idx := 0 to FImages.Count - 1 do
    FImages[Idx].Free;
  FImages.Free;
  FProblems.Free;
  DeleteFile(TempName('.zip'));
end;

function TDiskArchiveTest.SamplePath(const Name: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'data' + PathDelim + 'mgtdisklib' +
    PathDelim + 'archives' + PathDelim + Name;
end;

function TDiskArchiveTest.TempName(const Extension: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'dim_zip_' + TestName + Extension;
end;

// A freshly formatted +3 disk as the bytes of a .dsk file
function TDiskArchiveTest.PlusThreeBytes: TMemoryStream;
var
  Image: TDSKImage;
  Spec: TDSKFormatSpecification;
  FileName: string;
begin
  FileName := TempName('.source.dsk');
  Image := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(0);
  try
    Image.Disk.Format(Spec);
    AssertTrue('source saved', Image.SaveFile(FileName, diExtendedDSK, True, False));
  finally
    Spec.Free;
    Image.Free;
  end;
  Result := TMemoryStream.Create;
  Result.LoadFromFile(FileName);
  DeleteFile(FileName);
end;

function TDiskArchiveTest.Zeroes(Count: integer): TMemoryStream;
begin
  Result := TMemoryStream.Create;
  Result.Size := Count;
  FillChar(Result.Memory^, Count, 0);
end;

// The streams are the zip's contents, and are freed here
procedure TDiskArchiveTest.MakeZip(const ZipName: string; const Names: array of string;
  const Contents: array of TStream; Compress: boolean);
var
  Zip: TZipper;
  Entry: TZipFileEntry;
  Idx: integer;
begin
  Zip := TZipper.Create;
  try
    Zip.FileName := ZipName;
    for Idx := 0 to High(Names) do
    begin
      Contents[Idx].Position := 0;
      Entry := Zip.Entries.AddFileEntry(Contents[Idx], Names[Idx]);
      if not Compress then
        Entry.CompressionLevel := clnone;
    end;
    Zip.ZipAllFiles;
  finally
    Zip.Free;
    for Idx := 0 to High(Contents) do
      Contents[Idx].Free;
  end;
end;

function TDiskArchiveTest.ReadBytes(const FileName: string): TDiskByteArray;
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

procedure TDiskArchiveTest.WriteBytes(const FileName: string; const Bytes: TDiskByteArray);
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

// Where the zip record starting 'PK' Third Fourth first appears
function TDiskArchiveTest.FindSignature(const Bytes: TDiskByteArray;
  Third, Fourth: byte): integer;
begin
  for Result := 0 to High(Bytes) - 3 do
    if (Bytes[Result] = Ord('P')) and (Bytes[Result + 1] = Ord('K')) and
      (Bytes[Result + 2] = Third) and (Bytes[Result + 3] = Fourth) then exit;
  Fail('zip record not found');
end;

procedure TDiskArchiveTest.Load(const FileName: string);
begin
  LoadZipImages(FileName, FImages, FProblems);
end;

procedure TDiskArchiveTest.TestZipHoldingOneImage;
var
  Zip: string;
begin
  Zip := SamplePath('image.mgt.zip');
  Load(Zip);
  AssertEquals('problems', '', FProblems.Text);
  AssertEquals('images', 1, FImages.Count);
  AssertEquals('format', Ord(diRawMGT), Ord(FImages[0].FileFormat));
  AssertFalse('loads cleanly', FImages[0].Corrupt);
  AssertFalse('not changed', FImages[0].IsChanged);
  AssertEquals('name says where it is', Zip + '>image.mgt', FImages[0].FileName);
  AssertEquals('zip', Zip, FImages[0].ArchiveName);
  AssertEquals('shown as', 'image.mgt (image.mgt.zip)', FImages[0].DisplayName);
  AssertEquals('size of the image, not the zip', MGTRawSize, FImages[0].FileSize);
  AssertFalse('there is no such file to overwrite', FileExists(FImages[0].FileName));
end;

procedure TDiskArchiveTest.TestEntryExtensionInCapitals;
begin
  Load(SamplePath('image_upper.zip'));
  AssertEquals('images', 1, FImages.Count);
  AssertEquals('format', Ord(diRawMGT), Ord(FImages[0].FileFormat));
  AssertEquals('shown as', 'IMAGE.MGT (image_upper.zip)', FImages[0].DisplayName);
end;

procedure TDiskArchiveTest.TestGzippedImageInsideAZip;
begin
  Load(SamplePath('image.mgt.gz.zip'));
  AssertEquals('problems', '', FProblems.Text);
  AssertEquals('images', 1, FImages.Count);
  AssertEquals('format', Ord(diRawMGT), Ord(FImages[0].FileFormat));
  AssertEquals('unpacked size', MGTRawSize, FImages[0].FileSize);
  AssertEquals('save as the image inside',
    ExtractFilePath(SamplePath('')) + 'image.mgt', FImages[0].UnpackedName);
end;

procedure TDiskArchiveTest.TestEveryImageInAZipIsOpened;
begin
  Load(SamplePath('image_multiple.zip'));
  AssertEquals('problems', '', FProblems.Text);
  AssertEquals('images', 2, FImages.Count);
  AssertEquals('first', 'image.sad (image_multiple.zip)', FImages[0].DisplayName);
  AssertEquals('first format', Ord(diRawSAD), Ord(FImages[0].FileFormat));
  AssertEquals('second', 'image9.dsk (image_multiple.zip)', FImages[1].DisplayName);
  AssertEquals('second format', Ord(diExtendedDSK), Ord(FImages[1].FileFormat));
  AssertTrue('each has a name of its own', FImages[0].FileName <> FImages[1].FileName);
end;

procedure TDiskArchiveTest.TestFoldersAndStraysAreHandled;
begin
  MakeZip(TempName('.zip'),
    ['readme.txt', 'Side A/game.dsk', 'Side B/game.dsk', '__MACOSX/Side A/._game.dsk',
    '.hidden.dsk'],
    [Zeroes(10), PlusThreeBytes, PlusThreeBytes, Zeroes(10), Zeroes(10)], True);
  Load(TempName('.zip'));
  AssertEquals('only the two disks are looked at', '', FProblems.Text);
  AssertEquals('images', 2, FImages.Count);
  AssertEquals('folder kept in the name', TempName('.zip') + '>Side A/game.dsk',
    FImages[0].FileName);
  AssertEquals('second folder', TempName('.zip') + '>Side B/game.dsk',
    FImages[1].FileName);
  AssertEquals('folder left off the label',
    'game.dsk (' + ExtractFileName(TempName('.zip')) + ')', FImages[0].DisplayName);
  AssertEquals('save beside the zip',
    ExtractFilePath(TempName('.zip')) + 'game.dsk', FImages[0].UnpackedName);
end;

procedure TDiskArchiveTest.TestStoredEntries;
begin
  MakeZip(TempName('.zip'), ['stored.dsk'], [PlusThreeBytes], False);
  Load(TempName('.zip'));
  AssertEquals('problems', '', FProblems.Text);
  AssertEquals('images', 1, FImages.Count);
  AssertEquals('sectors', 9, FImages[0].Disk.Side[0].Track[0].Sectors);
end;

procedure TDiskArchiveTest.TestBadEntryDoesNotStopTheOthers;
begin
  MakeZip(TempName('.zip'), ['junk.dsk', 'short.mgt', 'good.dsk'],
    [Zeroes(1000), Zeroes(1000), PlusThreeBytes], True);
  Load(TempName('.zip'));
  AssertEquals('the good one opened', 1, FImages.Count);
  AssertEquals('good.dsk', Copy(FImages[0].DisplayName, 1, 8));
  AssertEquals('both bad ones reported', 2, FProblems.Count);
  AssertTrue('by name', FProblems[0].StartsWith('junk.dsk: '));
  AssertTrue('by name', FProblems[1].StartsWith('short.mgt: '));
end;

// Old PKZIP versions packed with methods the unzipper does not know
procedure TDiskArchiveTest.TestUnsupportedCompressionIsReported;
const
  Imploded = 6;
var
  Bytes: TDiskByteArray;
begin
  MakeZip(TempName('.zip'), ['old.dsk', 'new.dsk'], [PlusThreeBytes, PlusThreeBytes], True);
  Bytes := ReadBytes(TempName('.zip'));
  // The method, in the entry's local header and in the directory
  Bytes[FindSignature(Bytes, 3, 4) + 8] := Imploded;
  Bytes[FindSignature(Bytes, 1, 2) + 10] := Imploded;
  WriteBytes(TempName('.zip'), Bytes);

  Load(TempName('.zip'));
  AssertEquals('the other opened', 1, FImages.Count);
  AssertEquals('one problem', 1, FProblems.Count);
  AssertTrue('names the entry and the method: ' + FProblems[0],
    FProblems[0].StartsWith('old.dsk: ') and (Pos('6', FProblems[0]) > 0));
end;

procedure TDiskArchiveTest.TestDamagedStoredEntryIsReported;
var
  Bytes: TDiskByteArray;
  Data: integer;
begin
  MakeZip(TempName('.zip'), ['stored.dsk'], [PlusThreeBytes], False);
  Bytes := ReadBytes(TempName('.zip'));
  // Past the local header, its name and any extra field, into the disk itself
  Data := FindSignature(Bytes, 3, 4);
  Data := Data + 30 + ReadWordLE(Bytes, Data + 26) + ReadWordLE(Bytes, Data + 28);
  Bytes[Data + 1000] := Bytes[Data + 1000] xor $FF;
  WriteBytes(TempName('.zip'), Bytes);

  Load(TempName('.zip'));
  AssertEquals('nothing opened', 0, FImages.Count);
  AssertEquals('reported', 1, FProblems.Count);
end;

procedure TDiskArchiveTest.TestOversizeEntryIsRefused;
begin
  MakeZip(TempName('.zip'), ['huge.dsk'], [Zeroes(MaxUnpackedSize + 1)], True);
  Load(TempName('.zip'));
  AssertEquals('nothing opened', 0, FImages.Count);
  AssertEquals('reported', 1, FProblems.Count);
  AssertTrue('says why: ' + FProblems[0], Pos('more than 64 MB', FProblems[0]) > 0);
end;

procedure TDiskArchiveTest.TestOversizeGzipIsRefused;
var
  Output: TGZFileStream;
  Source: TMemoryStream;
  FileName: string;
begin
  FileName := TempName('.dsk.gz');
  Source := Zeroes(MaxUnpackedSize + 1);
  try
    Output := TGZFileStream.Create(FileName, gzopenwrite);
    try
      Output.WriteBuffer(Source.Memory^, Source.Size);
    finally
      Output.Free;
    end;
  finally
    Source.Free;
  end;

  try
    try
      TDSKImage.CreateFromFile(FileName).Free;
      Fail('a gzip this size must be refused');
    except
      on E: EStreamError do
        AssertTrue('says why: ' + E.Message, Pos('more than 64 MB', E.Message) > 0);
    end;
  finally
    DeleteFile(FileName);
  end;
end;

procedure TDiskArchiveTest.TestFileThatIsNotAZipRaises;
var
  Bytes: TDiskByteArray;
  Raised: boolean;
begin
  Bytes := nil;
  SetLength(Bytes, 5000);
  FillChar(Bytes[0], Length(Bytes), $E5);
  WriteBytes(TempName('.zip'), Bytes);
  Raised := False;
  try
    Load(TempName('.zip'));
  except
    on E: Exception do Raised := True;
  end;
  AssertTrue('refused', Raised);
  AssertEquals('nothing opened', 0, FImages.Count);
end;

procedure TDiskArchiveTest.TestSaveAsNamesForCompressedImages;
var
  Image: TDSKImage;
begin
  Image := TDSKImage.Create;
  try
    Image.FileName := 'C:\disks\GAME.DSK';
    AssertEquals('a plain file is written back', '', Image.UnpackedName);
    Image.FileName := 'C:\disks\GAME.DSK.GZ';
    AssertEquals('a gzip in capitals is not', 'C:\disks\GAME.DSK', Image.UnpackedName);
    Image.FileName := 'C:\disks\game.mgt.gz';
    AssertEquals('C:\disks\game.mgt', Image.UnpackedName);
    AssertEquals('game.mgt.gz', Image.DisplayName);
  finally
    Image.Free;
  end;
end;

procedure TDiskArchiveTest.TestSavingAZippedImageLeavesTheZip;
var
  Before: TDiskByteArray;
  Target: string;
begin
  MakeZip(TempName('.zip'), ['game.dsk'], [PlusThreeBytes], True);
  Before := ReadBytes(TempName('.zip'));
  Load(TempName('.zip'));
  Target := TempName('.saved.dsk');
  try
    AssertTrue('saved', FImages[0].SaveFile(Target, diExtendedDSK, True, False));
    AssertEquals('a copy leaves it a zipped image', TempName('.zip'),
      FImages[0].ArchiveName);

    AssertTrue('saved', FImages[0].SaveFile(Target, diExtendedDSK, False, False));
    AssertEquals('now it is the saved file', '', FImages[0].ArchiveName);
    AssertEquals(Target, FImages[0].FileName);
    AssertEquals('and writes back to it', '', FImages[0].UnpackedName);
    AssertEquals('zip untouched', Length(Before), Length(ReadBytes(TempName('.zip'))));
    AssertTrue('zip untouched',
      CompareMem(@Before[0], @ReadBytes(TempName('.zip'))[0], Length(Before)));
  finally
    DeleteFile(Target);
  end;
end;

initialization
  RegisterTest(TDiskArchiveTest);

end.
