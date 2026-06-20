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

initialization
  RegisterTest(TAmstradBasicTest);
end.
