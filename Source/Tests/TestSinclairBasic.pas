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
    procedure TestModeDependentToken128K;
    procedure TestModeDependentToken48K;
    procedure TestPoundSign;
    procedure TestMultipleLines;
    procedure TestStringArrayTwoDimensions;
    procedure TestStringArraySingleString;
    procedure TestStringArrayTrimsPadding;
  end;

implementation

const
  CRLF = #13#10;
  // Token codes used in the tests
  tPRINT = $F5;
  tSPECTRUM_PLAY = $A3; // mode dependent: SPECTRUM (128K) / UDG-A (48K)

procedure TSinclairBasicTest.TestPrintString;
var
  P: TSinclairBasicParser;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // 10 PRINT "HI"
    AssertEquals('10 PRINT "HI"' + CRLF,
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
    AssertEquals('30 PRINT 1' + CRLF,
      P.Decode([$00, $1E, $09, $00, tPRINT, $31, $0E, $00, $00, $01, $00, $00, $0D]));
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
    AssertEquals('10 SPECTRUM ' + CRLF,
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
    // The same token decodes to UDG-A in 48K mode
    AssertEquals('10 UDG-A ' + CRLF,
      P.Decode([$00, $0A, $02, $00, tSPECTRUM_PLAY, $0D]));
  finally
    P.Free;
  end;
end;

procedure TSinclairBasicTest.TestPoundSign;
var
  P: TSinclairBasicParser;
  R: string;
begin
  P := TSinclairBasicParser.Create(sbMode128K);
  try
    // Byte $A1 is the pound sign, emitted as UTF-8 (C2 A3)
    R := P.Decode([$00, $0A, $02, $00, $A1, $0D]);
    AssertTrue('result should contain UTF-8 pound sign',
      Pos(#$C2#$A3, R) > 0);
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
    AssertEquals('10 PRINT "HI"' + CRLF + '20 CLS ' + CRLF,
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

initialization
  RegisterTest(TSinclairBasicTest);
end.
