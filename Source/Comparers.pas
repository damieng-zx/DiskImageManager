unit Comparers;

{$mode Delphi}

interface

uses
  Classes, SysUtils, ComCtrls;

function CompareItems(Item1, Item2: TListItem; ListView: TListView): integer;
function CompareValues(Value1, Value2: string): integer;
function TryStrToFileBytes(const S: ansistring; out Value: integer): boolean;
function TryStrToLeadingInt(const S: ansistring; out Value: int64): boolean;

implementation

function CompareItems(Item1, Item2: TListItem; ListView: TListView): integer;
var
  Column: integer;
  Value1, Value2: string;
begin
  if ListView.SortColumn <= 0 then
  begin
    Value1 := Item1.Caption;
    Value2 := Item2.Caption;
  end
  else
  begin
    Column := ListView.SortColumn - 1;
    if Column < Item1.SubItems.Count then
      Value1 := Item1.SubItems[Column]
    else
      Value1 := '';
    if Column < Item2.SubItems.Count then
      Value2 := Item2.SubItems[Column]
    else
      Value2 := '';
  end;
  Result := CompareValues(Value1, Value2);

  if ListView.SortDirection = sdDescending then Result := -Result;
end;

// Compare two column values, sorting them as numbers whenever both are numeric
// and falling back to text otherwise. Only when both sides parse do we sort
// numerically, so a column of fixed-width hex ('0A', '20', 'FF') stays on the
// text path where its ordering is already correct.
function CompareValues(Value1, Value2: string): integer;
var
  Num1, Num2: int64;
  Size1, Size2: integer;
begin
  if TryStrToFileBytes(Value1, Size1) and TryStrToFileBytes(Value2, Size2) then
  begin
    if Size1 < Size2 then exit(-1);
    if Size1 > Size2 then exit(1);
    exit(0);
  end;

  if TryStrToLeadingInt(Value1, Num1) and TryStrToLeadingInt(Value2, Num2) then
  begin
    if Num1 < Num2 then exit(-1);
    if Num1 > Num2 then exit(1);
    // Equal leading numbers ('2 (512)' vs '2 (1024)') settle on the text below
  end;

  Result := CompareText(Value1, Value2);
end;

// Parse the number a value starts with, ignoring any trailing detail, so that
// '512', '+42', '2 (512)' and '0, 0' all sort numerically. Digits butted up
// against a letter are part of a wider token ('0A' is hex, not 10) and are
// rejected so such columns fall back to text.
function TryStrToLeadingInt(const S: ansistring; out Value: int64): boolean;
var
  First, Last: integer;
begin
  Result := False;

  First := 1;
  if (First <= Length(S)) and (S[First] in ['+', '-']) then Inc(First);

  Last := First;
  while (Last <= Length(S)) and (S[Last] in ['0'..'9']) do Inc(Last);

  if Last = First then exit;
  if (Last <= Length(S)) and (S[Last] in ['A'..'Z', 'a'..'z']) then exit;

  Result := TryStrToInt64(Copy(S, 1, Last - 1), Value);
end;

function TryStrToFileBytes(const S: ansistring; out Value: integer): boolean;
var
  Parts: array of string;
  NumValue, Multiplier, BytesValue: int64;
begin
  Result := False;
  Parts := S.Split(' ');
  if High(Parts) = 1 then
  begin
    if Parts[1] = 'bytes' then Multiplier := 1
    else if Parts[1] = 'KB' then Multiplier := 1024
    else if Parts[1] = 'MB' then Multiplier := 1024 * 1024
    else exit;
    if not TryStrToInt64(Parts[0], NumValue) then exit;
    if (NumValue > 0) and (NumValue > High(Int64) div Multiplier) then exit;
    if (NumValue < 0) and (NumValue < Low(Int64) div Multiplier) then exit;
    BytesValue := NumValue * Multiplier;
    if (BytesValue < Low(integer)) or (BytesValue > High(integer)) then exit;
    Value := integer(BytesValue);
    Result := True;
  end;
end;

end.
