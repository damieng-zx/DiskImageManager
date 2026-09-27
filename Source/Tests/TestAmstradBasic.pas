unit TestAmstradBasic;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the Amstrad (Locomotive) BASIC decoder.

  Drives TAmstradBasicParser.Decode directly with hand-built tokenised byte
  streams. Line format on the wire:
    [len lo][len hi][line-number lo][line-number hi][ ...line bytes... $00 ]
  where len covers the whole line including the 4-byte header and terminator.
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, AmstradBasic;

type
  TAmstradBasicTest = class(TTestCase)
  published
    procedure TestPrintString;
    procedure TestEightBitInteger;
    procedure TestHexConstant;
    procedure TestFunctionPrefix;
    procedure TestDigitConstant;
    procedure TestMultipleLines;
    procedure TestProtectedBasic;
    procedure TestSixteenBitBinaryAndHexConstants;
    procedure TestTokenizedVariableName;
    procedure TestFloatingPointSignAndZero;
    procedure TestRemCommentKeepsOnlyPrintableBytes;
    procedure TestRTFEscapesStringPunctuation;
  end;

implementation

const
  CRLF = #13#10;
  tPRINT = $BF;

procedure TAmstradBasicTest.TestPrintString;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // 10 PRINT "HI"  ; len = 11 (4 header + BF 20 22 48 49 22 00)
    AssertEquals('10 PRINT "HI"' + CRLF,
      P.Decode([$0B, $00, $0A, $00, tPRINT, $20, $22, $48, $49, $22, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestEightBitInteger;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // 20 PRINT 65  ; $19 = 8-bit integer prefix, next byte = value
    AssertEquals('20 PRINT 65' + CRLF,
      P.Decode([$09, $00, $14, $00, tPRINT, $20, $19, $41, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestHexConstant;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // 30 PRINT &FF  ; $1C = 16-bit hex prefix (lo, hi)
    AssertEquals('30 PRINT &FF' + CRLF,
      P.Decode([$0A, $00, $1E, $00, tPRINT, $20, $1C, $FF, $00, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestFunctionPrefix;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // 40 PRINT SIN  ; $FF = function prefix, $15 = SIN ; len = 9
    AssertEquals('40 PRINT SIN' + CRLF,
      P.Decode([$09, $00, $28, $00, tPRINT, $20, $FF, $15, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestDigitConstant;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // 50 PRINT 7  ; $0E..$17 encode the single digits 0..9 ($15 = 7)
    AssertEquals('50 PRINT 7' + CRLF,
      P.Decode([$08, $00, $32, $00, tPRINT, $20, $15, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestMultipleLines;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // 10 PRINT "HI" then 20 CLS  (CLS = $8A)
    AssertEquals('10 PRINT "HI"' + CRLF + '20 CLS' + CRLF,
      P.Decode([$0B, $00, $0A, $00, tPRINT, $20, $22, $48, $49, $22, $00,
                $06, $00, $14, $00, $8A, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestProtectedBasic;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // "10 PRINT \"HI\"" encrypted with the AMSDOS 128-byte XOR stream.
    AssertEquals('10 PRINT "HI"' + CRLF,
      P.Decode([$A0, $2C, $E7, $EA, $D3, $17, $1D, $A4, $D2, $FD, $7A], True));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestSixteenBitBinaryAndHexConstants;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    AssertEquals('16-bit, binary and hexadecimal constants',
      '10 PRINT 4660 &X10100101 &1234' + CRLF,
      P.Decode([$12, $00, $0A, $00, tPRINT, $20,
        $1A, $34, $12, $20, $1B, $A5, $00, $20, $1C, $34, $12, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestTokenizedVariableName;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // $02 is an integer variable; bit 7 marks the last character in its name.
    AssertEquals('10 PRINT N%' + CRLF,
      P.Decode([$0B, $00, $0A, $00, tPRINT, $20, $02, $00, $00, $CE, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestFloatingPointSignAndZero;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    // An implicit leading mantissa bit and exponent 128 encode +/-1; exponent
    // zero is the dedicated representation for 0.
    AssertEquals('10 PRINT 0.5' + CRLF + '20 PRINT -0.5' + CRLF + '30 PRINT 0' + CRLF,
      P.Decode([$0D, $00, $0A, $00, tPRINT, $20, $1F, $00, $00, $00, $00, $80, $00,
                $0D, $00, $14, $00, tPRINT, $20, $1F, $00, $00, $00, $80, $80, $00,
                $0D, $00, $1E, $00, tPRINT, $20, $1F, $00, $00, $00, $00, $00, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestRemCommentKeepsOnlyPrintableBytes;
var
  P: TAmstradBasicParser;
begin
  P := TAmstradBasicParser.Create;
  try
    AssertEquals('10 PRINT REMhi' + CRLF,
      P.Decode([$0B, $00, $0A, $00, tPRINT, $20, $C5, $68, $69, $BF, $00]));
  finally
    P.Free;
  end;
end;

procedure TAmstradBasicTest.TestRTFEscapesStringPunctuation;
var
  P: TAmstradBasicParser;
  RTF: string;
begin
  P := TAmstradBasicParser.Create;
  try
    RTF := P.DecodeRTF([$0D, $00, $0A, $00, tPRINT, $20,
      $22, $41, $7B, $42, $7D, $22, $00]);
    AssertTrue('opening brace escaped in RTF', Pos('\{', RTF) > 0);
    AssertTrue('closing brace escaped in RTF', Pos('\}', RTF) > 0);
    AssertTrue('BASIC string uses its syntax color', Pos('\cf3', RTF) > 0);
  finally
    P.Free;
  end;
end;

initialization
  RegisterTest(TAmstradBasicTest);
end.
