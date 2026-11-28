unit TestTapeImage;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Tests for writing Spectrum tape images.
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, DskImage, DIMUtils, TapeImage;

type
  // A file with nothing to say about tapes beyond the data a test gives it
  TStubFile = class(TDiskFile)
  public
    Size: integer;
    function HasHeader: boolean; override;
    function GetData(WithHeader: boolean): TDiskByteArray; override;
    function GetTapeFile(out Tape: TTapeFile): boolean; override;
  end;

  TTapeImageTest = class(TTestCase)
  private
    procedure AssertStream(const Hex: string; Stream: TMemoryStream);
  published
    procedure TestHeaderAndDataBlocks;
    procedure TestEmptyDataStillHasItsBlock;
    procedure TestFilesFollowOneAnother;
    procedure TestTooBigForABlock;
  end;

implementation

function TStubFile.HasHeader: boolean;
begin
  Result := False;
end;

function TStubFile.GetData(WithHeader: boolean): TDiskByteArray;
begin
  Result := nil;
  SetLength(Result, Size);
end;

function TStubFile.GetTapeFile(out Tape: TTapeFile): boolean;
begin
  inherited GetTapeFile(Tape);
  Tape.Data := GetData(False);
  Result := True;
end;

procedure TTapeImageTest.AssertStream(const Hex: string; Stream: TMemoryStream);
var
  Actual: string;
  Idx: integer;
begin
  Actual := '';
  for Idx := 0 to Stream.Size - 1 do
    Actual := Actual + IntToHex(PByte(Stream.Memory)[Idx], 2);
  AssertEquals(Hex, Actual);
end;

// CODE called "abc" of the bytes 1, 2 and 4, loading at 32768
procedure TTapeImageTest.TestHeaderAndDataBlocks;
var
  Tape: TTapeFile;
  Stream: TMemoryStream;
  Name: ansistring;
begin
  Tape := Default(TTapeFile);
  Tape.FileType := tfCode;
  Name := 'abc       ';
  Move(Name[1], Tape.Name, 10);
  Tape.Param1 := 32768;
  Tape.Param2 := TapeNoValue;
  SetLength(Tape.Data, 3);
  Tape.Data[0] := 1;
  Tape.Data[1] := 2;
  Tape.Data[2] := 4;

  Stream := TMemoryStream.Create;
  try
    WriteTapeFile(Stream, Tape);
    AssertStream(
      // 19 bytes: flag, type, name, length, two parameters, checksum
      '1300' + '00' + '03' + '61626320202020202020' + '0300' + '0080' + '0080' + '40' +
      // 5 bytes: flag, data, checksum
      '0500' + 'FF' + '010204' + 'F8', Stream);
  finally
    Stream.Free;
  end;
end;

procedure TTapeImageTest.TestEmptyDataStillHasItsBlock;
var
  Tape: TTapeFile;
  Stream: TMemoryStream;
begin
  Tape := Default(TTapeFile);
  Stream := TMemoryStream.Create;
  try
    WriteTapeFile(Stream, Tape);
    // A 21-byte header block, then a data block of a flag and a checksum
    AssertEquals(21 + 4, Stream.Size);
    AssertEquals('flag', $FF, PByte(Stream.Memory)[23]);
    AssertEquals('checksum', $FF, PByte(Stream.Memory)[24]);
  finally
    Stream.Free;
  end;
end;

procedure TTapeImageTest.TestFilesFollowOneAnother;
var
  Tape: TTapeFile;
  Stream: TMemoryStream;
begin
  Tape := Default(TTapeFile);
  SetLength(Tape.Data, 100);
  Stream := TMemoryStream.Create;
  try
    WriteTapeFile(Stream, Tape);
    WriteTapeFile(Stream, Tape);
    AssertEquals(2 * (21 + 104), Stream.Size);
  finally
    Stream.Free;
  end;
end;

procedure TTapeImageTest.TestTooBigForABlock;
var
  DiskFile: TStubFile;
  Tape: TTapeFile;
  Stream: TMemoryStream;
begin
  DiskFile := TStubFile.Create;
  Stream := TMemoryStream.Create;
  try
    DiskFile.Size := MaxTapeData;
    AssertTrue('fits', CanSaveToTape(DiskFile, Tape));
    WriteTapeFile(Stream, Tape);
    // The data block's length fills its two bytes
    AssertEquals($FF, PByte(Stream.Memory)[21]);
    AssertEquals($FF, PByte(Stream.Memory)[22]);
    DiskFile.Size := MaxTapeData + 1;
    AssertFalse('one byte too many', CanSaveToTape(DiskFile, Tape));
  finally
    Stream.Free;
    DiskFile.Free;
  end;
end;

initialization
  RegisterTest(TTapeImageTest);
end.
