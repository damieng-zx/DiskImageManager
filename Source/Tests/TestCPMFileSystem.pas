unit TestCPMFileSystem;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the CP/M (+3/PCW/CPC) file system.

  Builds a blank PCW/+3 disk in code, then plants directory entries and file
  headers straight into the sectors, so the file system can be pointed at
  sizes no real disk could hold.
}

interface

uses
  Classes, SysUtils, FGL, fpcunit, testregistry, Utils, DskImage, DSKFormat, FileSystem;

type
  TDirectory = specialize TFPGList<TCPMFile>;

  TCPMFileSystemTest = class(TTestCase)
  private
    function MakePCWDisk: TDSKImage;
    function DirSector(Img: TDSKImage): TDSKSector;
    function DataSector(Img: TDSKImage): TDSKSector;
    procedure WriteAscii(Sec: TDSKSector; Offset: integer; const Text: string);
    procedure PlantDirEntry(Img: TDSKImage; RecordCount, BytesInLast, FirstBlock: byte);
    procedure PlantPlus3DOSHeader(Sec: TDSKSector; FileSize: longword);
    procedure PlantAMSDOSHeader(Sec: TDSKSector; PayloadSize: longword);
    procedure FreeDirectory(Files: TDirectory);
  published
    procedure TestPlus3DOSHeaderSizeClampedToCapacity;
    procedure TestPlus3DOSGetDataClampedToBlocks;
    procedure TestPlus3DOSExactSizeKept;
    procedure TestAMSDOSHeaderSizeClampedToCapacity;
    procedure TestExtentSizeFlooredAtZero;
  end;

implementation

// Format 0 = Amstrad PCW/Spectrum +3: 40T SS, 9 x 512, one reserved track,
// two directory blocks and 1KB allocation blocks
function TCPMFileSystemTest.MakePCWDisk: TDSKImage;
var
  Spec: TDSKFormatSpecification;
begin
  Result := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(0);
  try
    Result.Disk.Format(Spec);
  finally
    Spec.Free;
  end;
end;

// The directory starts on the first sector of the first track past the
// reserved one
function TCPMFileSystemTest.DirSector(Img: TDSKImage): TDSKSector;
begin
  Result := Img.Disk.Side[0].Track[1].Sector[0];
end;

// Block 2 is the first a file can use (the two directory blocks take 0 and
// 1); at 1KB a block it starts four sectors along the same track
function TCPMFileSystemTest.DataSector(Img: TDSKImage): TDSKSector;
begin
  Result := Img.Disk.Side[0].Track[1].Sector[4];
end;

procedure TCPMFileSystemTest.WriteAscii(Sec: TDSKSector; Offset: integer;
  const Text: string);
var
  Idx: integer;
begin
  for Idx := 1 to Length(Text) do
    Sec.Data[Offset + Idx - 1] := Ord(Text[Idx]);
end;

// One primary extent (EX=0) for TESTFILE.BAS under user 0
procedure TCPMFileSystemTest.PlantDirEntry(Img: TDSKImage;
  RecordCount, BytesInLast, FirstBlock: byte);
var
  Sec: TDSKSector;
begin
  Sec := DirSector(Img);
  FillChar(Sec.Data[0], 32, 0);
  WriteAscii(Sec, 1, 'TESTFILE');
  WriteAscii(Sec, 9, 'BAS');
  Sec.Data[12] := 0;
  Sec.Data[13] := BytesInLast;
  Sec.Data[15] := RecordCount;
  Sec.Data[16] := FirstBlock;
end;

// A PLUS3DOS header whose length field claims FileSize, checksum correct so
// only the size itself is under test
procedure TCPMFileSystemTest.PlantPlus3DOSHeader(Sec: TDSKSector;
  FileSize: longword);
var
  Idx: integer;
  Checksum: byte;
begin
  FillChar(Sec.Data[0], 128, 0);
  WriteAscii(Sec, 0, 'PLUS3DOS');
  Sec.Data[8] := $1A;
  Sec.Data[11] := byte(FileSize and $FF);
  Sec.Data[12] := byte((FileSize shr 8) and $FF);
  Sec.Data[13] := byte((FileSize shr 16) and $FF);
  Sec.Data[14] := byte((FileSize shr 24) and $FF);
  Sec.Data[15] := 3; // CODE

  Checksum := 0;
  for Idx := 0 to 126 do
    Checksum := Checksum + Sec.Data[Idx];
  Sec.Data[127] := Checksum;
end;

// An AMSDOS header whose payload length claims PayloadSize, checksum correct
procedure TCPMFileSystemTest.PlantAMSDOSHeader(Sec: TDSKSector;
  PayloadSize: longword);
var
  Idx: integer;
  Checksum: word;
begin
  FillChar(Sec.Data[0], 128, 0);
  Sec.Data[18] := 2; // binary
  Sec.Data[64] := byte(PayloadSize and $FF);
  Sec.Data[65] := byte((PayloadSize shr 8) and $FF);
  Sec.Data[66] := byte((PayloadSize shr 16) and $FF);

  Checksum := 0;
  for Idx := 0 to 66 do
    Checksum := Checksum + Sec.Data[Idx];
  Sec.Data[67] := Checksum and $FF;
  Sec.Data[68] := Checksum shr 8;
end;

procedure TCPMFileSystemTest.FreeDirectory(Files: TDirectory);
var
  DiskFile: TCPMFile;
begin
  for DiskFile in Files do
    DiskFile.Free;
  Files.Free;
end;

// The length field is four untrusted bytes; stored in an integer a value
// above 2GB wraps negative and GetData would size an allocation with it
procedure TCPMFileSystemTest.TestPlus3DOSHeaderSizeClampedToCapacity;
var
  Img: TDSKImage;
  FSys: TCPMFileSystem;
  Files: TDirectory;
  DiskFile: TCPMFile;
begin
  Img := MakePCWDisk;
  try
    PlantDirEntry(Img, 2, 0, 2);
    PlantPlus3DOSHeader(DataSector(Img), $FFFFFF7F);

    FSys := TCPMFileSystem.Create(Img.Disk);
    try
      Files := FSys.Directory;
      try
        AssertEquals('one file found', 1, Files.Count);
        DiskFile := Files[0];
        AssertEquals('recognised as PLUS3DOS', 'PLUS3DOS', DiskFile.HeaderType);
        AssertTrue('size not negative', DiskFile.Size >= 0);
        AssertTrue('size kept to what the disk can hold',
          DiskFile.Size <= Img.Disk.FormattedCapacity);
      finally
        FreeDirectory(Files);
      end;
    finally
      FSys.Free;
    end;
  finally
    Img.Free;
  end;
end;

// Extraction sizes its buffer from the same length; it must come back no
// bigger than the blocks the directory entry actually holds
procedure TCPMFileSystemTest.TestPlus3DOSGetDataClampedToBlocks;
var
  Img: TDSKImage;
  FSys: TCPMFileSystem;
  Files: TDirectory;
  DiskFile: TCPMFile;
  Data: TDiskByteArray;
begin
  Img := MakePCWDisk;
  try
    PlantDirEntry(Img, 2, 0, 2);
    PlantPlus3DOSHeader(DataSector(Img), $7FFFFFFF); // just under 2GB

    FSys := TCPMFileSystem.Create(Img.Disk);
    try
      Files := FSys.Directory;
      try
        DiskFile := Files[0];
        Data := DiskFile.GetData(True);
        AssertEquals('buffer held to the file''s one 1KB block', 1024,
          Length(Data));
        Data := DiskFile.GetData(False);
        AssertEquals('payload stays the header short of that', 1024 - 128,
          Length(Data));
      finally
        FreeDirectory(Files);
      end;
    finally
      FSys.Free;
    end;
  finally
    Img.Free;
  end;
end;

// A length the disk can hold and the blocks can supply comes back unchanged,
// header and all
procedure TCPMFileSystemTest.TestPlus3DOSExactSizeKept;
var
  Img: TDSKImage;
  FSys: TCPMFileSystem;
  Files: TDirectory;
  DiskFile: TCPMFile;
  Data: TDiskByteArray;
begin
  Img := MakePCWDisk;
  try
    PlantDirEntry(Img, 2, 0, 2);
    PlantPlus3DOSHeader(DataSector(Img), 228); // 128 header + 100 payload
    DataSector(Img).Data[128] := $5A; // a marker where the payload starts

    FSys := TCPMFileSystem.Create(Img.Disk);
    try
      Files := FSys.Directory;
      try
        DiskFile := Files[0];
        AssertEquals('honest size kept', 228, DiskFile.Size);

        Data := DiskFile.GetData(True);
        AssertEquals('with header', 228, Length(Data));

        Data := DiskFile.GetData(False);
        AssertEquals('without header', 100, Length(Data));
        AssertEquals('payload marker came back', $5A, Data[0]);
      finally
        FreeDirectory(Files);
      end;
    finally
      FSys.Free;
    end;
  finally
    Img.Free;
  end;
end;

// AMSDOS lengths are 24-bit and cannot wrap an integer, but they can still
// promise more than the disk holds
procedure TCPMFileSystemTest.TestAMSDOSHeaderSizeClampedToCapacity;
var
  Img: TDSKImage;
  FSys: TCPMFileSystem;
  Files: TDirectory;
  DiskFile: TCPMFile;
begin
  Img := MakePCWDisk;
  try
    PlantDirEntry(Img, 2, 0, 2);
    PlantAMSDOSHeader(DataSector(Img), $00FFFFFF); // the 24-bit maximum

    FSys := TCPMFileSystem.Create(Img.Disk);
    try
      Files := FSys.Directory;
      try
        AssertEquals('one file found', 1, Files.Count);
        DiskFile := Files[0];
        AssertEquals('recognised as AMSDOS', 'AMSDOS', DiskFile.HeaderType);
        AssertTrue('size kept to what the disk can hold',
          DiskFile.Size <= Img.Disk.FormattedCapacity);
      finally
        FreeDirectory(Files);
      end;
    finally
      FSys.Free;
    end;
  finally
    Img.Free;
  end;
end;

// RC=0 with BYTES_IN_LAST_RECORD=100 used to compute 0*128 - 128 + 100 = -28
procedure TCPMFileSystemTest.TestExtentSizeFlooredAtZero;
var
  Img: TDSKImage;
  FSys: TCPMFileSystem;
  Files: TDirectory;
  DiskFile: TCPMFile;
  Data: TDiskByteArray;
begin
  Img := MakePCWDisk;
  try
    PlantDirEntry(Img, 0, 100, 2);
    // No header planted: the block keeps its E5 filler, so this reads as a
    // headerless file

    FSys := TCPMFileSystem.Create(Img.Disk);
    try
      Files := FSys.Directory;
      try
        AssertEquals('one file found', 1, Files.Count);
        DiskFile := Files[0];
        AssertEquals('size floored at nothing', 0, DiskFile.Size);
        Data := DiskFile.GetData(True);
        AssertEquals('nothing to extract', 0, Length(Data));
      finally
        FreeDirectory(Files);
      end;
    finally
      FSys.Free;
    end;
  finally
    Img.Free;
  end;
end;

initialization
  RegisterTest(TCPMFileSystemTest);
end.
