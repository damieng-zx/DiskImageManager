unit TestNavigationHistory;

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, NavigationHistory;

type
  TNavigationHistoryTest = class(TTestCase)
  published
    procedure TestSerializeAndDeserializeLocation;
    procedure TestDeserializeRejectsWrongFieldCount;
    procedure TestDeserializeDefaultsMalformedNumbers;
  end;

implementation

procedure TNavigationHistoryTest.TestSerializeAndDeserializeLocation;
var
  Original, Restored: TNavLocation;
begin
  Original := TNavLocation.Create;
  try
    Original.ImageFile := 'C:\images\disk.dsk';
    SetLength(Original.NodePath, 3);
    Original.NodePath[0] := 2;
    Original.NodePath[1] := 0;
    Original.NodePath[2] := 15;
    Original.ListRow := 7;
    AssertEquals('C:\images\disk.dsk|2.0.15|7', Original.Serialize);

    Restored := TNavLocation.Deserialize(Original.Serialize);
    try
      AssertNotNull(Restored);
      AssertEquals(Original.ImageFile, Restored.ImageFile);
      AssertEquals(Original.ListRow, Restored.ListRow);
      AssertEquals(Length(Original.NodePath), Length(Restored.NodePath));
      AssertEquals(Original.NodePath[0], Restored.NodePath[0]);
      AssertEquals(Original.NodePath[1], Restored.NodePath[1]);
      AssertEquals(Original.NodePath[2], Restored.NodePath[2]);
    finally
      Restored.Free;
    end;
  finally
    Original.Free;
  end;
end;

procedure TNavigationHistoryTest.TestDeserializeRejectsWrongFieldCount;
begin
  AssertNull(TNavLocation.Deserialize('disk.dsk|0.1'));
end;

procedure TNavigationHistoryTest.TestDeserializeDefaultsMalformedNumbers;
var
  Location: TNavLocation;
begin
  Location := TNavLocation.Deserialize('disk.dsk|bad.2|bad');
  try
    AssertNotNull(Location);
    AssertEquals(-1, Location.ListRow);
    AssertEquals(0, Location.NodePath[0]);
    AssertEquals(2, Location.NodePath[1]);
  finally
    Location.Free;
  end;
end;

initialization
  RegisterTest(TNavigationHistoryTest);
end.
