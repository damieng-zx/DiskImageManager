unit OpusFileSystem;

{$MODE Delphi}

{
  Disk Image Manager -  Virtual Opus Discovery file system

  The disk layout, catalogue and file header of the Opus Discovery interface for
  the Spectrum, following dskmanager-rust.

  Sector 0 of the first track is the boot sector: a Z80 jump (18 xx), the tracks
  per side, the sectors per track and a flags byte (bit 4 set for two sides,
  bits 6-7 the sector size as 128 shl n). The file system works in blocks of one
  sector. Block 0 is the sector after the boot sector, and blocks run through
  every track of side 0 and then every track of side 1, whatever order the image
  file keeps the tracks in.

  The catalogue starts at block 0 and holds 16-byte entries: the bytes used in
  the last block less one, the first block, the last block (all little endian)
  and a 10 character name. The first entry names the disk and covers the
  catalogue itself. An entry whose last block is $FFFF ends the list, and its
  first block is the number of blocks on the disk.

  A file is one run of blocks. Files saved from BASIC begin with a 7-byte
  header: type, length and two parameters, as on tape.

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DskImage, DIMUtils,
  Classes, SysUtils, FGL;

const
  // What format detection calls these disks
  OpusFormatName = 'Opus Discovery';
  OpusDirEntrySize = 16;
  OpusNameLength = 10;
  OpusHeaderSize = 7;
  // The disks the interface formats, and the only ones this app makes
  OpusSectorsPerTrack = 18;
  OpusSectorSize = 256;
  OpusCatalogueBlocks = 7;

type
  // Disk geometry, as the boot sector records it
  TOpusGeometry = record
    Tracks: integer;  // per side
    Sides: integer;
    SectorsPerTrack: integer;
    SectorSize: integer;  // which is also the block size
    function TotalSectors: integer;
    function Capacity: integer;
    // Every sector but the boot sector
    function Blocks: integer;
    // The side, track and sector index (from 0) that hold a block
    function BlockLocation(Block: integer; out Side, Track, Index: integer): boolean;
  end;

  // What a file saved from BASIC holds. Data is a file with no header, such as
  // one written with PRINT #.
  TOpusFileType = (oftBasic, oftNumberArray, oftStringArray, oftCode, oftData);

  TOpusFile = class;

  TOpusFileSystem = class(TObject)
  private
    FParentDisk: TDSKDisk;
    FGeometry: TOpusGeometry;
    FFirstSectorID: integer;
    FIsValid: boolean;
    FDiskName: string;
    FCatalogueBlocks: integer;
    FCatalogueLastBytes: integer;
    FTotalBlocks: integer;
    FUsedBlocks: integer;
    // Read the boot sector and the catalogue, forgetting anything read before
    procedure Mount;
    // Walk the entries after the disk's own, adding the files to List when there
    // is one, and note how many blocks the disk has and how many are taken
    procedure ReadCatalogue(List: TFPGList<TOpusFile>);
    function GetFreeBlocks: integer;
  public
    constructor Create(ParentDisk: TDSKDisk);

    // The sector holding a block, or nil when the disk has no whole one there
    function GetBlock(Block: integer): TDSKSector;
    // The files in catalogue order. The caller owns the list and what is in it.
    function Directory: TFPGList<TOpusFile>;

    // Whether there is a boot sector and a catalogue to read
    property IsValid: boolean read FIsValid;
    property Geometry: TOpusGeometry read FGeometry;
    property DiskName: string read FDiskName;
    property CatalogueBlocks: integer read FCatalogueBlocks;
    // Bytes the catalogue's own entry uses of its last block
    property CatalogueLastBytes: integer read FCatalogueLastBytes;
    property TotalBlocks: integer read FTotalBlocks;
    property FreeBlocks: integer read GetFreeBlocks;
  end;

  TOpusFile = class(TDiskFile)
  private
    FParentFileSystem: TOpusFileSystem;
    // The stored bytes, header and all, with zeroes for any block that is missing
    function ReadStored: TDiskByteArray;
    procedure Describe;
  public
    EntryIndex: integer;
    FirstBlock: integer;
    LastBlock: integer;
    LastBlockBytes: integer;
    FileType: TOpusFileType;
    Meta: string;
    // The header's two parameters: autorun line, start address or array name,
    // then the length of a BASIC program without its variables
    Param1, Param2: word;
    // The length of the file's data, not counting any header
    Size: integer;

    function BlockCount: integer;
    function AllocatedSize: integer;
    // Bytes the file takes on the disk, header included
    function StoredSize: integer;
    function HasHeader: boolean; override;
    function GetData(WithHeader: boolean): TDiskByteArray; override;
    // A BASIC program without its variables, or nothing for any other file
    function BasicProgram: TDiskByteArray;

    constructor Create(ParentFileSystem: TOpusFileSystem);
    destructor Destroy; override;
  end;

// The geometry a boot sector describes, if it holds a plausible one
function OpusBootGeometry(const Boot: array of byte; out Geometry: TOpusGeometry): boolean;

// The geometry of an image file of FileSize bytes that starts with Boot: what the
// boot sector says if that fits the file, or else the standard disk of that size
function OpusImageGeometry(const Boot: array of byte; FileSize: int64;
  out Geometry: TOpusGeometry; out FromBoot: boolean): boolean;

// Whether the disk's contents are an Opus Discovery disk. Stricter than reading
// one, because it decides which file system a DSK or Teledisk image is read with.
function IsOpusDisk(Disk: TDSKDisk): boolean;

// Whether a disk of this shape can be given an Opus Discovery file system
function IsOpusFormattable(Formatter: TDSKFormatSpecification): boolean;

// Write the boot sector and an empty catalogue to a freshly formatted disk
procedure WriteOpusFileSystem(Disk: TDSKDisk; CatalogueBlocks: integer = OpusCatalogueBlocks);

implementation

const
  // Limits on what a boot sector can sensibly say
  MaxOpusTracks = 86;
  MaxOpusSectorsPerTrack = 32;

  JumpOpcode = $18;      // the Z80 relative jump that starts a boot sector
  DoubleSidedFlag = $10;
  UnusedFlags = $2F;     // clear in a boot sector written to disk
  EndMarker = $FFFF;     // last block of the entry that ends the catalogue
  ValueMask = $0FFF;     // the first block and last block length use 12 bits
  Filler = $E5;

  // Offsets within a catalogue entry
  deLastBytes = 0;
  deFirstBlock = 2;
  deLastBlock = 4;
  deName = 6;

  NewDiskName: array[0..OpusNameLength - 1] of ansichar = 'Untitled  ';

  // The Z80 routine at offset 7 of a boot sector. When a sector starts 18 05 the
  // interface calls it there to load the geometry, so a boot sector with that
  // start must hold this code.
  GeometryLoader: array[0..23] of byte = (
    $7E,             // ld a,(hl)     tracks
    $DD, $77, $00,   // ld (ix+0),a
    $23,             // inc hl
    $7E,             // ld a,(hl)     sectors per track
    $DD, $77, $01,   // ld (ix+1),a
    $DD, $7E, $02,   // ld a,(ix+2)   the drive's flags
    $E6, $2F,        // and $2f       keep the bits the disk does not set
    $57,             // ld d,a
    $23,             // inc hl
    $7E,             // ld a,(hl)     the disk's flags
    $E6, $D0,        // and $d0       sides and sector size
    $B2,             // or d
    $DD, $77, $02,   // ld (ix+2),a
    $C9              // ret
    );

// Geometry

function TOpusGeometry.TotalSectors: integer;
begin
  Result := Tracks * Sides * SectorsPerTrack;
end;

function TOpusGeometry.Capacity: integer;
begin
  Result := TotalSectors * SectorSize;
end;

function TOpusGeometry.Blocks: integer;
begin
  Result := TotalSectors - 1;
  if Result < 0 then Result := 0;
end;

function TOpusGeometry.BlockLocation(Block: integer; out Side, Track, Index: integer): boolean;
var
  Linear: integer;
begin
  Side := 0;
  Track := 0;
  Index := 0;
  Result := (Block >= 0) and (Block < Blocks);
  if not Result then exit;
  Linear := (Block + 1) div SectorsPerTrack;
  Side := Linear div Tracks;
  Track := Linear mod Tracks;
  Index := (Block + 1) mod SectorsPerTrack;
end;

function OpusBootGeometry(const Boot: array of byte; out Geometry: TOpusGeometry): boolean;
begin
  FillChar(Geometry, SizeOf(Geometry), 0);
  Result := False;
  if Length(Boot) < 5 then exit;
  if (Boot[2] < 1) or (Boot[2] > MaxOpusTracks) or
    (Boot[3] < 1) or (Boot[3] > MaxOpusSectorsPerTrack) then exit;

  Geometry.Tracks := Boot[2];
  Geometry.SectorsPerTrack := Boot[3];
  if (Boot[4] and DoubleSidedFlag) <> 0 then
    Geometry.Sides := 2
  else
    Geometry.Sides := 1;
  Geometry.SectorSize := 128 shl (Boot[4] shr 6);
  Result := True;
end;

function OpusImageGeometry(const Boot: array of byte; FileSize: int64;
  out Geometry: TOpusGeometry; out FromBoot: boolean): boolean;
const
  // 180K, 360K and 720K
  StandardTracks: array[0..2] of integer = (40, 40, 80);
  StandardSides: array[0..2] of integer = (1, 2, 2);
var
  Idx: integer;
begin
  FromBoot := OpusBootGeometry(Boot, Geometry) and (Geometry.Capacity = FileSize);
  if FromBoot then exit(True);

  Geometry.SectorsPerTrack := OpusSectorsPerTrack;
  Geometry.SectorSize := OpusSectorSize;
  for Idx := Low(StandardTracks) to High(StandardTracks) do
  begin
    Geometry.Tracks := StandardTracks[Idx];
    Geometry.Sides := StandardSides[Idx];
    if Geometry.Capacity = FileSize then exit(True);
  end;

  FillChar(Geometry, SizeOf(Geometry), 0);
  Result := False;
end;

// The lowest numbered sector of the first track, or nil if there is none
function BootSector(Disk: TDSKDisk): TDSKSector;
var
  Track: TDSKTrack;
begin
  Result := nil;
  if (Disk.Sides = 0) or (Disk.Side[0].Tracks = 0) then exit;
  Track := Disk.Side[0].Track[0];
  if Track.Sectors = 0 then exit;
  Result := Track.GetLogicalSectorByID(Track.LowSectorID);
end;

function BootSectorGeometry(Sector: TDSKSector; out Geometry: TOpusGeometry): boolean;
var
  Boot: array[0..4] of byte;
begin
  FillChar(Geometry, SizeOf(Geometry), 0);
  if (Sector = nil) or (Sector.DataSize < SizeOf(Boot)) then exit(False);
  Move(Sector.Data, Boot, SizeOf(Boot));
  Result := OpusBootGeometry(Boot, Geometry);
end;

function IsOpusDisk(Disk: TDSKDisk): boolean;
var
  Boot, Sector: TDSKSector;
  Geometry: TOpusGeometry;
  FileSystem: TOpusFileSystem;
begin
  Result := False;
  Boot := BootSector(Disk);
  if not BootSectorGeometry(Boot, Geometry) then exit;
  if (Boot.ID > 1) or (Boot.Data[0] <> JumpOpcode) or
    ((Boot.Data[4] and UnusedFlags) <> 0) then exit;

  if Disk.Side[0].Track[0].Sectors <> Geometry.SectorsPerTrack then exit;
  for Sector in Disk.Side[0].Track[0].Sector do
    if GetFDCSizeBytes(Sector.FDCSize) <> Geometry.SectorSize then exit;

  // The catalogue always fills its last block
  FileSystem := TOpusFileSystem.Create(Disk);
  try
    Result := FileSystem.IsValid and
      (FileSystem.CatalogueLastBytes = Geometry.SectorSize);
  finally
    FileSystem.Free;
  end;
end;

// Formatting

function IsOpusFormattable(Formatter: TDSKFormatSpecification): boolean;
begin
  Result := ((Formatter.TracksPerSide = 40) or (Formatter.TracksPerSide = 80)) and
    (Formatter.SectorsPerTrack = OpusSectorsPerTrack) and
    (Formatter.SectorSize = OpusSectorSize) and (Formatter.FirstSector = 0) and
    (Formatter.DirBlocks > 0);
end;

procedure WriteEntry(var Data: array of byte; Offset, FirstBlock, LastBlock, LastBytes: integer);

  procedure PutWord(At, Value: integer);
  begin
    Data[At] := Value and $FF;
    Data[At + 1] := (Value shr 8) and $FF;
  end;

begin
  PutWord(Offset + deLastBytes, LastBytes - 1);
  PutWord(Offset + deFirstBlock, FirstBlock);
  PutWord(Offset + deLastBlock, LastBlock);
  Move(NewDiskName, Data[Offset + deName], OpusNameLength);
end;

procedure WriteOpusFileSystem(Disk: TDSKDisk; CatalogueBlocks: integer);
var
  Geometry: TOpusGeometry;
  FileSystem: TOpusFileSystem;
  Boot, Sector: TDSKSector;
  Identifier: word;
  Block: integer;
begin
  Boot := BootSector(Disk);
  if Boot = nil then exit;

  Geometry.Tracks := Disk.Side[0].Tracks;
  Geometry.Sides := Disk.Sides;
  Geometry.SectorsPerTrack := Disk.Side[0].Track[0].Sectors;
  Geometry.SectorSize := Boot.DataSize;

  // A jump over the geometry and a number telling disks apart, to the routine
  // the interface calls to load the geometry
  FillChar(Boot.Data, Geometry.SectorSize, $FF);
  Boot.Data[0] := JumpOpcode;
  Boot.Data[1] := $05;
  Boot.Data[2] := Geometry.Tracks;
  Boot.Data[3] := Geometry.SectorsPerTrack;
  Boot.Data[4] := GetFDCSectorSize(Geometry.SectorSize) shl 6;
  if Geometry.Sides = 2 then
    Boot.Data[4] := Boot.Data[4] or DoubleSidedFlag;
  // The ROM stamps each disk with its frame counter; any varying number serves
  Identifier := GetTickCount64 and $FFFF;
  Boot.Data[5] := Lo(Identifier);
  Boot.Data[6] := Hi(Identifier);
  Move(GeometryLoader, Boot.Data[7], SizeOf(GeometryLoader));

  // The catalogue: the disk's own entry covering the catalogue itself, then the
  // end marker holding the number of blocks, and filler after it
  FileSystem := TOpusFileSystem.Create(Disk);
  try
    FileSystem.FGeometry := Geometry;
    FileSystem.FFirstSectorID := Boot.ID;
    for Block := 0 to CatalogueBlocks - 1 do
    begin
      Sector := FileSystem.GetBlock(Block);
      if Sector = nil then continue;
      FillChar(Sector.Data, Geometry.SectorSize, Filler);
      if Block = 0 then
      begin
        WriteEntry(Sector.Data, 0, 0, CatalogueBlocks - 1, Geometry.SectorSize);
        WriteEntry(Sector.Data, OpusDirEntrySize, Geometry.Blocks, EndMarker,
          Geometry.SectorSize);
      end;
    end;
  finally
    FileSystem.Free;
  end;
end;

// File system

// A name as the catalogue stores it, without its trailing padding. The Spectrum
// has a pound sign and a copyright sign where ASCII has other things.
function DecodeName(const Data: array of byte; Offset: integer): string;
var
  Idx, Last: integer;
begin
  Result := '';
  Last := Offset + OpusNameLength - 1;
  while (Last >= Offset) and ((Data[Last] = 32) or (Data[Last] = 0)) do
    Dec(Last);
  for Idx := Offset to Last do
    case Data[Idx] of
      $60: Result := Result + #$C2#$A3;  // pound sign (UTF-8)
      $7F: Result := Result + #$C2#$A9;  // copyright sign (UTF-8)
      $20..$5F, $61..$7E: Result := Result + Chr(Data[Idx]);
      else
        Result := Result + '?';
    end;
end;

// A slot formatted but never used
function IsUnusedSlot(const Data: array of byte; Offset: integer): boolean;
var
  Idx: integer;
  AllZero, AllFiller: boolean;
begin
  AllZero := True;
  AllFiller := True;
  for Idx := Offset + deName to Offset + deName + OpusNameLength - 1 do
  begin
    if Data[Idx] <> 0 then AllZero := False;
    if Data[Idx] <> Filler then AllFiller := False;
  end;
  Result := AllZero or AllFiller;
end;

constructor TOpusFileSystem.Create(ParentDisk: TDSKDisk);
begin
  inherited Create;
  FParentDisk := ParentDisk;
  Mount;
end;

procedure TOpusFileSystem.Mount;
var
  Boot, First: TDSKSector;
  LastBlock: integer;
begin
  FIsValid := False;
  FDiskName := '';
  FCatalogueBlocks := 0;
  FCatalogueLastBytes := 0;
  FTotalBlocks := 0;
  FUsedBlocks := 0;

  Boot := BootSector(FParentDisk);
  if not BootSectorGeometry(Boot, FGeometry) then exit;
  FFirstSectorID := Boot.ID;

  First := GetBlock(0);
  if (First = nil) or IsUnusedSlot(First.Data, 0) then exit;
  LastBlock := ReadWordLE(First.Data, deLastBlock);
  if ((ReadWordLE(First.Data, deFirstBlock) and ValueMask) <> 0) or
    (LastBlock >= FGeometry.Blocks) then exit;

  FDiskName := DecodeName(First.Data, deName);
  FCatalogueBlocks := LastBlock + 1;
  FCatalogueLastBytes := (ReadWordLE(First.Data, deLastBytes) and ValueMask) + 1;
  FIsValid := True;
  ReadCatalogue(nil);
end;

function TOpusFileSystem.GetBlock(Block: integer): TDSKSector;
var
  SideIdx, TrackIdx, Index: integer;
begin
  Result := nil;
  if not FGeometry.BlockLocation(Block, SideIdx, TrackIdx, Index) then exit;
  if (SideIdx >= FParentDisk.Sides) or (TrackIdx >= FParentDisk.Side[SideIdx].Tracks) or
    (FFirstSectorID + Index > High(byte)) then exit;
  Result := FParentDisk.Side[SideIdx].Track[TrackIdx].GetLogicalSectorByID(
    FFirstSectorID + Index);
  if (Result <> nil) and (Result.DataSize < FGeometry.SectorSize) then
    Result := nil;
end;

procedure TOpusFileSystem.ReadCatalogue(List: TFPGList<TOpusFile>);
var
  Block, Slot, Offset, PerBlock, First, Last: integer;
  Sector: TDSKSector;
  DiskFile: TOpusFile;
begin
  FTotalBlocks := FGeometry.Blocks;
  FUsedBlocks := FCatalogueBlocks;
  PerBlock := FGeometry.SectorSize div OpusDirEntrySize;

  for Block := 0 to FCatalogueBlocks - 1 do
  begin
    Sector := GetBlock(Block);
    if Sector = nil then exit;

    for Slot := 0 to PerBlock - 1 do
    begin
      if (Block = 0) and (Slot = 0) then continue;  // the disk's own entry
      Offset := Slot * OpusDirEntrySize;
      if IsUnusedSlot(Sector.Data, Offset) then continue;

      First := ReadWordLE(Sector.Data, Offset + deFirstBlock) and ValueMask;
      Last := ReadWordLE(Sector.Data, Offset + deLastBlock);
      if Last = EndMarker then
      begin
        if (First > 0) and (First <= FGeometry.Blocks) then
          FTotalBlocks := First;
        exit;
      end;
      // An entry whose blocks are not on the disk describes no file
      if (Last < First) or (Last >= FGeometry.Blocks) then continue;

      Inc(FUsedBlocks, Last - First + 1);
      if List = nil then continue;

      DiskFile := TOpusFile.Create(Self);
      DiskFile.FileName := DecodeName(Sector.Data, Offset + deName);
      DiskFile.EntryIndex := Block * PerBlock + Slot;
      DiskFile.FirstBlock := First;
      DiskFile.LastBlock := Last;
      DiskFile.LastBlockBytes :=
        (ReadWordLE(Sector.Data, Offset + deLastBytes) and ValueMask) + 1;
      DiskFile.Describe;
      List.Add(DiskFile);
    end;
  end;
end;

function TOpusFileSystem.Directory: TFPGList<TOpusFile>;
begin
  // The sectors can have been edited since they were last read
  Mount;
  Result := TFPGList<TOpusFile>.Create;
  if FIsValid then
    ReadCatalogue(Result);
end;

function TOpusFileSystem.GetFreeBlocks: integer;
begin
  Result := FTotalBlocks - FUsedBlocks;
  if Result < 0 then Result := 0;
end;

// File

constructor TOpusFile.Create(ParentFileSystem: TOpusFileSystem);
begin
  inherited Create;
  FParentFileSystem := ParentFileSystem;
  FileType := oftData;
end;

destructor TOpusFile.Destroy;
begin
  FParentFileSystem := nil;
  inherited Destroy;
end;

function TOpusFile.BlockCount: integer;
begin
  Result := LastBlock - FirstBlock + 1;
end;

function TOpusFile.AllocatedSize: integer;
begin
  Result := BlockCount * FParentFileSystem.Geometry.SectorSize;
end;

function TOpusFile.StoredSize: integer;
var
  BlockSize, InLast: integer;
begin
  BlockSize := FParentFileSystem.Geometry.SectorSize;
  InLast := LastBlockBytes;
  if InLast > BlockSize then InLast := BlockSize;
  Result := (BlockCount - 1) * BlockSize + InLast;
end;

function TOpusFile.ReadStored: TDiskByteArray;
var
  Block, BlockSize, Target, Count: integer;
  Sector: TDSKSector;
begin
  Result := nil;
  SetLength(Result, StoredSize);  // zeroed, which is what a missing block reads as
  BlockSize := FParentFileSystem.Geometry.SectorSize;
  Target := 0;

  for Block := FirstBlock to LastBlock do
  begin
    Count := Length(Result) - Target;
    if Count <= 0 then break;
    if Count > BlockSize then Count := BlockSize;

    Sector := FParentFileSystem.GetBlock(Block);
    if Sector <> nil then
      Move(Sector.Data, Result[Target], Count);
    Inc(Target, Count);
  end;
end;

// Read the header, if there is one, and say what the file is. A file has a header
// only when the header's length accounts for exactly the rest of the file.
procedure TOpusFile.Describe;
var
  Complete: boolean;
  Variable: char;
  Letter, Block: integer;
begin
  FirstSector := FParentFileSystem.GetBlock(FirstBlock);
  FileType := oftData;
  Size := StoredSize;

  if (FirstSector <> nil) and (Size >= OpusHeaderSize) and
    (FirstSector.Data[0] <= Ord(oftCode)) and
    (ReadWordLE(FirstSector.Data, 1) + OpusHeaderSize = Size) then
  begin
    FileType := TOpusFileType(FirstSector.Data[0]);
    Size := ReadWordLE(FirstSector.Data, 1);
    Param1 := ReadWordLE(FirstSector.Data, 3);
    Param2 := ReadWordLE(FirstSector.Data, 5);
  end;

  Complete := True;
  for Block := FirstBlock to LastBlock do
    if FParentFileSystem.GetBlock(Block) = nil then
    begin
      Complete := False;
      break;
    end;

  // An array's variable letter is in the low five bits of the high byte
  Letter := Hi(Param1) and $1F;
  if (Letter >= 1) and (Letter <= 26) then
    Variable := Chr(Ord('a') + Letter - 1)
  else
    Variable := '?';

  case FileType of
    oftBasic:
      if Param1 < 10000 then
        Meta := Format('BASIC LINE %d', [Param1])
      else
        Meta := 'BASIC';
    oftNumberArray: Meta := Format('DATA %s()', [Variable]);
    oftStringArray: Meta := Format('DATA %s$()', [Variable]);
    oftCode: Meta := Format('CODE %d,%d', [Param1, Size]);
    else
      Meta := 'Data';
  end;
  if not Complete then
    Meta := Meta + ' (incomplete)';
end;

function TOpusFile.HasHeader: boolean;
begin
  Result := FileType <> oftData;
end;

function TOpusFile.GetData(WithHeader: boolean): TDiskByteArray;
begin
  Result := ReadStored;
  if (not WithHeader) and HasHeader then
    Result := Copy(Result, OpusHeaderSize, Length(Result) - OpusHeaderSize);
end;

function TOpusFile.BasicProgram: TDiskByteArray;
var
  Count: integer;
begin
  Result := nil;
  if FileType <> oftBasic then exit;
  Count := Param2;
  if Count > Size then Count := Size;
  Result := Copy(GetData(False), 0, Count);
end;

end.
