unit TestDIMUtils;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the Utils unit.

  Covers the pure string / byte / size helper functions. The LCL-dependent
  drawing and list-view helpers are exercised only indirectly (they need a
  widgetset) and are out of scope here.

  NOTE: deliberately NOT named "TestUtils" - fcl-fpcunit ships a unit called
  "testutils" and Pascal unit names are case-insensitive, so that name would
  collide and corrupt fpcunit dependency resolution.
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Utils;

type
  TUtilsTest = class(TTestCase)
  published
    procedure TestStrInt;
    procedure TestStrHex;
    procedure TestIntStr;
    procedure TestStrBlockClean;
    procedure TestStrYesNo;
    procedure TestBlockShiftToBlockSize;
    procedure TestStrFileSize;
    procedure TestStrBufPos;
    procedure TestStrInByteArray;
    procedure TestCompareBlock;
    procedure TestCompareBlockInsensitive;
    procedure TestCompareBlockStart;
    procedure TestCompareByLength;
  end;

implementation

procedure TUtilsTest.TestStrInt;
begin
  AssertEquals('5', StrInt(5));
  AssertEquals('0', StrInt(0));
  AssertEquals('-3', StrInt(-3));
  AssertEquals('65536', StrInt(65536));
end;

procedure TUtilsTest.TestStrHex;
begin
  AssertEquals('FF', StrHex(255));
  AssertEquals('0A', StrHex(10));
  AssertEquals('00', StrHex(0));
  // Values needing more than two digits are not truncated
  AssertEquals('100', StrHex(256));
end;

procedure TUtilsTest.TestIntStr;
begin
  AssertEquals(42, IntStr('42'));
  AssertEquals(-7, IntStr('-7'));
  // Non-numeric input falls back to zero
  AssertEquals(0, IntStr('abc'));
  AssertEquals(0, IntStr(''));
end;

procedure TUtilsTest.TestStrBlockClean;
begin
  // Plain ASCII passes through
  AssertEquals('HI', StrBlockClean([72, 73], 0, 2));
  // Control characters (<= 31) are dropped
  AssertEquals('HI', StrBlockClean([72, 5, 73], 0, 3));
  // High-bit-set bytes are masked down into the 7-bit range (200 -> 72 = 'H')
  AssertEquals('H', StrBlockClean([200], 0, 1));
  // Start offset is honoured
  AssertEquals('I', StrBlockClean([72, 73], 1, 1));
end;

procedure TUtilsTest.TestStrYesNo;
begin
  AssertEquals('Yes', StrYesNo(True));
  AssertEquals('No', StrYesNo(False));
end;

procedure TUtilsTest.TestBlockShiftToBlockSize;
begin
  // 2 << (BlockShift + 6)
  AssertEquals(128, BlockShiftToBlockSize(0));
  AssertEquals(1024, BlockShiftToBlockSize(3));
  AssertEquals(2048, BlockShiftToBlockSize(4));
end;

procedure TUtilsTest.TestStrFileSize;
begin
  AssertEquals('512 bytes', StrFileSize(512));
  AssertEquals('1023 bytes', StrFileSize(1023));
  AssertEquals('1 KB', StrFileSize(1024));
  AssertEquals('2 KB', StrFileSize(2048));
  AssertEquals('1 MB', StrFileSize(1024 * 1024));
end;

procedure TUtilsTest.TestStrBufPos;
begin
  // 'HELLO' = 72 69 76 76 79
  AssertEquals(2, StrBufPos([72, 69, 76, 76, 79], 'LL'));
  AssertEquals(0, StrBufPos([72, 69, 76, 76, 79], 'HE'));
  AssertEquals(-1, StrBufPos([72, 69, 76, 76, 79], 'XY'));
end;

procedure TUtilsTest.TestStrInByteArray;
begin
  // 'HELLO WORLD' starting at 0
  AssertTrue(StrInByteArray([72, 69, 76, 76, 79, 32, 87, 79, 82, 76, 68], 'HELL', 0));
  AssertFalse(StrInByteArray([72, 69, 76, 76, 79, 32, 87, 79, 82, 76, 68], 'XELL', 0));
end;

procedure TUtilsTest.TestCompareBlock;
begin
  // Matches the leading characters (the final char of B is not compared)
  AssertTrue(CompareBlock(['M', 'V', ' ', '-'], 'MV '));
  AssertFalse(CompareBlock(['X', 'V'], 'MV'));
end;

procedure TUtilsTest.TestCompareBlockInsensitive;
begin
  AssertTrue(CompareBlockInsensitive(['h', 'i'], 'HI'));
  AssertTrue(CompareBlockInsensitive(['H', 'I'], 'hi'));
  AssertFalse(CompareBlockInsensitive(['x', 'i'], 'HI'));
end;

procedure TUtilsTest.TestCompareBlockStart;
begin
  // Compare starting at offset 2 within the char array
  AssertTrue(CompareBlockStart(['x', 'y', 'M', 'V'], 'MV', 2));
  AssertFalse(CompareBlockStart(['x', 'y', 'Z', 'V'], 'MV', 2));
end;

procedure TUtilsTest.TestCompareByLength;
var
  List: TStringList;
begin
  List := TStringList.Create;
  try
    List.Add('short');     // index 0, len 5
    List.Add('a-longer');  // index 1, len 8
    // Longest first -> longer string should sort before shorter (negative)
    AssertTrue('longer should precede shorter', CompareByLength(List, 1, 0) < 0);
    AssertTrue('shorter should follow longer', CompareByLength(List, 0, 1) > 0);
    // Equal length falls back to alphabetical
    List.Clear;
    List.Add('bbb');
    List.Add('aaa');
    AssertTrue('alphabetical tie-break', CompareByLength(List, 0, 1) > 0);
  finally
    List.Free;
  end;
end;

initialization
  RegisterTest(TUtilsTest);
end.
