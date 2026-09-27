unit NavigationHistory;

{$MODE Delphi}

{
  Disk Image Manager - persisted navigation location descriptors

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

type
  // Stores a tree location by image path and child indices rather than node
  // pointers, so history survives images closing and application restarts.
  TNavLocation = class
  public
    ImageFile: string;
    NodePath: array of integer;
    ListRow: integer;
    function Serialize: string;
    class function Deserialize(const Text: string): TNavLocation;
  end;

implementation

uses
  SysUtils;

// Serialize as "ImageFile|i0.i1.i2|ListRow" ('|' can't appear in a Windows path).
function TNavLocation.Serialize: string;
var
  PathStr: string;
  Idx: integer;
begin
  PathStr := '';
  for Idx := 0 to High(NodePath) do
  begin
    if PathStr <> '' then PathStr := PathStr + '.';
    PathStr := PathStr + IntToStr(NodePath[Idx]);
  end;
  Result := ImageFile + '|' + PathStr + '|' + IntToStr(ListRow);
end;

class function TNavLocation.Deserialize(const Text: string): TNavLocation;
var
  Parts, PathParts: TStringArray;
  Idx: integer;
begin
  Result := nil;
  Parts := Text.Split(['|']);
  if Length(Parts) <> 3 then Exit;

  Result := TNavLocation.Create;
  Result.ImageFile := Parts[0];
  Result.ListRow := StrToIntDef(Parts[2], -1);
  if Parts[1] <> '' then
  begin
    PathParts := Parts[1].Split(['.']);
    SetLength(Result.NodePath, Length(PathParts));
    for Idx := 0 to High(PathParts) do
      Result.NodePath[Idx] := StrToIntDef(PathParts[Idx], 0);
  end;
end;

end.
