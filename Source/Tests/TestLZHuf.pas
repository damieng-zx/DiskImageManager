unit TestLZHuf;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the LZHUF codec Teledisk compresses with.

  Round trips cover the encoder and decoder together; the slice of a real
  Teledisk stream pins the decoder to what Teledisk itself wrote.
}

interface

uses
  Classes, SysUtils, base64, fpcunit, testregistry, LZHuf;

type
  TLZHufTest = class(TTestCase)
  private
    function RoundTrip(const Input: TBytes): TBytes;
    function Compress(const Input: TBytes): TBytes;
    procedure AssertSameBytes(const Name: string; const Expected, Actual: TBytes);
  published
    procedure TestRoundTripEmpty;
    procedure TestRoundTripSingleByte;
    procedure TestRoundTripEveryShortLength;
    procedure TestRoundTripRepeatedByte;
    procedure TestRoundTripPseudoRandom;
    procedure TestRoundTripTriggersHuffmanReconstruction;
    procedure TestRoundTripTextLongerThanWindow;
    procedure TestRepetitiveInputShrinks;
    procedure TestPositionPrefixLengths;
    procedure TestDecodesRealTelediskStream;
  end;

implementation

function TLZHufTest.Compress(const Input: TBytes): TBytes;
var
  Src, Dest: TMemoryStream;
begin
  Src := TMemoryStream.Create;
  Dest := TMemoryStream.Create;
  try
    if Length(Input) > 0 then
      Src.WriteBuffer(Input[0], Length(Input));
    Src.Position := 0;
    LZHufCompress(Src, Dest);
    SetLength(Result, Dest.Size);
    if Dest.Size > 0 then
      Move(Dest.Memory^, Result[0], Dest.Size);
  finally
    Dest.Free;
    Src.Free;
  end;
end;

function TLZHufTest.RoundTrip(const Input: TBytes): TBytes;
var
  Packed_: TBytes;
  Src, Dest: TMemoryStream;
begin
  Packed_ := Compress(Input);
  Src := TMemoryStream.Create;
  Dest := TMemoryStream.Create;
  try
    if Length(Packed_) > 0 then
      Src.WriteBuffer(Packed_[0], Length(Packed_));
    Src.Position := 0;
    LZHufDecompress(Src, Dest);
    SetLength(Result, Dest.Size);
    if Dest.Size > 0 then
      Move(Dest.Memory^, Result[0], Dest.Size);
  finally
    Dest.Free;
    Src.Free;
  end;
end;

procedure TLZHufTest.AssertSameBytes(const Name: string; const Expected, Actual: TBytes);
var
  Idx: integer;
begin
  AssertEquals(Name + ' length', Length(Expected), Length(Actual));
  for Idx := 0 to High(Expected) do
    if Expected[Idx] <> Actual[Idx] then
      Fail(Format('%s differs at byte %d: expected %d, got %d',
        [Name, Idx, Expected[Idx], Actual[Idx]]));
end;

procedure TLZHufTest.TestRoundTripEmpty;
var
  Input: TBytes;
begin
  Input := nil;
  AssertEquals('nothing compresses to nothing', 0, Length(Compress(Input)));
  AssertEquals('and back', 0, Length(RoundTrip(Input)));
end;

procedure TLZHufTest.TestRoundTripSingleByte;
var
  Input: TBytes;
begin
  SetLength(Input, 1);
  Input[0] := $42;
  AssertSameBytes('one byte', Input, RoundTrip(Input));
end;

// Nothing records where the stream stops, so the padding in the last byte must
// never read as one more symbol, whatever the length leaves it holding
procedure TLZHufTest.TestRoundTripEveryShortLength;
var
  Input: TBytes;
  Len, Idx: integer;
begin
  for Len := 1 to 300 do
  begin
    SetLength(Input, Len);
    for Idx := 0 to Len - 1 do
      Input[Idx] := (Idx * 7 + Len) mod 5;
    AssertSameBytes(Format('length %d', [Len]), Input, RoundTrip(Input));
  end;
end;

procedure TLZHufTest.TestRoundTripRepeatedByte;
var
  Input: TBytes;
begin
  SetLength(Input, 65536);
  FillChar(Input[0], Length(Input), $E5);
  AssertSameBytes('64K of E5', Input, RoundTrip(Input));
end;

procedure TLZHufTest.TestRoundTripPseudoRandom;
var
  Input: TBytes;
  Idx: integer;
  Seed: longword;
begin
  SetLength(Input, 20000);
  Seed := 12345;
  for Idx := 0 to High(Input) do
  begin
    Seed := Seed * 1103515245 + 12345;
    Input[Idx] := (Seed shr 16) and $FF;
  end;
  AssertSameBytes('noise', Input, RoundTrip(Input));
end;

procedure TLZHufTest.TestRoundTripTriggersHuffmanReconstruction;
var
  Input, Packed_: TBytes;
  Idx: integer;
  Seed: longword;
begin
  // More than MaxFreq symbols are processed, forcing THuffTree.Reconst while
  // using reproducible incompressible data rather than a repetition-heavy run.
  SetLength(Input, 40000);
  Seed := $13579BDF;
  for Idx := 0 to High(Input) do
  begin
    Seed := Seed * 1664525 + 1013904223;
    Input[Idx] := (Seed shr 24) and $FF;
  end;
  Packed_ := Compress(Input);
  AssertTrue('compressed fixture is nonempty', Length(Packed_) > 0);
  AssertSameBytes('round trip across Huffman reconstruction', Input,
    RoundTrip(Input));
end;

procedure TLZHufTest.TestRoundTripTextLongerThanWindow;
var
  Text: string;
  Input: TBytes;
  Idx: integer;
begin
  Text := '';
  for Idx := 1 to 800 do
    Text := Text + Format('Line %d of a CP/M directory listing; ', [Idx * 37 mod 101]);
  AssertTrue('past the 4K window', Length(Text) > 3 * 4096);
  SetLength(Input, Length(Text));
  Move(Text[1], Input[0], Length(Text));
  AssertSameBytes('text', Input, RoundTrip(Input));
end;

procedure TLZHufTest.TestRepetitiveInputShrinks;
var
  Input: TBytes;
begin
  SetLength(Input, 65536);
  FillChar(Input[0], Length(Input), 0);
  AssertTrue('64K of zeros compresses below 4K', Length(Compress(Input)) < 4096);
end;

procedure TLZHufTest.TestPositionPrefixLengths;
var
  Input, Packed_: TBytes;
  Seed: longword;
  Hash: int64;
  Idx, K, TargetPos, SourcePos, OldLength: integer;
begin
  // A deterministic noise window followed by 64 three-byte matches at each
  // position band (0..63). This exercises the complete 3-8 bit prefix table.
  SetLength(Input, 8192);
  Seed := $2468ACE1;
  for Idx := 0 to High(Input) do
  begin
    Seed := Seed * 1664525 + 1013904223;
    Input[Idx] := (Seed shr 24) and $FF;
  end;

  for K := 0 to 63 do
  begin
    OldLength := Length(Input);
    SetLength(Input, OldLength + 4);
    Input[OldLength] := (K * 37 + 11) and $FF;
    TargetPos := OldLength + 1;
    SourcePos := TargetPos - (K + 1) * 64;
    Input[TargetPos] := Input[SourcePos];
    Input[TargetPos + 1] := Input[SourcePos + 1];
    Input[TargetPos + 2] := Input[SourcePos + 2];
  end;

  Packed_ := Compress(Input);
  Hash := 0;
  for Idx := 0 to High(Packed_) do
    Hash := (Hash * 131 + Packed_[Idx]) mod 2147483647;
  // Pins the independently generated encoder stream; the decoder must recover
  // the expected plaintext from that stable stream via RoundTrip.
  AssertEquals('compressed position-code fixture signature', 418470217, Hash);
  AssertSameBytes('all position-code bands', Input, RoundTrip(Input));
end;

// The opening compressed bytes of a real Teledisk 2.1 image of an Amstrad PCW
// CP/M-3 boot disc. A prefix of the stream decodes to a prefix of the output,
// which opens with the image's comment block.
procedure TLZHufTest.TestDecodesRealTelediskStream;
const
  Slice =
    'WTXpYz2Y/U6DUbHn9zd9nc7/dbzWf8FsgD4/mz+H1qfep8v3/qnNrqthSe2tl4m+4PCwp/e0E3us' +
    'ZNfNDB98uljbiadt+LINi8Z9AoIAysRngOQY3HQxKxANa9pBP8BgL9t3qAG8hFrVf5TpHiE6xZg6' +
    '61KYDnWuWSdlQ0pzmdY=';
  ExpectedHex =
    'CDA9460060031D141C2543502F4D2D332E302073797374656D206469736B20666F7220416D' +
    '7374726164203832353600353132206279746520736563746F722C20312D392C20323A31' +
    '00000000000000090000340000010200E201020000002809020103022A52000000000004' +
    '31F0FF3EFF32D0F8CDB4F0210000E51100D00604CD8EF010FB';
var
  Raw: string;
  Src, Dest: TMemoryStream;
  Output: PByte;
  Text: string;
  Expected, Actual: TBytes;
  Idx: integer;
begin
  Raw := DecodeStringBase64(Slice);
  Src := TMemoryStream.Create;
  Dest := TMemoryStream.Create;
  try
    Src.WriteBuffer(Raw[1], Length(Raw));
    Src.Position := 0;
    LZHufDecompress(Src, Dest);
    AssertEquals('full decoded fixture size', 134, Dest.Size);
    SetLength(Expected, Length(ExpectedHex) div 2);
    for Idx := 0 to High(Expected) do
      Expected[Idx] := StrToInt('$' + Copy(ExpectedHex, Idx * 2 + 1, 2));
    SetLength(Actual, Dest.Size);
    Move(Dest.Memory^, Actual[0], Dest.Size);
    AssertSameBytes('complete Teledisk decompressed payload', Expected, Actual);
    Output := Dest.Memory;
    AssertEquals('comment CRC', $A9CD, Output[0] or (Output[1] shl 8));
    AssertEquals('comment length', 70, Output[2] or (Output[3] shl 8));
    AssertEquals('year', 96, Output[4]);
    AssertEquals('month', 3, Output[5]);
    AssertEquals('day', 29, Output[6]);
    SetString(Text, PChar(Output + 10), 37);
    AssertEquals('comment', 'CP/M-3.0 system disk for Amstrad 8256', Text);
  finally
    Dest.Free;
    Src.Free;
  end;
end;

initialization
  RegisterTest(TLZHufTest);
end.
