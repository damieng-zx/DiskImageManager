unit TestByteViews;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the hex, code and text views of a file, and
  for the addresses they take from it.
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, ByteViews, DIMUtils, FileSystem,
  MGTFileSystem, OpusFileSystem;

type
  TByteViewsTest = class(TTestCase)
  published
    procedure TestHexLine;
    procedure TestHexShortLineKeepsItsColumns;
    procedure TestHexAddressesWidenForBigFiles;
    procedure TestHexCharacters;
    procedure TestHexPlaces;
    procedure TestCodeLines;
    procedure TestCodeCutOffAtTheEnd;
    procedure TestCodeStartsAgainAtSyncPoints;
    procedure TestLargeViewsAreNotColoured;
    procedure TestEmptyData;
    procedure TestASCIIText;
    procedure TestMGTAddresses;
    procedure TestOpusAddresses;
    procedure TestCPMProgramAddresses;
  end;

implementation

// The numbers from Origin upwards, as many as asked for
function Counting(Count: integer; First: integer = 0): TDiskByteArray;
var
  Idx: integer;
begin
  Result := nil;
  SetLength(Result, Count);
  for Idx := 0 to Count - 1 do
    Result[Idx] := (First + Idx) and $FF;
end;

function Given(const Values: array of byte): TDiskByteArray;
var
  Idx: integer;
begin
  Result := nil;
  SetLength(Result, Length(Values));
  for Idx := 0 to High(Values) do
    Result[Idx] := Values[Idx];
end;

// The text of a view without its colours: what comes after the header, with the
// groups that colour part of a line taken away and line ends as bars
function Shown(const RTF: string): string;
var
  Idx: integer;
begin
  Result := Copy(RTF, Pos('\fs20 ', RTF) + 6, MaxInt);
  Delete(Result, Length(Result), 1);
  for Idx := 1 to 5 do
    Result := StringReplace(Result, '{\cf' + IntToStr(Idx) + ' ', '',
      [rfReplaceAll]);
  // A closing brace that is not escaped ends a colour
  Result := StringReplace(Result, '\}', #1, [rfReplaceAll]);
  Result := StringReplace(Result, '}', '', [rfReplaceAll]);
  Result := StringReplace(Result, #1, '\}', [rfReplaceAll]);
  Result := StringReplace(Result, '\par ', '|', [rfReplaceAll]);
end;

procedure TByteViewsTest.TestHexLine;
var
  View: TByteView;
begin
  View := BuildHexView(Counting(16, $41), $8000, csASCII, 'Mono');
  try
    AssertEquals('8000  41 42 43 44 45 46 47 48  49 4A 4B 4C 4D 4E 4F 50  ' +
      'ABCDEFGHIJKLMNOP', Shown(View.RTF));
    AssertEquals(1, View.LineCount);
    AssertTrue('in the font asked for', Pos('Mono;', View.RTF) > 0);
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestHexShortLineKeepsItsColumns;
var
  View: TByteView;
  Lines: TStringArray;
begin
  View := BuildHexView(Counting(18, $41), 0, csASCII, 'Mono');
  try
    Lines := Shown(View.RTF).Split(['|']);
    AssertEquals(2, Length(Lines));
    AssertEquals('0010  51 52', Copy(Lines[1], 1, 11));
    AssertEquals('characters start where the full line has them',
      Pos('ABC', Lines[0]), Pos('QR', Lines[1]));
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestHexAddressesWidenForBigFiles;
var
  View: TByteView;
begin
  View := BuildHexView(Counting(32), $FFF0, csASCII, 'Mono');
  try
    AssertEquals('every address as wide as the last', '0FFF0', Copy(Shown(View.RTF), 1, 5));
    AssertTrue(Pos('|10000  ', Shown(View.RTF)) > 0);
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestHexCharacters;
var
  View: TByteView;
  Data: TDiskByteArray;
begin
  Data := Given([$20, $5B, $5C, $5D, $7B, $7D, $60, $7F, $1F, $80]);
  View := BuildHexView(Data, 0, csASCII, 'Mono');
  try
    AssertTrue('RTF characters escaped, others dotted',
      Pos(' [\\]\{\}`...', Shown(View.RTF)) > 0);
  finally
    View.Free;
  end;
  View := BuildHexView(Data, 0, csSpectrum, 'Mono');
  try
    AssertTrue('Spectrum pound and copyright signs',
      Pos(' [\\]\{\}\u163?\u169?..', Shown(View.RTF)) > 0);
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestHexPlaces;
const
  // Columns on a line with a four digit address
  Numbers = 6;
  Characters = 56;
var
  View: TByteView;
  Second: integer;

  procedure Points(const Where: string; Position, Offset: integer);
  begin
    AssertEquals(Where, Offset, View.OffsetAt(Position));
  end;

begin
  View := BuildHexView(Counting(20), 0, csASCII, 'Mono');
  try
    Points('the address', 0, 0);
    Points('first number', Numbers, 0);
    Points('second number', Numbers + 3, 1);
    Points('eighth number', Numbers + 7 * 3, 7);
    Points('the gap', Numbers + 8 * 3, 7);
    Points('ninth number', Numbers + 8 * 3 + 1, 8);
    Points('last number', Numbers + 15 * 3 + 1, 15);
    Points('first character', Characters, 0);
    Points('last character', Characters + 15, 15);
    Points('the end of the line', Characters + 16, 15);

    // The second line follows the first and its ending
    Second := Characters + 16 + 1;
    AssertEquals(Second, View.Lines[1].Position);
    Points('second line', Second + Numbers + 3, 17);
    Points('past a short line', Second + Numbers + 10 * 3, 19);
    Points('its characters', Second + Characters + 2, 18);

    AssertEquals(0, View.LineOf(15));
    AssertEquals(1, View.LineOf(16));
    AssertEquals(1, View.LineAt(Second));
    AssertEquals(0, View.LineAt(Second - 1));
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestCodeLines;
var
  View: TByteView;
begin
  View := BuildZ80View(Given([$3E, $01, $C9, $21, $00, $40]), $8000, [], 'Mono');
  try
    AssertEquals(
      '8000  3E 01        LD A,01|' +
      '8002  C9           RET|' +
      '8003  21 00 40     LD HL,4000', Shown(View.RTF));
    AssertEquals(3, View.LineCount);
    AssertEquals(2, View.Lines[1].Offset);
    AssertEquals('anywhere on a line is its instruction', 3,
      View.OffsetAt(View.Lines[2].Position + 20));
    AssertEquals('the line showing the middle of an instruction', 2, View.LineOf(4));
    // Each position counts the visible text before it and one for each ending
    AssertEquals(Length('8000  3E 01        LD A,01') + 1, View.Lines[1].Position);
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestCodeCutOffAtTheEnd;
var
  View: TByteView;
begin
  View := BuildZ80View(Given([$00, $21, $34]), 0, [], 'Mono');
  try
    AssertEquals(
      '0000  00           NOP|' +
      '0001  21 34        DB 21,34', Shown(View.RTF));
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestCodeStartsAgainAtSyncPoints;
var
  View: TByteView;
  Data: TDiskByteArray;
begin
  // Read from the start this is LD BC,3E01 and NOP; from the second byte it is
  // LD A,00
  Data := Given([$01, $3E, $00, $C9]);
  View := BuildZ80View(Data, 0, [], 'Mono');
  try
    AssertEquals('0000  01 3E 00     LD BC,003E|0003  C9           RET',
      Shown(View.RTF));
  finally
    View.Free;
  end;
  // Given out of order, and one past the end
  View := BuildZ80View(Data, 0, [99, 1], 'Mono');
  try
    AssertEquals(
      '0000  01           DB 01|' +
      '0001  3E 00        LD A,00|' +
      '0003  C9           RET', Shown(View.RTF));
    AssertEquals(1, View.LineOf(1));
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestLargeViewsAreNotColoured;
var
  View: TByteView;
begin
  View := BuildHexView(Counting(64), 0, csASCII, 'Mono');
  try
    AssertTrue('a small file is coloured', Pos('{\cf1 ', View.RTF) > 0);
  finally
    View.Free;
  end;
  View := BuildHexView(Counting(ColouredLineLimit * HexBytesPerLine), 0, csASCII,
    'Mono');
  try
    AssertEquals(0, Pos('{\cf', View.RTF));
    AssertEquals(ColouredLineLimit, View.LineCount);
  finally
    View.Free;
  end;
  View := BuildZ80View(Counting(ColouredLineLimit * 2), 0, [], 'Mono');
  try
    AssertEquals(0, Pos('{\cf', View.RTF));
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestEmptyData;
var
  View: TByteView;
begin
  View := BuildHexView(Counting(0), 0, csASCII, 'Mono');
  try
    AssertEquals('', Shown(View.RTF));
    AssertEquals(-1, View.OffsetAt(0));
    AssertEquals(-1, View.LineOf(0));
  finally
    View.Free;
  end;
  View := BuildZ80View(Counting(0), 0, [0], 'Mono');
  try
    AssertEquals(0, View.LineCount);
  finally
    View.Free;
  end;
end;

procedure TByteViewsTest.TestASCIIText;
var
  RTF: string;
begin
  RTF := BuildASCIITextRTF(Given([$41, $0D, $0A, $42, $0A, $43, $0D, $44, $09,
    $7B, $01]), 'Mono');
  AssertEquals('A|B|C|D\tab \{.', Shown(RTF));
end;

procedure TByteViewsTest.TestMGTAddresses;
var
  DiskFile: TMGTFile;
  Load, Exec: integer;

  // An entry of a type, with the start at 214 and the execute address at 218
  procedure Expect(FileType: byte; Start, Parameter, WantedLoad, WantedExec: integer);
  begin
    FillChar(DiskFile.Entry, SizeOf(DiskFile.Entry), 0);
    DiskFile.FileType := FileType;
    DiskFile.Entry[214] := Start and $FF;
    DiskFile.Entry[215] := Start shr 8;
    DiskFile.Entry[218] := Parameter and $FF;
    DiskFile.Entry[219] := Parameter shr 8;
    DiskFile.GetAddresses(Load, Exec);
    AssertEquals('load for type ' + IntToStr(FileType), WantedLoad, Load);
    AssertEquals('execute for type ' + IntToStr(FileType), WantedExec, Exec);
  end;

begin
  DiskFile := TMGTFile.Create(nil);
  try
    Expect(4, 32768, 0, 32768, -1);
    Expect(4, 32768, $FFFF, 32768, -1);
    Expect(4, 24576, 24580, 24576, 24580);
    Expect(7, 0, 0, 16384, -1);       // SCREEN$
    Expect(5, 0, 0, 16384, -1);       // 48K snapshot
    Expect(1, 32768, 100, -1, -1);    // BASIC
  finally
    DiskFile.Free;
  end;
end;

procedure TByteViewsTest.TestOpusAddresses;
var
  DiskFile: TOpusFile;
  Load, Exec: integer;
begin
  DiskFile := TOpusFile.Create(nil);
  try
    DiskFile.FileType := oftCode;
    DiskFile.Param1 := 40000;
    DiskFile.GetAddresses(Load, Exec);
    AssertEquals(40000, Load);
    AssertEquals(-1, Exec);
    DiskFile.FileType := oftBasic;
    DiskFile.GetAddresses(Load, Exec);
    AssertEquals(-1, Load);
  finally
    DiskFile.Free;
  end;
end;

procedure TByteViewsTest.TestCPMProgramAddresses;
var
  DiskFile: TCPMFile;
  Load, Exec: integer;
begin
  DiskFile := TCPMFile.Create(nil);
  try
    DiskFile.HeaderType := 'None';
    DiskFile.FileName := 'pip.com';
    DiskFile.GetAddresses(Load, Exec);
    AssertEquals($100, Load);
    AssertEquals($100, Exec);
    DiskFile.FileName := 'README.TXT';
    DiskFile.GetAddresses(Load, Exec);
    AssertEquals(-1, Load);
    AssertEquals(-1, Exec);
  finally
    DiskFile.Free;
  end;
end;

initialization
  RegisterTest(TByteViewsTest);
end.
