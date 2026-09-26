unit TestTeleDisk;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for Teledisk (.td0) loading and saving.

  Fixtures are built in code: plain 'TD' images are assembled byte by byte so
  every sector encoding and flag can be set exactly, and compressed 'td' images
  come from saving a formatted disk and loading it back.
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, DskImage, TeleDisk;

type
  TTeleDiskTest = class(TTestCase)
  private
    function TempName(const Ext: string): string;
    function LoadBytes(Stream: TMemoryStream): TDSKImage;
    function HasMessageLike(List: TStringList; const Text: string): boolean;
    procedure PutHeader(Stream: TStream; const Signature: string; Sequence, Version,
      DataRate, Stepping, Sides: byte);
    procedure PutComment(Stream: TStream; const Text: ansistring);
    procedure PutTrack(Stream: TStream; Count, Cylinder, Head: byte);
    procedure PutSector(Stream: TStream; Cylinder, Head, ID, Size, Flags: byte;
      const Data: array of byte; const Field: array of byte);
    procedure BuildSample(Stream: TMemoryStream);
  published
    procedure TestCrcMatchesRealHeader;
    procedure TestHeaderCheckRejectsBadCRC;
    procedure TestLoadHandBuiltImage;
    procedure TestLoadedImageNumbersTracksAcrossSides;
    procedure TestRoundTripKeepsDataAndGeometry;
    procedure TestRoundTripKeepsFlagsAndComment;
    procedure TestSaveWritesCompressedHeader;
    procedure TestCanSaveRejectsCommentBeyondTD0Limit;
    procedure TestRejectsMultiVolume;
    procedure TestRejectsOldAdvancedCompression;
    procedure TestTruncatedImageIsCorrupt;
    procedure TestTruncatedDataTrimsUnreadSectors;
  end;

implementation

function TTeleDiskTest.TempName(const Ext: string): string;
begin
  Result := IncludeTrailingPathDelimiter(GetTempDir) + 'dim_test_' + TestName + Ext;
end;

function TTeleDiskTest.LoadBytes(Stream: TMemoryStream): TDSKImage;
var
  FileName: string;
begin
  FileName := TempName('.td0');
  Stream.SaveToFile(FileName);
  try
    Result := TDSKImage.CreateFromFile(FileName);
  finally
    DeleteFile(FileName);
  end;
end;

function TTeleDiskTest.HasMessageLike(List: TStringList; const Text: string): boolean;
var
  Idx: integer;
begin
  Result := True;
  for Idx := 0 to List.Count - 1 do
    if Pos(Text, List[Idx]) > 0 then exit;
  Result := False;
end;

procedure TTeleDiskTest.PutHeader(Stream: TStream; const Signature: string;
  Sequence, Version, DataRate, Stepping, Sides: byte);
var
  Header: TTD0Header;
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.Signature[0] := Signature[1];
  Header.Signature[1] := Signature[2];
  Header.Sequence := Sequence;
  Header.Version := Version;
  Header.DataRate := DataRate;
  Header.DriveType := 3;
  Header.Stepping := Stepping;
  Header.Sides := Sides;
  Header.CRC := TD0Crc(Header, 10);
  Stream.WriteBuffer(Header, SizeOf(Header));
end;

procedure TTeleDiskTest.PutComment(Stream: TStream; const Text: ansistring);
var
  Header: TTD0CommentHeader;
begin
  Header.Length := Length(Text);
  Header.Year := 96;
  Header.Month := 3;
  Header.Day := 29;
  Header.Hour := 20;
  Header.Minute := 28;
  Header.Second := 37;
  Header.CRC := TD0Crc(PAnsiChar(Text)^, Length(Text), TD0Crc(Header.Length, 8));
  Stream.WriteBuffer(Header, SizeOf(Header));
  Stream.WriteBuffer(PAnsiChar(Text)^, Length(Text));
end;

procedure TTeleDiskTest.PutTrack(Stream: TStream; Count, Cylinder, Head: byte);
var
  Header: TTD0TrackHeader;
begin
  Header.Sectors := Count;
  Header.Cylinder := Cylinder;
  Header.Head := Head;
  Header.CRC := Byte(TD0Crc(Header, 3));
  Stream.WriteBuffer(Header, SizeOf(Header));
end;

// Data is the sector as it should decode, for its CRC; Field is the stored
// data field (encoding byte first), or empty for a sector without data
procedure TTeleDiskTest.PutSector(Stream: TStream; Cylinder, Head, ID, Size, Flags: byte;
  const Data: array of byte; const Field: array of byte);
var
  Header: TTD0SectorHeader;
begin
  Header.Cylinder := Cylinder;
  Header.Head := Head;
  Header.ID := ID;
  Header.Size := Size;
  Header.Flags := Flags;
  Header.CRC := 0;
  if Length(Data) > 0 then
    Header.CRC := Byte(TD0Crc(Data[0], Length(Data)));
  Stream.WriteBuffer(Header, SizeOf(Header));
  if Length(Field) > 0 then
  begin
    Stream.WriteWord(Length(Field));
    Stream.WriteBuffer(Field[0], Length(Field));
  end;
end;

// Two sides and three cylinders, of which cylinder 1 was never imaged and side
// 1 has only cylinder 0. Side 0 cylinder 0 holds one sector of each encoding
// and each flag; side 1 cylinder 0 is FM.
procedure TTeleDiskTest.BuildSample(Stream: TMemoryStream);
var
  Data: array[0..255] of byte;
  Small: array[0..127] of byte;
  Field: array of byte;
  Idx: integer;
begin
  PutHeader(Stream, 'TD', 0, 21, TD0Rate250, TD0StepHasComment, 2);
  PutComment(Stream, 'First line'#0'Second line'#0);

  PutTrack(Stream, 6, 0, 0);

  // Raw
  for Idx := 0 to 255 do Data[Idx] := Idx;
  SetLength(Field, 257);
  Field[0] := TD0EncodingRaw;
  Move(Data, Field[1], 256);
  PutSector(Stream, 0, 0, 1, 1, 0, Data, Field);

  // One repeated word
  for Idx := 0 to 127 do
  begin
    Data[Idx * 2] := $12;
    Data[Idx * 2 + 1] := $34;
  end;
  PutSector(Stream, 0, 0, 2, 1, 0, Data, [TD0EncodingRepeat, 128, 0, $12, $34]);

  // Run-length: four literal bytes, then $55 $AA 126 times
  Data[0] := Ord('A'); Data[1] := Ord('B'); Data[2] := Ord('C'); Data[3] := Ord('D');
  for Idx := 2 to 127 do
  begin
    Data[Idx * 2] := $55;
    Data[Idx * 2 + 1] := $AA;
  end;
  PutSector(Stream, 0, 0, 3, 1, 0, Data,
    [TD0EncodingRLE, 0, 4, Ord('A'), Ord('B'), Ord('C'), Ord('D'), 1, 126, $55, $AA]);

  FillChar(Data, SizeOf(Data), $E5);
  PutSector(Stream, 0, 0, 4, 1, TD0FlagCRCError, Data, [TD0EncodingRepeat, 128, 0, $E5, $E5]);
  PutSector(Stream, 0, 0, 5, 1, TD0FlagDeleted, Data, [TD0EncodingRepeat, 128, 0, $E5, $E5]);
  PutSector(Stream, 0, 0, 6, 1, TD0FlagNoData, [], []);

  FillChar(Small, SizeOf(Small), $E5);
  PutTrack(Stream, 1, 0, 1 or TD0HeadFM);
  PutSector(Stream, 0, 1, 1, 0, 0, Small, [TD0EncodingRepeat, 64, 0, $E5, $E5]);

  PutTrack(Stream, 1, 2, 0);
  PutSector(Stream, 2, 0, 1, 0, 0, Small, [TD0EncodingRepeat, 64, 0, $E5, $E5]);

  Stream.WriteByte(TD0EndOfImage);
end;

// The first ten header bytes of a real Teledisk image of a PCW CP/M disc,
// whose stored CRC is $5D66: pins the polynomial, bit order and seed together
procedure TTeleDiskTest.TestCrcMatchesRealHeader;
const
  Header: array[0..9] of byte = ($74, $64, $00, $41, $15, $00, $01, $80, $00, $01);
begin
  AssertEquals('header CRC', $5D66, TD0Crc(Header, 10));
end;

procedure TTeleDiskTest.TestHeaderCheckRejectsBadCRC;
var
  Stream: TMemoryStream;
  Header: TTD0Header;
begin
  Stream := TMemoryStream.Create;
  try
    PutHeader(Stream, 'td', 0, 21, 0, 0, 1);
    Move(Stream.Memory^, Header, SizeOf(Header));
    AssertTrue('good header', IsTD0Header(Header));
    Header.Sides := 2;
    AssertFalse('header changed after its CRC', IsTD0Header(Header));
    Header.Sides := 1;
    Header.Signature[0] := 'X';
    AssertFalse('wrong signature', IsTD0Header(Header));
  finally
    Stream.Free;
  end;
end;

procedure TTeleDiskTest.TestLoadHandBuiltImage;
var
  Stream: TMemoryStream;
  Img: TDSKImage;
  Track: TDSKTrack;
begin
  Stream := TMemoryStream.Create;
  try
    BuildSample(Stream);
    Img := LoadBytes(Stream);
  finally
    Stream.Free;
  end;

  try
    AssertEquals('format', Ord(diTeleDisk), Ord(Img.FileFormat));
    AssertFalse('not corrupt: ' + Img.Messages.Text, Img.Corrupt);
    AssertEquals('creator', 'Teledisk 2.1', Img.Creator);
    AssertEquals('comment', 'First line' + LineEnding + 'Second line', Img.Comment);
    AssertEquals('sides', 2, Img.Disk.Sides);
    AssertEquals('side 0 tracks', 3, Img.Disk.Side[0].Tracks);
    AssertEquals('side 1 tracks', 3, Img.Disk.Side[1].Tracks);

    Track := Img.Disk.Side[0].Track[0];
    AssertEquals('sectors', 6, Track.Sectors);
    AssertEquals('MFM', Ord(rmMFM), Ord(Track.RecordingMode));
    AssertEquals('data rate', Ord(drSingleOrDoubleDensity), Ord(Track.DataRate));

    AssertEquals('raw size', 256, Track.Sector[0].DataSize);
    AssertEquals('raw byte', 5, Track.Sector[0].Data[5]);
    AssertEquals('raw last', 255, Track.Sector[0].Data[255]);

    AssertEquals('repeat first', $12, Track.Sector[1].Data[0]);
    AssertEquals('repeat last', $34, Track.Sector[1].Data[255]);

    AssertEquals('RLE literal', Ord('D'), Track.Sector[2].Data[3]);
    AssertEquals('RLE pattern', $55, Track.Sector[2].Data[4]);
    AssertEquals('RLE last', $AA, Track.Sector[2].Data[255]);

    AssertEquals('CRC error ST1', $20, Track.Sector[3].FDCStatus[1]);
    AssertEquals('CRC error ST2', $20, Track.Sector[3].FDCStatus[2]);
    AssertEquals('deleted ST2', $40, Track.Sector[4].FDCStatus[2]);
    AssertEquals('no data size', 0, Track.Sector[5].DataSize);
    AssertEquals('no data ST1', $01, Track.Sector[5].FDCStatus[1]);
    AssertEquals('no data ST2', $01, Track.Sector[5].FDCStatus[2]);
    AssertEquals('sector ID', 6, Track.Sector[5].ID);

    AssertEquals('FM track', Ord(rmFM), Ord(Img.Disk.Side[1].Track[0].RecordingMode));
    AssertEquals('128-byte sector', 128, Img.Disk.Side[1].Track[0].Sector[0].DataSize);

    AssertEquals('missing cylinder unformatted', 0, Img.Disk.Side[0].Track[1].Sectors);
    AssertEquals('cylinder 2 present', 1, Img.Disk.Side[0].Track[2].Sectors);
    AssertEquals('side 1 cylinder 2 unformatted', 0, Img.Disk.Side[1].Track[2].Sectors);
    AssertFalse('a loaded image is unchanged', Img.IsChanged);
  finally
    Img.Free;
  end;
end;

procedure TTeleDiskTest.TestLoadedImageNumbersTracksAcrossSides;
var
  Stream: TMemoryStream;
  Img: TDSKImage;
begin
  Stream := TMemoryStream.Create;
  try
    BuildSample(Stream);
    Img := LoadBytes(Stream);
  finally
    Stream.Free;
  end;

  try
    AssertEquals('side 0 cyl 0', 0, Img.Disk.Side[0].Track[0].Logical);
    AssertEquals('side 1 cyl 0', 1, Img.Disk.Side[1].Track[0].Logical);
    AssertEquals('side 0 cyl 2', 4, Img.Disk.Side[0].Track[2].Logical);
    AssertEquals('side 1 track number', 2, Img.Disk.Side[1].Track[2].Track);
    AssertEquals('side 1 side number', 1, Img.Disk.Side[1].Track[2].Side);
  finally
    Img.Free;
  end;
end;

procedure TTeleDiskTest.TestRoundTripKeepsDataAndGeometry;
var
  Img, Reloaded: TDSKImage;
  Spec: TDSKFormatSpecification;
  FileName: string;
  SIdx, TIdx, EIdx, Idx: integer;
  Sector: TDSKSector;
begin
  FileName := TempName('.td0');
  Img := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(1); // PCW CF2DD, 80T DS 9 x 512
  try
    Img.Disk.Format(Spec);
  finally
    Spec.Free;
  end;

  try
    // Vary the data by position so any sector landing in the wrong place shows
    for SIdx := 0 to 1 do
      for TIdx := 0 to 79 do
        if TIdx mod 3 = 0 then
          for EIdx := 0 to 8 do
            for Idx := 0 to 511 do
              Img.Disk.Side[SIdx].Track[TIdx].Sector[EIdx].Data[Idx] :=
                (SIdx * 131 + TIdx * 31 + EIdx * 7 + Idx) mod 251;
    AssertTrue('save succeeded: ' + Img.Messages.Text,
      Img.SaveFile(FileName, diTeleDisk, False, False));

    Reloaded := TDSKImage.CreateFromFile(FileName);
    try
      AssertEquals('format', Ord(diTeleDisk), Ord(Reloaded.FileFormat));
      AssertFalse('not corrupt: ' + Reloaded.Messages.Text, Reloaded.Corrupt);
      AssertEquals('no messages: ' + Reloaded.Messages.Text, 0, Reloaded.Messages.Count);
      AssertEquals('sides', 2, Reloaded.Disk.Sides);
      AssertEquals('tracks', 80, Reloaded.Disk.Side[0].Tracks);
      for SIdx := 0 to 1 do
        for TIdx := 0 to 79 do
        begin
          AssertEquals('sectors', 9, Reloaded.Disk.Side[SIdx].Track[TIdx].Sectors);
          for EIdx := 0 to 8 do
          begin
            Sector := Reloaded.Disk.Side[SIdx].Track[TIdx].Sector[EIdx];
            AssertEquals('ID', Img.Disk.Side[SIdx].Track[TIdx].Sector[EIdx].ID, Sector.ID);
            AssertEquals('size', 512, Sector.DataSize);
            AssertEquals('FDC size', 2, Sector.FDCSize);
            if not CompareMem(@Sector.Data[0],
              @Img.Disk.Side[SIdx].Track[TIdx].Sector[EIdx].Data[0], 512) then
              Fail(Format('side %d track %d sector %d data differs', [SIdx, TIdx, EIdx]));
          end;
        end;
    finally
      Reloaded.Free;
    end;
  finally
    Img.Free;
    DeleteFile(FileName);
  end;
end;

procedure TTeleDiskTest.TestRoundTripKeepsFlagsAndComment;
var
  Img, Reloaded: TDSKImage;
  Spec: TDSKFormatSpecification;
  FileName: string;
  Track: TDSKTrack;
begin
  FileName := TempName('.td0');
  Img := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(0); // 40T SS 9 x 512
  try
    Img.Disk.Format(Spec);
  finally
    Spec.Free;
  end;

  try
    Img.Comment := 'Archived' + LineEnding + 'for testing';
    Track := Img.Disk.Side[0].Track[1];
    Track.Sector[0].FDCStatus[1] := $20;
    Track.Sector[0].FDCStatus[2] := $20;
    Track.Sector[1].FDCStatus[2] := $40;
    Track.Sector[2].DataSize := 0;
    Track.Sector[4].FDCStatus[1] := $01; // data found without its ID
    Img.Disk.Side[0].Track[2].RecordingMode := rmFM;
    AssertTrue('save succeeded: ' + Img.Messages.Text,
      Img.SaveFile(FileName, diTeleDisk, False, False));

    Reloaded := TDSKImage.CreateFromFile(FileName);
    try
      AssertFalse('not corrupt: ' + Reloaded.Messages.Text, Reloaded.Corrupt);
      AssertEquals('comment', 'Archived' + LineEnding + 'for testing', Reloaded.Comment);
      AssertEquals('sides', 1, Reloaded.Disk.Sides);
      AssertEquals('tracks', 40, Reloaded.Disk.Side[0].Tracks);
      Track := Reloaded.Disk.Side[0].Track[1];
      AssertEquals('CRC error ST1', $20, Track.Sector[0].FDCStatus[1]);
      AssertEquals('CRC error ST2', $20, Track.Sector[0].FDCStatus[2]);
      AssertEquals('deleted ST2', $40, Track.Sector[1].FDCStatus[2]);
      AssertEquals('no data', 0, Track.Sector[2].DataSize);
      AssertEquals('no data ST2', $01, Track.Sector[2].FDCStatus[2]);
      AssertEquals('others untouched', 0, Track.Sector[3].FDCStatus[2]);
      AssertEquals('no ID ST1', $01, Track.Sector[4].FDCStatus[1]);
      AssertEquals('no ID keeps data', 512, Track.Sector[4].DataSize);
      AssertEquals('FM track', Ord(rmFM), Ord(Reloaded.Disk.Side[0].Track[2].RecordingMode));
      AssertEquals('MFM track', Ord(rmMFM), Ord(Reloaded.Disk.Side[0].Track[3].RecordingMode));
    finally
      Reloaded.Free;
    end;
  finally
    Img.Free;
    DeleteFile(FileName);
  end;
end;

procedure TTeleDiskTest.TestSaveWritesCompressedHeader;
var
  Img: TDSKImage;
  Spec: TDSKFormatSpecification;
  FileName: string;
  Stream: TFileStream;
  Header: TTD0Header;
begin
  FileName := TempName('.td0');
  Img := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(1);
  try
    Img.Disk.Format(Spec);
  finally
    Spec.Free;
  end;

  try
    AssertTrue('save succeeded', Img.SaveFile(FileName, diTeleDisk, False, False));
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      Stream.ReadBuffer(Header, SizeOf(Header));
      AssertTrue('valid header', IsTD0Header(Header));
      AssertEquals('advanced compression', 'td', Header.Signature[0] + Header.Signature[1]);
      AssertEquals('version', 21, Header.Version);
      AssertEquals('sides', 2, Header.Sides);
      AssertEquals('no comment', 0, Header.Stepping and TD0StepHasComment);
      // 720K of blank sectors comes to a few kilobytes
      AssertTrue('compressed', Stream.Size < 16384);
    finally
      Stream.Free;
    end;
    AssertEquals('saved format kept', Ord(diTeleDisk), Ord(Img.FileFormat));
  finally
    Img.Free;
    DeleteFile(FileName);
  end;
end;

procedure TTeleDiskTest.TestRejectsMultiVolume;
var
  Stream: TMemoryStream;
  Img: TDSKImage;
begin
  Stream := TMemoryStream.Create;
  try
    PutHeader(Stream, 'TD', 1, 21, 0, 0, 1);
    Stream.WriteByte(TD0EndOfImage);
    Img := LoadBytes(Stream);
  finally
    Stream.Free;
  end;

  try
    AssertEquals('format', Ord(diTeleDisk), Ord(Img.FileFormat));
    AssertTrue('corrupt', Img.Corrupt);
    AssertTrue('says why', HasMessageLike(Img.Messages, 'multi-volume'));
  finally
    Img.Free;
  end;
end;

procedure TTeleDiskTest.TestRejectsOldAdvancedCompression;
var
  Stream: TMemoryStream;
  Img: TDSKImage;
begin
  Stream := TMemoryStream.Create;
  try
    PutHeader(Stream, 'td', 0, 15, 0, 0, 1);
    Stream.WriteByte(0);
    Img := LoadBytes(Stream);
  finally
    Stream.Free;
  end;

  try
    AssertTrue('corrupt', Img.Corrupt);
    AssertTrue('says why', HasMessageLike(Img.Messages, 'advanced compression is not supported'));
  finally
    Img.Free;
  end;
end;

procedure TTeleDiskTest.TestTruncatedImageIsCorrupt;
var
  Stream: TMemoryStream;
  Img: TDSKImage;
begin
  Stream := TMemoryStream.Create;
  try
    BuildSample(Stream);
    // Cut part way into the raw sector's data
    Stream.Size := 12 + 10 + 23 + 4 + 6 + 100;
    Img := LoadBytes(Stream);
  finally
    Stream.Free;
  end;

  try
    AssertTrue('corrupt', Img.Corrupt);
    AssertTrue('says why', HasMessageLike(Img.Messages, 'ran past the end of the file'));
    AssertEquals('side kept', 2, Img.Disk.Sides);
  finally
    Img.Free;
  end;
end;

procedure TTeleDiskTest.TestCanSaveRejectsCommentBeyondTD0Limit;
var
  Img: TDSKImage;
  Spec: TDSKFormatSpecification;
begin
  Img := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(0);
  try
    Img.Disk.Format(Spec);
  finally
    Spec.Free;
  end;
  try
    Img.Comment := StringOfChar('C', High(Word));
    AssertFalse('terminating NUL would overflow the TD0 comment length',
      Img.CanSave(diTeleDisk));
    Img.Comment := StringOfChar('C', High(Word) - 1);
    AssertTrue('maximum representable comment length is accepted',
      Img.CanSave(diTeleDisk));
  finally
    Img.Free;
  end;
end;

procedure TTeleDiskTest.TestTruncatedDataTrimsUnreadSectors;
var
  Stream: TMemoryStream;
  Img: TDSKImage;
begin
  Stream := TMemoryStream.Create;
  try
    PutHeader(Stream, 'TD', 0, 21, TD0Rate250, 0, 1);
    PutTrack(Stream, 2, 0, 0);
    PutSector(Stream, 0, 0, 1, 1, TD0FlagNoData, [], []);
    PutSector(Stream, 0, 0, 2, 1, 0, [], []); // missing data field
    Img := LoadBytes(Stream);
  finally
    Stream.Free;
  end;
  try
    AssertTrue('incomplete data marks the image corrupt', Img.Corrupt);
    AssertEquals('only the complete sector remains', 1,
      Img.Disk.Side[0].Track[0].Sectors);
  finally
    Img.Free;
  end;
end;

initialization
  RegisterTest(TTeleDiskTest);
end.
