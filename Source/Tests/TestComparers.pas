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

initialization
  RegisterTest(TComparersTest);
end.
