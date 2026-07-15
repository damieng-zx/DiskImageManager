unit MGTFileSystem;

{$MODE Delphi}

{
  Disk Image Manager -  Virtual MGT file system

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DSKImage, Utils,
  Classes, SysUtils, FGL;

type
  TMGTFile = class;

  TMGTFileSystem = class(TObject)
  private
    FParentDisk: TDSKDisk;
  public
    DiskLabel: string;

    function ReadFileEntry(Data: array of byte; Offset: integer): TMGTFile;
    function Directory: TFPGList<TMGTFile>;

    constructor Create(ParentDisk: TDSKDisk);
    destructor Destroy; override;
  end;

  TMGTFile = class(TObject)
  private
    FParentFileSystem: TMGTFileSystem;
  public
    Blocks: TFPGList<integer>;
    FileName: string;
    Meta: string;
    SectorsAllocated: integer;
    AllocatedSize: integer;

    FirstSector: TDSKSector;

    constructor Create(ParentFileSystem: TMGTFileSystem);
    destructor Destroy; override;
  end;

implementation

constructor TMGTFileSystem.Create(ParentDisk: TDSKDisk);
begin
  inherited Create;
  FParentDisk := ParentDisk;
end;

destructor TMGTFileSystem.Destroy;
begin
  FParentDisk := nil;
  inherited Destroy;
end;

function TMGTFileSystem.Directory: TFPGList<TMGTFile>;
const
  DIR_ENTRY_SIZE: integer = 256;
var
  MaxEntries, SectorOffset: integer;
  Sector: TDSKSector;
  Index: integer;
  DiskFile: TMGTFile;
begin
  MaxEntries := 80;

  Result := TFPGList<TMGTFile>.Create;

  Sector := FParentDisk.GetFirstSector();
  if Sector = nil then exit;

  SectorOffset := 0;
  for Index := 0 to MaxEntries - 1 do
  begin
    // Move to next sector if out of data
    if (SectorOffset + DIR_ENTRY_SIZE > Sector.GetCopySize) then
    begin
      Sector := FParentDisk.GetNextLogicalSector(Sector);
      SectorOffset := 0;
    end;

    DiskFile := ReadFileEntry(Sector.Data, SectorOffset);
    if (DiskFile <> nil) and (DiskFile.FileName <> '') and (DiskFile.SectorsAllocated > 0) then
       Result.Add(DiskFile)
    else
       DiskFile.Free;

    SectorOffset := SectorOffset + DIR_ENTRY_SIZE;
  end;
end;

function TMGTFileSystem.ReadFileEntry(Data: array of byte; Offset: integer): TMGTFile;
var
  Track: TDSKTrack;
begin
  Track := FParentDisk.GetLogicalTrack(Data[13]);
  if Track = nil then
  begin
    Result := nil;
    exit;
  end;

  Result := TMGTFile.Create(self);
  with Result do
  begin
    FileName := StrBlockClean(Data, Offset + 1, 10).TrimRight();
    if FileName = '' then exit;

    case Data[0] and 63 of
      0: Meta := 'Erased';
      1: Meta := 'BASIC';
      2: Meta := 'Numeric array';
      3: Meta := 'String array';
      4: Meta := 'CODE';
      5: Meta := 'Snapshot (48K)';
      6: Meta := 'Microdrive';
      7: Meta := 'SCREEN';
      8: Meta := 'Special';
      9: Meta := 'Snapshot (128K)';
      10: Meta := 'Opentype';
      11: Meta := 'ZX execute';
      12: Meta := 'UNI-DOS subdirectory';
      13: Meta := 'UNI-DOS create';
      16: Meta := 'SAM BASIC';
      17: Meta := 'SAM numeric array';
      18: Meta := 'SAM string array';
      19: Meta := 'SAM CODE';
      20: Meta := 'SAM SCREEN';
      21: Meta := 'MasterDOS subdirectory';
      22: Meta := 'SAM Driver application';
      23: Meta := 'SAM Driver bootstrap';
      24: Meta := 'EDOS NOMEN';
      25: Meta := 'EDOS system';
      26: Meta := 'EDOS overlay';
      28: Meta := 'HDOS Hdos';
      29: Meta := 'HDOS Hdir';
      30: Meta := 'HDOS Hdisk';
      31: Meta := 'HDOS Hfree/Htmp';
      else
        Meta := Format('Custom 0x%x', [Data[0] and 63]);
    end;

    if Data[0] and 64 <> 0 then  Meta := Meta + ' (protected)';
    if Data[0] and 128 <> 0 then Meta := Meta + ' (hidden)';

    SectorsAllocated := Data[11] * 256 + Data[12];
    AllocatedSize := SectorsAllocated * FParentDisk.GetFirstSector().AdvertisedSize;

    FirstSector := Track.GetLogicalSectorByID(Data[14]);
  end;
end;

constructor TMGTFile.Create(ParentFileSystem: TMGTFileSystem);
begin
  inherited Create;
  FParentFileSystem := ParentFileSystem;
  Blocks := TFPGList<integer>.Create;
end;

destructor TMGTFile.Destroy;
begin
  FParentFileSystem := nil;
  Blocks.Free;
  inherited Destroy;
end;

end.
