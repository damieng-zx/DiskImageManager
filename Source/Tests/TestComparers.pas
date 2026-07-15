unit TestComparers;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the Comparers unit.

  Covers value parsing and comparison. CompareItems is excluded because it
  operates on live TListItem/TListView instances.
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Comparers;

type
  TComparersTest = class(TTestCase)
  published
    procedure TestFileBytesPlain;
    procedure TestFileBytesKB;
    procedure TestFileBytesMB;
    procedure TestFileBytesRejectsNoUnit;
    procedure TestFileBytesRejectsUnknownUnit;
    procedure TestFileBytesRejectsNonNumeric;
    procedure TestCompareValuesBySize;
    procedure TestCompareValuesByText;
    procedure TestCompareValuesEqual;
    procedure TestLeadingIntPlain;
    procedure TestLeadingIntSigned;
    procedure TestLeadingIntWithTrailingDetail;
    procedure TestLeadingIntRejectsHex;
    procedure TestLeadingIntRejectsText;
    procedure TestCompareValuesNumerically;
    procedure TestCompareValuesByLeadingNumber;
    procedure TestCompareValuesMixedSizeFormats;
    procedure TestCompareValuesTiesBreakOnText;
    procedure TestCompareValuesHexAsText;
    procedure TestCompareValuesSmallIntegers;
  end;

implementation

procedure TComparersTest.TestFileBytesPlain;
var
  V: integer;
begin
  AssertTrue(TryStrToFileBytes('512 bytes', V));
  AssertEquals(512, V);
end;

procedure TComparersTest.TestFileBytesKB;
var
  V: integer;
begin
  AssertTrue(TryStrToFileBytes('2 KB', V));
  AssertEquals(2048, V);
end;

procedure TComparersTest.TestFileBytesMB;
var
  V: integer;
begin
  AssertTrue(TryStrToFileBytes('3 MB', V));
  AssertEquals(3 * 1024 * 1024, V);
end;

procedure TComparersTest.TestFileBytesRejectsNoUnit;
var
  V: integer;
begin
  // No space separator -> a single token -> not a file-size string
  AssertFalse(TryStrToFileBytes('512bytes', V));
end;

procedure TComparersTest.TestFileBytesRejectsUnknownUnit;
var
  V: integer;
begin
  AssertFalse(TryStrToFileBytes('12 GB', V));
end;

procedure TComparersTest.TestFileBytesRejectsNonNumeric;
var
  V: integer;
begin
  AssertFalse(TryStrToFileBytes('big KB', V));
end;

procedure TComparersTest.TestCompareValuesBySize;
begin
  // 1 KB (1024) vs 512 bytes -> first is larger
  AssertTrue(CompareValues('1 KB', '512 bytes') > 0);
  AssertTrue(CompareValues('512 bytes', '1 KB') < 0);
end;

procedure TComparersTest.TestCompareValuesByText;
begin
  // Falls back to case-insensitive text comparison
  AssertTrue(CompareValues('zebra', 'apple') > 0);
  AssertTrue(CompareValues('apple', 'zebra') < 0);
end;

procedure TComparersTest.TestCompareValuesEqual;
begin
  AssertEquals(0, CompareValues('apple', 'apple'));
  AssertEquals(0, CompareValues('1 KB', '1 KB'));
end;

procedure TComparersTest.TestLeadingIntPlain;
var
  V: int64;
begin
  AssertTrue(TryStrToLeadingInt('512', V));
  AssertEquals(512, V);
end;

procedure TComparersTest.TestLeadingIntSigned;
var
  V: int64;
begin
  // Index point offsets are rendered as '+123'
  AssertTrue(TryStrToLeadingInt('+123', V));
  AssertEquals(123, V);
end;

procedure TComparersTest.TestLeadingIntWithTrailingDetail;
var
  V: int64;
begin
  // FDC size is '2 (512)', FDC flags are '0, 0'
  AssertTrue(TryStrToLeadingInt('2 (512)', V));
  AssertEquals(2, V);
  AssertTrue(TryStrToLeadingInt('10, 0', V));
  AssertEquals(10, V);
end;

procedure TComparersTest.TestLeadingIntRejectsHex;
var
  V: int64;
begin
  // '0A' is a hex filler byte, not the number 0
  AssertFalse(TryStrToLeadingInt('0A', V));
  AssertFalse(TryStrToLeadingInt('9F', V));
end;

procedure TComparersTest.TestLeadingIntRejectsText;
var
  V: int64;
begin
  AssertFalse(TryStrToLeadingInt('FF', V));
  AssertFalse(TryStrToLeadingInt('', V));
  AssertFalse(TryStrToLeadingInt('+', V));
end;

procedure TComparersTest.TestCompareValuesNumerically;
begin
  // Text ordering would put '10' before '2'
  AssertTrue(CompareValues('2', '10') < 0);
  AssertTrue(CompareValues('10', '2') > 0);
  AssertTrue(CompareValues('9', '100') < 0);
end;

procedure TComparersTest.TestCompareValuesByLeadingNumber;
begin
  // FDC size column: '2 (512)' vs '10 (4096)'
  AssertTrue(CompareValues('2 (512)', '10 (4096)') < 0);
  AssertTrue(CompareValues('10 (4096)', '2 (512)') > 0);
end;

procedure TComparersTest.TestCompareValuesMixedSizeFormats;
begin
  // Data size mixes plain '1024' with '256 (512)' when sizes disagree
  AssertTrue(CompareValues('256 (512)', '1024') < 0);
  AssertTrue(CompareValues('1024', '256 (512)') > 0);
end;

procedure TComparersTest.TestCompareValuesTiesBreakOnText;
begin
  // Same leading number falls back to text rather than comparing equal
  AssertTrue(CompareValues('2 (1024)', '2 (512)') <> 0);
  AssertEquals(0, CompareValues('2 (512)', '2 (512)'));
end;

procedure TComparersTest.TestCompareValuesHexAsText;
begin
  // Fixed-width hex sorts correctly as text; it must not be read as decimal
  AssertTrue(CompareValues('0A', '20') < 0);
  AssertTrue(CompareValues('20', '9F') < 0);
  AssertTrue(CompareValues('9F', 'FF') < 0);
end;

procedure TComparersTest.TestCompareValuesSmallIntegers;
begin
  // Integers 1..31 once parsed as dates; they must compare as numbers
  AssertTrue(CompareValues('2', '3') < 0);
  AssertTrue(CompareValues('31', '2') > 0);
end;

initialization
  RegisterTest(TComparersTest);
end.
