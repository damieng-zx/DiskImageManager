unit TestSinclairBasic;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the Sinclair (Spectrum) BASIC decoder.

  Drives TSinclairBasicParser.Decode directly with hand-built tokenised byte
  streams, so no disk image is required. Line format on the wire:
    [line-number hi][line-number lo][len lo][len hi][ ...line bytes... $0D ]
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, SinclairBasic;

type
  TSinclairBasicTest = class(TTestCase)
  published
    procedure TestPrintString;
    procedure TestNumberMarkerSkipped;
    procedure TestControlParametersSkipped;
    procedure TestTildeIsNotANumberMarker;
    procedure TestModeDependentToken128K;
    procedure TestModeDependentToken48K;
    procedure TestUserDefinedGraphics;
    procedure TestSpectrumAndPlayDependOnStrings;
    procedure TestBackslashIsEscaped;
    procedure TestLongTextShowsEscapesAsWritten;
    procedure TestSignsAboveASCII;
    procedure TestGraphicsAndUdgRanges;
    procedure TestEveryBlockGraphic;
    procedure TestMultipleLines;
    procedure TestLineNumbersAlign;
    procedure TestStringArrayTwoDimensions;
    procedure TestStringArraySingleString;
    procedure TestStringArrayTrimsPadding;
    procedure TestStringArrayHeaderClampedToData;
    procedure TestStringArrayMapsExtendedCharactersAndTokens;
    procedure TestStringArrayRejectsInvalidDimensions;
    procedure TestPlainTextRTFHandlesLineEndingsAndEscaping;
  end;

implementation

const
  CRLF = #13#10;
  // Token codes used in the tests
  tPRINT = $F5;
  tSPECTRUM_PLAY = $A3; // mode dependent: SPECTRUM (128K) / UDG T (48K)

  // User defined graphics as they are written
  UdgA = '\A';
  UdgR = '\R';
  UdgS = '\S';
  UdgT = '\T';
  UdgU = '\U';

procedure TSinclairBasicTest.TestPrintString;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // 10 PRINT "HI"
    AssertEquals('  10 PRINT "HI"' + CRLF,
      P.Decode([$00, $0A, $06, $00, tPRINT, $22, $48, $49, $22, $0D]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestNumberMarkerSkipped;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // 30 PRINT 1  -- the ASCII '1' is kept, the 5-byte $0E number marker dropped
    AssertEquals('  30 PRINT 1' + CRLF,
      P.Decode([$00, $1E, $09, $00, tPRINT, $31, $0E, $00, $00, $01, $00, $00, $0D]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestControlParametersSkipped;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // INK carries ' ' and AT carries '12': none are text in the listing.
    AssertEquals('  10 PRINT A' + CRLF,
      P.Decode([$00, $0A, $08, $00, tPRINT, $10, $20, $16, $31, $32, $41, $0D]));
  finally
    P.Free;
  end;
end;

// $7E was taken for a second number marker, but the format only has $0E and
// $7E is an ordinary tilde, so a line holding one lost it and the five bytes
// after it: this decoded as '10 PRINT "A"'.
procedure TSinclairBasicTest.TestTildeIsNotANumberMarker;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // 10 PRINT "~HELLO"
    AssertEquals('  10 PRINT "~HELLO"' + CRLF,
      P.Decode([$00, $0A, $0B, $00, tPRINT, $22, $7E, $48, $45, $4C, $4C, $4F, $22, $0D]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestModeDependentToken128K;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // Token $A3 decodes to SPECTRUM in 128K mode (with surrounding spaces)
    AssertEquals('  10 SPECTRUM ' + CRLF,
      P.Decode([$00, $0A, $02, $00, tSPECTRUM_PLAY, $0D]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestModeDependentToken48K;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode48K);
  try
    // The same byte is user defined graphic T in 48K mode
    AssertEquals('  10 ' + UdgT + CRLF,
      P.Decode([$00, $0A, $02, $00, tSPECTRUM_PLAY, $0D]));
  finally
    P.Free;
  end;
end;

// $90 to $A4 are the user defined graphics A to U: written as \A to \U, and
// shown as the letter underlined with the backslash hidden, so that copying it
// from the viewer gives the backslash back
procedure TSinclairBasicTest.TestUserDefinedGraphics;
var
  P: TSinclairBasicParser;
  Code: integer;
  Letter: char;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    for Code := $90 to $A4 do
    begin
      Letter := Chr(Ord('A') + Code - $90);
      // A string array holding the one character
      AssertEquals('UDG ' + Letter, '\' + Letter + CRLF,
        P.DecodeStringArray([$01, $01, $00, Code]));
      AssertTrue('UDG ' + Letter + ' in the viewer',
        Pos('{\v \\}{\ul ' + Letter + '}',
        P.DecodeStringArrayRTF([$01, $01, $00, Code])) > 0);
    end;
  finally
    P.Free;
  end;
end;

// $A3 and $A4 are the graphics T and U inside a string, and on a 128K machine
// the keywords SPECTRUM and PLAY outside one
procedure TSinclairBasicTest.TestSpectrumAndPlayDependOnStrings;
const
  // 10 $A3 "$A3 $A4":$A4
  Mixed: array[0..11] of byte = (
    $00, $0A, $08, $00, $A3, $22, $A3, $A4, $22, $3A, $A4, $0D);
  // 20 REM "$A3"
  Comment: array[0..8] of byte = (
    $00, $14, $05, $00, $EA, $22, $A3, $22, $0D);
  // 30 PRINT "RND" as the one byte $A5
  Keyword: array[0..8] of byte = (
    $00, $1E, $05, $00, $F5, $22, $A5, $22, $0D);
  // The two graphics as the viewer is given them
  ViewT = '{\v \\}{\ul T}';
  ViewU = '{\v \\}{\ul U}';
var
  P: TSinclairBasicParser;
  RTF: string;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    AssertEquals('128K', '  10 SPECTRUM "' + UdgT + UdgU + '": PLAY ' + CRLF,
      P.Decode(Mixed));
    RTF := P.DecodeRTF(Mixed);
    AssertTrue('128K SPECTRUM keyword', Pos('{\cf2\b SPECTRUM }', RTF) > 0);
    AssertTrue('128K string', Pos('{\cf3 "' + ViewT + ViewU + '"}', RTF) > 0);
    AssertTrue('128K PLAY keyword', Pos('{\cf2\b PLAY }', RTF) > 0);

    // A comment is not a string, whatever quotes it holds
    AssertEquals('comment', '  20 REM " SPECTRUM "' + CRLF, P.Decode(Comment));
    AssertTrue('comment in the viewer',
      Pos('"SPECTRUM"', P.DecodeRTF(Comment)) > 0);

    // Other keywords are still keywords in a string, and the viewer keeps them
    AssertTrue('keyword in a string', Pos('"RND"', P.DecodeRTF(Keyword)) > 0);

    P.Mode := sbMode48K;
    AssertEquals('48K', '  10 ' + UdgT + '"' + UdgT + UdgU + '":' + UdgU + CRLF,
      P.Decode(Mixed));
    RTF := P.DecodeRTF(Mixed);
    AssertEquals('48K has no such keyword', 0, Pos('SPECTRUM', RTF));
    AssertEquals('48K has no such keyword either', 0, Pos('PLAY', RTF));
    AssertTrue('48K outside a string', Pos(ViewT + '{\cf3 "', RTF) > 0);
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestSignsAboveASCII;
const
  // The pound and copyright signs as UTF-8
  Signs = #$C2#$A3#$C2#$A9;
  // 10 REM, then a string, each holding both signs and then both bare
  Lines: array[0..16] of byte = (
    $00, $0A, $04, $00, $EA, $60, $7F, $0D,
    $00, $14, $05, $00, $22, $60, $7F, $22, $0D);
var
  P: TSinclairBasicParser;
  R: string;
  Count, At: integer;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    R := P.Decode(Lines);
    AssertTrue('listing', Pos('"' + Signs + '"', R) > 0);
    AssertEquals('string array', Signs + #13#10,
      P.DecodeStringArray([$01, $02, $00, $60, $7F]));

    // The viewer is given them as RTF characters, never as UTF-8 bytes
    R := P.DecodeRTF(Lines) + P.DecodeStringArrayRTF([$01, $02, $00, $60, $7F]) +
      P.DecodeTextRTF([$60, $7F]);
    AssertEquals('no raw bytes', 0, Pos(#$C2, R));
    Count := 0;
    repeat
      At := Pos('\u163?\u169?', R);
      if At > 0 then
      begin
        Inc(Count);
        Delete(R, 1, At);
      end;
    until At = 0;
    AssertEquals('in the comment, string, array and text', 4, Count);
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestGraphicsAndUdgRanges;
var
  P: TSinclairBasicParser;
  R: string;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    R := P.Decode([$00, $0A, $05, $00, $80, $8F, $90, $A2, $0D]);
    // A blank graphic then a full block, which is U+2588
    AssertTrue('block graphics are block elements',
      Pos('10  '#$E2#$96#$88, R) > 0);
    AssertTrue('user defined graphics are letters',
      Pos(#$E2#$96#$88 + UdgA + UdgS, R) > 0);
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestEveryBlockGraphic;
const
  // The Unicode block element for each code from $80 to $8F
  Expected: array[0..15] of word = (
    $0020, $259D, $2598, $2580, $2597, $2590, $259A, $259C,
    $2596, $259E, $258C, $259B, $2584, $259F, $2599, $2588);
var
  P: TSinclairBasicParser;
  Code: integer;
  Plain: UnicodeString;
  RTF, Wanted: string;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    for Code := 0 to 15 do
    begin
      // A string array of one two-character item, ending in a letter so that
      // the blank graphic is not trimmed away as padding
      Plain := UTF8Decode(P.DecodeStringArray([$01, $02, $00, $80 + Code, $41]));
      AssertEquals(Format('$%x code point', [$80 + Code]),
        Expected[Code], Ord(Plain[1]));
      AssertEquals(Format('$%x is one character', [$80 + Code]), Ord('A'), Ord(Plain[2]));

      if Code = 0 then
        Wanted := ' A'
      else
        Wanted := '\u' + IntToStr(Expected[Code]) + '?A';
      RTF := P.DecodeStringArrayRTF([$01, $02, $00, $80 + Code, $41]);
      AssertTrue(Format('$%x in the viewer', [$80 + Code]), Pos(Wanted, RTF) > 0);
    end;
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestMultipleLines;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // 10 PRINT "HI" then 20 CLS  (CLS = $FB)
    AssertEquals('  10 PRINT "HI"' + CRLF + '  20 CLS ' + CRLF,
      P.Decode([$00, $0A, $06, $00, tPRINT, $22, $48, $49, $22, $0D,
                $00, $14, $02, $00, $FB, $0D]));
  finally
    P.Free;
  end;
end;

// Saved character array format (PLUS3DOS header already stripped):
//   [dimension count][dim 1 lo/hi]..[dim K lo/hi][elements]
// The final dimension is the length of each string; the product of the
// earlier dimensions is the number of strings.
procedure TSinclairBasicTest.TestStringArrayTwoDimensions;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // DIM a$(2,3) = two strings of three chars: "ABC" and "DEF"
    AssertEquals('ABC' + CRLF + 'DEF' + CRLF,
      P.DecodeStringArray([$02, $02, $00, $03, $00,
                           $41, $42, $43, $44, $45, $46]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestStringArraySingleString;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // DIM a$(2) = a single two-character string "HI"
    AssertEquals('HI' + CRLF,
      P.DecodeStringArray([$01, $02, $00, $48, $49]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestStringArrayTrimsPadding;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // DIM a$(2,4) with space-padded strings "HI  " and "BYE " - padding trimmed
    AssertEquals('HI' + CRLF + 'BYE' + CRLF,
      P.DecodeStringArray([$02, $02, $00, $04, $00,
                           $48, $49, $20, $20, $42, $59, $45, $20]));
  finally
    P.Free;
  end;
end;

// The dimensions are words and were believed whatever the file held, so a
// corrupt header asked the decoder for billions of items over data that had
// long run out. Only what is really there can be decoded.
procedure TSinclairBasicTest.TestStringArrayHeaderClampedToData;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // Claims 65535 x 65535 elements, with four bytes of data behind it
    AssertEquals('AB' + CRLF + 'CD' + CRLF,
      P.DecodeStringArray([$02, $FF, $FF, $02, $00, $41, $42, $43, $44]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestStringArrayMapsExtendedCharactersAndTokens;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // Character arrays contain literal Spectrum bytes, not BASIC number
    // markers: user defined graphics, including the one that doubles as a
    // keyword in a program, a block graphic and a keyword.
    AssertEquals(UdgR + UdgT + #$E2#$96#$88 + 'PRINT' + CRLF,
      P.DecodeStringArray([$01, $04, $00, $A1, $A3, $8F, $F5]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestStringArrayRejectsInvalidDimensions;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    AssertEquals('empty data has no array header', '', P.DecodeStringArray([]));
    AssertEquals('zero dimensions are invalid', '', P.DecodeStringArray([$00]));
    AssertEquals('truncated dimension table is invalid', '',
      P.DecodeStringArray([$02, $02, $00, $03]));
    AssertEquals('zero-length dimension is invalid', '',
      P.DecodeStringArray([$01, $00, $00]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestPlainTextRTFHandlesLineEndingsAndEscaping;
var
  P: TSinclairBasicParser;
  RTF: string;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    RTF := P.DecodeTextRTF([Ord('A'), Ord(','), Ord('{'), Ord('B'), Ord('}'),
      $0D, $0A, Ord('C'), $0A, Ord('D'), $0D, Ord('E')]);
    AssertTrue('CRLF and lone CR/LF are normalized to paragraphs',
      Pos('A,\{B\}\par C\par D\par E', RTF) > 0);
  finally
    P.Free;
  end;
end;

// Line numbers take four columns, as on the Spectrum, so the statements line up
procedure TSinclairBasicTest.TestLineNumbersAlign;
const
  // Lines 5, 100 and 9999, each just CLS
  Lines: array[0..17] of byte = (
    $00, $05, $02, $00, $FB, $0D,
    $00, $64, $02, $00, $FB, $0D,
    $27, $0F, $02, $00, $FB, $0D);
var
  P: TSinclairBasicParser;
  RTF: string;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    AssertEquals('   5 CLS ' + CRLF + ' 100 CLS ' + CRLF + '9999 CLS ' + CRLF,
      P.Decode(Lines));

    RTF := P.DecodeRTF(Lines);
    AssertTrue('one digit', Pos('{\cf1    5} ', RTF) > 0);
    AssertTrue('three digits', Pos('{\cf1  100} ', RTF) > 0);
    AssertTrue('four digits', Pos('{\cf1 9999} ', RTF) > 0);
  finally
    P.Free;
  end;
end;

// A backslash introduces a user defined graphic, so a real one in a program is
// doubled. A text file has no graphics to tell it from when typed back in, and
// its backslashes are left alone.
procedure TSinclairBasicTest.TestBackslashIsEscaped;
const
  // 10 REM \A
  Comment: array[0..7] of byte = ($00, $0A, $04, $00, $EA, $5C, $41, $0D);
var
  P: TSinclairBasicParser;
  RTF: string;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    AssertEquals('listing', '  10 REM \\A' + CRLF, P.Decode(Comment));
    AssertTrue('in the viewer', Pos('{\v \\}\\A', P.DecodeRTF(Comment)) > 0);
    AssertEquals('string array', '\\' + CRLF,
      P.DecodeStringArray([$01, $01, $00, $5C]));

    RTF := P.DecodeTextRTF([$41, $5C, $42]);
    AssertTrue('text file', Pos('A\\B', RTF) > 0);
    AssertEquals('nothing hidden in a text file', 0, Pos('\v ', RTF));
  finally
    P.Free;
  end;
end;

// Underlining tens of thousands of graphics takes the text control seconds, so
// very long text shows them as they are written
procedure TSinclairBasicTest.TestLongTextShowsEscapesAsWritten;
var
  P: TSinclairBasicParser;
  Data: array of byte;
  RTF: string;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // A graphic and a backslash, then enough text to pass the limit
    SetLength(Data, 200 * 1024);
    FillChar(Data[0], Length(Data), Ord('x'));
    Data[0] := $90;
    RTF := P.DecodeTextRTF(Data);
    AssertTrue('written out', Pos('\\Axxx', RTF) > 0);
    AssertEquals('nothing hidden', 0, Pos('\v ', RTF));
    AssertEquals('nothing underlined', 0, Pos('\ul ', RTF));

    // The next document is underlined again
    AssertTrue(Pos('{\v \\}{\ul A}', P.DecodeTextRTF([$90])) > 0);
  finally
    P.Free;
  end;
end;

initialization
  RegisterTest(TSinclairBasicTest);
end.
