unit FileSystem;

{$MODE Delphi}

{
  Disk Image Manager -  Virtual CP/M (+3/PCW/CPC) file system

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
  TCPMFile = class;

  TCPMFileSystem = class(TObject)
  private
    FParentDisk: TDSKDisk;
    FEntryAllocationSize: TDSKAllocationSize;

    procedure TryPlus3DOSHeader(Data: array of byte; DiskFile: TCPMFile);
    procedure TryAMSDOSHeader(Data: array of byte; DiskFile: TCPMFile);
  public
    DiskLabel: string;

    property EntryAllocationSize: TDSKAllocationSize read FEntryAllocationSize;

    function ReadLabelEntry(Data: array of byte; Offset: integer): string;
    function ReadFileEntry(Data: array of byte; Offset: integer): TCPMFile;
    function Directory: TFPGList<TCPMFile>;

    constructor Create(ParentDisk: TDSKDisk);
    destructor Destroy; override;
  end;

  TCPMFile = class(TObject)
  private
    FParentFileSystem: TCPMFileSystem;
  public
    Blocks: TFPGList<integer>;
    FileName: string;
    SizeOnDisk: integer;
    User: byte;
    ReadOnly: boolean;
    System: boolean;
    Archived: boolean;
    FirstSector: TDSKSector;
    EntryIndex: integer;
    Extent: integer;

    HeaderType: string;
    Checksum: boolean;
    Size: integer;
    HeaderSize: integer;
    Meta: string;

    function GetData(WithHeader: boolean): TDiskByteArray;

    constructor Create(ParentFileSystem: TCPMFileSystem);
    destructor Destroy; override;
  end;


implementation

// File system

constructor TCPMFileSystem.Create(ParentDisk: TDSKDisk);
begin
  inherited Create;
  FParentDisk := ParentDisk;
end;

destructor TCPMFileSystem.Destroy;
begin
  FParentDisk := nil;
  inherited Destroy;
end;

const
  FILENAME_OFFSET: integer = 1;
  EXTENSION_OFFSET: integer = 9;
  READONLY_OFFSET: integer = 9;
  SYSTEM_OFFSET: integer = 10;
  ARCHIVED_OFFSET: integer = 11;
  EXTENT_LOW: integer = 12;
  BYTES_IN_LAST_RECORD_OFFSET: integer = 13;
  RECORD_COUNT_OFFSET: integer = 15;
  ALLOCATION_OFFSET: integer = 16;

function CompareByExtent(const Item1, Item2: TCPMFile): integer;
begin
  Result := Item1.Extent - Item2.Extent;
end;

function TCPMFileSystem.Directory: TFPGList<TCPMFile>;
const
  DIR_ENTRY_SIZE: integer = 32;
var
  MaxEntries, SectorOffset: integer;
  Sector: TDSKSector;
  Track: TDSKTrack;
  Spec: TDSKSpecification;
  Index: integer;
  Extents: TFPGList<TCPMFile>;
  PrimaryDiskFile, ExtentEntry, DiskFile: TCPMFile;
begin
  Spec := FParentDisk.Specification;
  // Directory entries = directory blocks * block size / 32 bytes per entry.
  // For CPC Data and System this is 2 * 1024 / 32 = 64, matching AMSDOS.
  MaxEntries := Spec.DirectoryBlocks * Spec.GetBlockSize() div DIR_ENTRY_SIZE;

  Result := TFPGList<TCPMFile>.Create;

  Track := FParentDisk.GetLogicalTrack(Spec.ReservedTracks);
  if Track = nil then exit;
  Sector := Track.GetFirstLogicalSector();
  if Sector = nil then exit;

  Extents := TFPGList<TCPMFile>.Create;

  SectorOffset := 0;
  for Index := 0 to MaxEntries - 1 do
  begin
    // Move to next sector if out of data
    if (SectorOffset + DIR_ENTRY_SIZE > Sector.GetCopySize) then
    begin
      Sector := FParentDisk.GetNextLogicalSector(Sector);
      if Sector = nil then break;
      SectorOffset := 0;
    end;

    if Sector.Data[SectorOffset] < 32 then
    begin
      DiskFile := ReadFileEntry(Sector.Data, SectorOffset);
      DiskFile.EntryIndex := Index;
      if (DiskFile.FileName <> '') and (DiskFile.Blocks.Count > 0) then
      begin
        if DiskFile.Extent = 0 then
          Result.Add(DiskFile)
        else
          Extents.Add(DiskFile);
      end
      else
        DiskFile.Free;
    end;

    if Sector.Data[SectorOffset] = 32 then
      DiskLabel := ReadLabelEntry(Sector.Data, SectorOffset);

    SectorOffset := SectorOffset + DIR_ENTRY_SIZE;
  end;

  Extents.Sort(CompareByExtent);

  while Extents.Count > 0 do
  begin
    ExtentEntry := Extents.First;
    Extents.Remove(ExtentEntry);
    for PrimaryDiskFile in Result do
    begin
      // The name alone does not say which file an extent belongs to: the same
      // name under another user number is another file, and matching on the
      // name only handed one user's extents to whoever held the name first
      if (PrimaryDiskFile.User = ExtentEntry.User) and
        (PrimaryDiskFile.FileName = ExtentEntry.FileName) then
      begin
        PrimaryDiskFile.Blocks.AddList(ExtentEntry.Blocks);
        PrimaryDiskFile.SizeOnDisk := PrimaryDiskFile.SizeOnDisk + ExtentEntry.SizeOnDisk;
        PrimaryDiskFile.Size := PrimaryDiskFile.Size + ExtentEntry.Size;
        break;
      end;
    end;
    ExtentEntry.Free;
  end;

  Extents.Free;
end;

function TCPMFileSystem.ReadLabelEntry(Data: array of byte; Offset: integer): string;
begin
  Result := StrBlockClean(Data, Offset + FILENAME_OFFSET, 11);
end;

function TCPMFileSystem.ReadFileEntry(Data: array of byte; Offset: integer): TCPMFile;
var
  Extension: string;
  AllocBlock, AllocOffset: integer;
  Spec: TDSKSpecification;
begin
  Result := TCPMFile.Create(self);
  Spec := FParentDisk.Specification;

  with Result do
  begin
    User := Data[Offset];
    FileName := StrBlockClean(Data, Offset + FILENAME_OFFSET, 8).TrimRight();
    Extension := StrBlockClean(Data, Offset + EXTENSION_OFFSET, 3).TrimRight();
    if FileName = '' then exit;
    if Extension <> '' then
      FileName := FileName + '.' + Extension;

    ReadOnly := Data[Offset + READONLY_OFFSET] > 127;
    System := Data[Offset + SYSTEM_OFFSET] > 127;
    Archived := Data[Offset + ARCHIVED_OFFSET] > 127;
    HeaderSize := 0;

    Extent := Data[Offset + EXTENT_LOW];
    AllocOffset := Offset + ALLOCATION_OFFSET;
    repeat
      begin
        if Spec.AllocationSize = asByte then
        begin
          AllocBlock := Data[AllocOffset];
          AllocOffset := AllocOffset + 1;
        end
        else
        begin
          AllocBlock := ReadWordLE(Data, AllocOffset);
          AllocOffset := AllocOffset + 2;
        end;
        if AllocBlock > 0 then
          Result.Blocks.Add(AllocBlock);
      end;
    until (AllocBlock = 0) or (AllocOffset = Offset + 32);

    SizeOnDisk := Blocks.Count * Spec.GetBlockSize();
    Size := Data[Offset + RECORD_COUNT_OFFSET] * 128;
    if Data[Offset + BYTES_IN_LAST_RECORD_OFFSET] > 0 then
      Size := Size - 128 + Data[Offset + BYTES_IN_LAST_RECORD_OFFSET];

    if Blocks.Count > 0 then
    begin
      HeaderType := 'None';
      FirstSector := FParentDisk.GetSectorByBlock(Blocks[0]);
      if FirstSector <> nil then
      begin
        TryPlus3DOSHeader(FirstSector.Data, Result);
        TryAMSDOSHeader(FirstSector.Data, Result);
      end;
    end;
  end;
end;

procedure TCPMFileSystem.TryAMSDOSHeader(Data: array of byte; DiskFile: TCPMFile);
var
  CalcCheckSum: word;
  Idx: integer;
  ExecAddr, LoadAddr: word;
begin
  CalcChecksum := 0;
  for Idx := 0 to 66 do
    CalcChecksum := CalcChecksum + Data[Idx];
  if CalcCheckSum <> ReadWordLE(Data, 67) then exit;

  DiskFile.Checksum := True;
  DiskFile.HeaderType := 'AMSDOS';
  DiskFile.Size := Read24LE(Data, 64);
  DiskFile.HeaderSize := 128;

  LoadAddr := ReadWordLE(Data, 21);
  ExecAddr := ReadWordLE(Data, 26);

  case Data[18] of
    0: DiskFile.Meta := 'BASIC';
    1: DiskFile.Meta := 'BASIC (protected)';
    2: DiskFile.Meta := Format('BINARY &%s EXEC &%s', [IntToHex(LoadAddr, 4), IntToHex(ExecAddr, 4)]);
    3: DiskFile.Meta := Format('BINARY (protected) &%s EXEC &%s', [IntToHex(LoadAddr, 4), IntToHex(ExecAddr, 4)]);
    4: DiskFile.Meta := 'SCREEN';
    5: DiskFile.Meta := 'SCREEN (protected)';
    6: DiskFile.Meta := 'ASCII';
    7: DiskFile.Meta := 'ASCII (protected)';
    else
      DiskFile.Meta := Format('Custom 0x%x', [Data[18]]);
  end;

  // Screens are normally saved as a plain binary loading at &C000, not as the
  // (rarely used) SCREEN type, so flag the likely ones for the file list.
  if ((Data[18] = 2) or (Data[18] = 3)) and (LoadAddr = $C000) and
     (DiskFile.Size = 16384) then
    DiskFile.Meta := DiskFile.Meta + ' (screen)';

end;

procedure TCPMFileSystem.TryPlus3DOSHeader(Data: array of byte; DiskFile: TCPMFile);
var
  Sig: string;
  CalcChecksum: byte;
  Idx: integer;
  Param1: word;
begin
  Sig := StrBlockClean(Data, 0, 8);
  if Sig <> 'PLUS3DOS' then exit;

  CalcChecksum := 0;
  for Idx := 0 to 126 do
    CalcChecksum := CalcChecksum + Data[Idx];

  DiskFile.Checksum := CalcChecksum = Data[127];
  DiskFile.HeaderType := Sig;
  DiskFile.Size := Read32LE(Data, 11);
  DiskFile.HeaderSize := 128;

  Param1 := ReadWordLE(Data, 18);

  case Data[15] of
    0: begin
      if Param1 <> $8000 then
        DiskFile.Meta := Format('BASIC LINE %d', [Param1])
      else
        DiskFile.Meta := 'BASIC';
    end;
    1: DiskFile.Meta := Format('DATA %s(%d)', [char(Data[19] - 64), ReadWordLE(Data, 129)]);
    2: DiskFile.Meta := Format('DATA %s$(%d)', [char(Data[19] - 128), ReadWordLE(Data, 129)]);
    3: DiskFile.Meta := Format('CODE %d,%d', [Param1,  ReadWordLE(Data, 16)]);
    else
      DiskFile.Meta := Format('Custom 0x%x', [Data[15]]);
  end;
end;

// File

constructor TCPMFile.Create(ParentFileSystem: TCPMFileSystem);
begin
  inherited Create;
  FParentFileSystem := ParentFileSystem;
  Blocks := TFPGList<integer>.Create;
end;

destructor TCPMFile.Destroy;
begin
  FParentFileSystem := nil;
  Blocks.Free;
  inherited Destroy;
end;

function TCPMFile.GetData(WithHeader: boolean): TDiskByteArray;
var
  Block, BytesLeft, TargetIdx, BlockSize, SectorsLeft, SectorsPerBlock: integer;
  TotalSize: integer;
  Disk: TDSKDisk;
  Sector: TDSKSector;
  FileData: TDiskByteArray;
begin
  FileData := nil;

  // PLUS3DOS records the whole file length (its 128-byte header included) in
  // Size, whereas AMSDOS and headerless files record only the payload. Derive
  // the true on-disk length so we neither over-read past the file nor treat the
  // trailing header-sized run of bytes as content.
  if HeaderType = 'PLUS3DOS' then
    TotalSize := Size
  else
    TotalSize := Size + HeaderSize;

  SetLength(FileData, TotalSize);

  BytesLeft := TotalSize;
  TargetIdx := 0;
  Disk := FParentFileSystem.FParentDisk;
  BlockSize := Disk.Specification.GetBlockSize();
  SectorsPerBlock := BlockSize div Disk.Specification.SectorSize;

  // Extract the full data out
  for Block in Blocks do
  begin
    Sector := Disk.GetSectorByBlock(Block);
    if Sector = nil then break;
    SectorsLeft := SectorsPerBlock;
    repeat
      begin
        // Final (possibly partial) sector
        if (BytesLeft < Sector.GetCopySize) then
        begin
          Move(Sector.Data, FileData[TargetIdx], BytesLeft);
          SectorsLeft := 0;
        end
        else
        begin
          // Full sector
          Move(Sector.Data, FileData[TargetIdx], Sector.GetCopySize);
          BytesLeft := BytesLeft - Sector.GetCopySize;
          TargetIdx := TargetIdx + Sector.GetCopySize;
          Sector := Disk.GetNextLogicalSector(Sector);
          Dec(SectorsLeft);
        end;
      end
    until (SectorsLeft = 0) or (Sector = nil);
    // A block can run past the last sector of a truncated image, leaving the
    // rest of FileData as the zeroes SetLength gave it rather than crashing
    if Sector = nil then break;
  end;

  // Strip any header: the headerless copy takes the payload that follows the
  // header, i.e. everything after the first HeaderSize bytes of the file.
  if (not WithHeader) and ((HeaderType = 'PLUS3DOS') or (HeaderType = 'AMSDOS')) then
    Result := Copy(FileData, HeaderSize, TotalSize - HeaderSize)
  else
    Result := Copy(FileData, 0, TotalSize);
end;

end.
