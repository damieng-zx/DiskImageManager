unit MGTFileSystem;

{$MODE Delphi}

{
  Disk Image Manager -  Virtual MGT file system

  The directory and file layout shared by the MGT +D and DISCiPLE on the
  Spectrum and by SAMDOS, MasterDOS and BDOS on the SAM Coupe, checked against
  Simon Owen's mgtdisklib (https://github.com/simonowen/mgtdisklib).

  Disk addresses are a track byte and a sector number from 1. The track byte is
  the cylinder, with bit 7 set for side 1. They are resolved against the side
  and cylinder directly, so they hold for a raw image and for the same disk
  carried in a DSK or Teledisk image, which number their tracks differently.

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DSKImage, DIMUtils,
  Classes, SysUtils, Math, FGL;

const
  MGTDirEntrySize = 256;
  MGTDirTracks = 4;        // directory tracks on a standard disk
  MGTMaxDirTracks = 39;    // as far as MasterDOS can grow it
  MGTChainPayload = 510;   // data bytes in a chained sector; the last two link on
  MGTFileHeaderSize = 9;
  // Sectors a file's sector map covers: everything after the standard directory
  MGTMapSectors = (MGTSides * MGTTracks - MGTDirTracks) * MGTSectorsPerTrack;

type
  // Which operating system's disk this is, as far as the directory can tell
  TMGTDosType = (mdPlusD, mdSAMDOS, mdMasterDOS, mdBDOS);

  // What a file's contents can be shown as
  TMGTViewKind = (mvNone, mvBasic, mvStringArray, mvScreen);

  TMGTFile = class;

  TMGTFileSystem = class(TObject)
  private
    FParentDisk: TDSKDisk;
    function FirstDirectorySector: TDSKSector;
    function GetDirectorySlot(Slot: integer; out Sector: TDSKSector; out Offset: integer): boolean;
    function GetDirectorySlots: integer;
    function GetDirectoryTracks: integer;
    function GetDiskLabel: string;
    function GetDosType: TMGTDosType;
    function HasMasterDOSMarker: boolean;
    function HoldsOnlySpectrumFiles: boolean;
  public
    // The sector at an MGT disk address, or nil when the disk has no such sector
    function GetSector(TrackByte, SectorID: byte): TDSKSector;
    // The file described by the entry at Offset, or nil when the slot is free
    function ReadFileEntry(const Data: array of byte; Offset: integer): TMGTFile;
    function Directory: TFPGList<TMGTFile>;
    // Give a file a new name. Raises EConvertError for one that the directory
    // cannot hold or that another file already has.
    function RenameFile(DiskFile: TMGTFile; const NewFileName: string): boolean;

    constructor Create(ParentDisk: TDSKDisk);
    destructor Destroy; override;

    property DirectorySlots: integer read GetDirectorySlots;
    property DirectoryTracks: integer read GetDirectoryTracks;
    property DiskLabel: string read GetDiskLabel;
    property DosType: TMGTDosType read GetDosType;
  end;

  TMGTFile = class(TDiskFile)
  private
    FParentFileSystem: TMGTFileSystem;
    function ReadChain: TDiskByteArray;
    function ReadMapped(PayloadSize: integer): TDiskByteArray;
    procedure Describe;
  public
    // The directory entry as it is on the disk
    Entry: array[0..MGTDirEntrySize - 1] of byte;
    EntryIndex: integer;
    FileType: byte;
    Meta: string;
    SectorsAllocated: integer;
    AllocatedSize: integer;
    // The length of the file's data, not counting any header
    Size: integer;

    // Whether the data stored on the disk starts with a 9-byte file header
    function HasHeader: boolean; override;
    // Whether the file occupies whole sectors rather than a chain of them
    function IsContiguous: boolean;
    // The data length the directory records, or -1 for a type that records none
    function DeclaredLength: integer;
    function MapBit(Index: integer): boolean;
    function MappedSectorCount: integer;
    function GetData(WithHeader: boolean): TDiskByteArray; override;
    // For code, screens and 48K snapshots
    procedure GetAddresses(out Load, Exec: integer); override;
    // SAM Coupe BASIC, arrays and screens differ from the Spectrum's and have
    // no viewer
    function ViewKind: TMGTViewKind;
    // A Spectrum BASIC program without its variables, or nothing for any other file
    function BasicProgram: TDiskByteArray;

    constructor Create(ParentFileSystem: TMGTFileSystem);
    destructor Destroy; override;
  end;

// The disk address a sector map bit stands for
procedure MGTMapLocation(Index: integer; out TrackByte, SectorID: byte);

// The sector map bit for a disk address, or -1 for one outside the data area
function MGTMapIndex(TrackByte, SectorID: byte): integer;

implementation

uses
  SpectrumScreen;

const
  // File types, the low five bits of an entry's first byte
  ftErased = 0;
  ftBasic = 1;
  ftNumberArray = 2;
  ftStringArray = 3;
  ftCode = 4;
  ftSnapshot48 = 5;
  ftMicrodrive = 6;
  ftScreen = 7;
  ftSpecial = 8;
  ftSnapshot128 = 9;
  ftOpentype = 10;
  ftExecute = 11;
  ftUniDOSDir = 12;
  ftUniDOSCreate = 13;
  ftSAMBasic = 16;
  ftSAMNumberArray = 17;
  ftSAMStringArray = 18;
  ftSAMCode = 19;
  ftSAMScreen = 20;
  ftMasterDOSDir = 21;
  ftDriverApp = 22;
  ftDriverBoot = 23;

  FileTypeMask = $1F;
  ProtectedBit = $40;
  HiddenBit = $80;

  // Offsets within a directory entry
  deName = 1;
  deNameLength = 10;
  deSectors = 11;        // big endian
  deFirstTrack = 13;
  deFirstSector = 14;
  deSectorMap = 15;
  deLabel = 210;         // first entry only
  deLengthHigh = 210;    // +D: bits 16-23 of the length
  deLength = 212;
  deStart = 214;
  deZXVariable = 216;
  deZXParameter = 218;   // autorun line, or CODE execute address
  deSAMFlags = 220;
  deSAMInfo = 221;       // screen mode, or the length of an array's name
  deSAMName = 222;
  deBDOSSignature = 232;
  deSAMStart = 236;
  deSAMLength = 239;
  deSAMExecute = 242;    // execute address, or autorun marker and line
  deBDOSLabel = 250;
  deDirTag = 254;        // MasterDOS: the subdirectory the file is in, 0 the root
  deDirTracks = 255;     // first entry only: MasterDOS extra directory tracks

  EntriesPerSector = MGTSectorSize div MGTDirEntrySize;
  EntriesPerTrack = MGTSectorsPerTrack * EntriesPerSector;
  StandardSlots = MGTDirTracks * EntriesPerTrack;
  PageSize = 16384;

procedure MGTMapLocation(Index: integer; out TrackByte, SectorID: byte);
var
  Linear: integer;
begin
  Linear := MGTDirTracks + Index div MGTSectorsPerTrack;
  TrackByte := (Linear div MGTTracks) * 128 + Linear mod MGTTracks;
  SectorID := Index mod MGTSectorsPerTrack + 1;
end;

function MGTMapIndex(TrackByte, SectorID: byte): integer;
var
  Linear: integer;
begin
  Result := -1;
  if ((TrackByte and $7F) >= MGTTracks) or (SectorID < 1) or
    (SectorID > MGTSectorsPerTrack) then exit;
  Linear := (TrackByte shr 7) * MGTTracks + (TrackByte and $7F);
  if Linear < MGTDirTracks then exit;
  Result := (Linear - MGTDirTracks) * MGTSectorsPerTrack + SectorID - 1;
end;

// SAM stores addresses and lengths as a 16K page and an offset within it
function SAMTriple(const Data: array of byte; Offset: integer): integer;
begin
  Result := (Data[Offset] and $1F) * PageSize + (ReadWordLE(Data, Offset + 1) and $7FFF);
end;

// A label byte may carry flags in its top bit, and is padded with spaces or NULs
function CleanLabel(const Data: array of byte; Offset, Count: integer): string;
var
  Idx: integer;
  Value: byte;
begin
  Result := '';
  for Idx := Offset to Offset + Count - 1 do
  begin
    Value := Data[Idx] and $7F;
    if Value >= 32 then
      Result := Result + Chr(Value);
  end;
  Result := Result.TrimRight;
end;

// File system

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

function TMGTFileSystem.GetSector(TrackByte, SectorID: byte): TDSKSector;
var
  SideIdx, TrackIdx: integer;
begin
  Result := nil;
  SideIdx := TrackByte shr 7;
  TrackIdx := TrackByte and $7F;
  if (SideIdx >= FParentDisk.Sides) or (TrackIdx >= FParentDisk.Side[SideIdx].Tracks) then
    exit;
  Result := FParentDisk.Side[SideIdx].Track[TrackIdx].GetLogicalSectorByID(SectorID);
end;

// The sector holding the first two entries, which also describe the disk
function TMGTFileSystem.FirstDirectorySector: TDSKSector;
begin
  Result := GetSector(0, 1);
  if (Result <> nil) and (Result.DataSize < MGTDirEntrySize) then
    Result := nil;
end;

// MasterDOS puts its disk label, or a '*', where the other systems leave 0 or
// 255. A +D 128K snapshot or large Opentype file keeps the top byte of its
// length there too, which is far too small to be a label character. Nor is a
// directory count past what MasterDOS allows, as on a disk full of filler.
function TMGTFileSystem.HasMasterDOSMarker: boolean;
var
  Sector: TDSKSector;
  Marker, FirstType: byte;
begin
  Result := False;
  Sector := FirstDirectorySector;
  if Sector = nil then exit;
  Marker := Sector.Data[deLabel];
  FirstType := Sector.Data[0] and FileTypeMask;
  Result := (Marker <> 0) and (Marker <> $FF) and
    (Sector.Data[deDirTracks] <= MGTMaxDirTracks - MGTDirTracks) and
    not ((FirstType in [ftSnapshot128, ftOpentype]) and (Marker < 32));
end;

// Whether a slot describes a file. Type zero marks a deleted one, whose old name
// and allocation count may still be there, and no file starts off the disk.
function IsFileEntry(const Data: array of byte; Offset: integer): boolean;
begin
  Result := ((Data[Offset] and FileTypeMask) <> ftErased) and
    ((Data[Offset + deFirstTrack] and $7F) < MGTTracks) and
    (StrBlockClean(Data, Offset + deName, deNameLength).TrimRight <> '');
end;

// SPECIAL files are left out of the evidence: SAM CP/M disks are made of them
function TMGTFileSystem.HoldsOnlySpectrumFiles: boolean;
var
  Slot, Offset: integer;
  Sector: TDSKSector;
  Kind: byte;
begin
  Result := False;
  for Slot := 0 to StandardSlots - 1 do
  begin
    if not GetDirectorySlot(Slot, Sector, Offset) then continue;
    if not IsFileEntry(Sector.Data, Offset) then continue;
    Kind := Sector.Data[Offset] and FileTypeMask;
    if Kind >= ftSAMBasic then exit(False);
    if Kind in [ftBasic..ftScreen, ftSnapshot128..ftUniDOSCreate] then
      Result := True;
  end;
end;

function TMGTFileSystem.GetDosType: TMGTDosType;
var
  Sector: TDSKSector;
begin
  Sector := FirstDirectorySector;
  if (Sector <> nil) and StrInByteArray(Sector.Data, 'BDOS', deBDOSSignature) then
    Result := mdBDOS
  else if HasMasterDOSMarker then
    Result := mdMasterDOS
  else if HoldsOnlySpectrumFiles then
    Result := mdPlusD
  else
    Result := mdSAMDOS;
end;

// Only MasterDOS can have more than four. This does not ask for the DOS type,
// which has to walk the directory this describes.
function TMGTFileSystem.GetDirectoryTracks: integer;
var
  Sector: TDSKSector;
begin
  Result := MGTDirTracks;
  Sector := FirstDirectorySector;
  if (Sector = nil) or StrInByteArray(Sector.Data, 'BDOS', deBDOSSignature) or
    not HasMasterDOSMarker then exit;
  Result := Min(MGTDirTracks + Sector.Data[deDirTracks], MGTMaxDirTracks);
end;

function TMGTFileSystem.GetDirectorySlots: integer;
var
  Tracks: integer;
begin
  Tracks := DirectoryTracks;
  Result := Tracks * EntriesPerTrack;
  // A longer directory steps over track 4 sector 1, which stays a boot sector
  if Tracks > MGTDirTracks then
    Dec(Result, EntriesPerSector);
end;

function TMGTFileSystem.GetDirectorySlot(Slot: integer; out Sector: TDSKSector;
  out Offset: integer): boolean;
var
  Position: integer;
begin
  Position := Slot;
  if Position >= StandardSlots then
    Inc(Position, EntriesPerSector);
  Sector := GetSector(Position div EntriesPerTrack,
    1 + (Position mod EntriesPerTrack) div EntriesPerSector);
  Offset := (Position mod EntriesPerSector) * MGTDirEntrySize;
  Result := (Sector <> nil) and (Sector.DataSize >= Offset + MGTDirEntrySize);
end;

function TMGTFileSystem.GetDiskLabel: string;
var
  Sector: TDSKSector;
begin
  Result := '';
  Sector := FirstDirectorySector;
  if Sector = nil then exit;

  case DosType of
    mdBDOS:
      // Sixteen characters in two parts, the second at the end of the entry
      if Sector.Data[deLabel] <> 0 then
        Result := (CleanLabel(Sector.Data, deLabel, 10) +
          CleanLabel(Sector.Data, deBDOSLabel, 6)).TrimRight;
    mdMasterDOS:
      if Sector.Data[deLabel] <> Ord('*') then
        Result := CleanLabel(Sector.Data, deLabel, 10);
  end;
end;

function TMGTFileSystem.Directory: TFPGList<TMGTFile>;
var
  Slot, Offset: integer;
  Sector: TDSKSector;
  DiskFile: TMGTFile;
begin
  Result := TFPGList<TMGTFile>.Create;
  try
    for Slot := 0 to DirectorySlots - 1 do
    begin
      if not GetDirectorySlot(Slot, Sector, Offset) then continue;
      DiskFile := ReadFileEntry(Sector.Data, Offset);
      if DiskFile = nil then continue;
      DiskFile.EntryIndex := Slot;
      Result.Add(DiskFile);
    end;
  except
    for DiskFile in Result do
      DiskFile.Free;
    Result.Free;
    raise;
  end;
end;

function TMGTFileSystem.ReadFileEntry(const Data: array of byte; Offset: integer): TMGTFile;
begin
  Result := nil;
  if not IsFileEntry(Data, Offset) then exit;

  Result := TMGTFile.Create(Self);
  Move(Data[Offset], Result.Entry, MGTDirEntrySize);
  Result.FileName := StrBlockClean(Data, Offset + deName, deNameLength).TrimRight;
  Result.FileType := Data[Offset] and FileTypeMask;
  Result.SectorsAllocated := ReadWordBE(Data, Offset + deSectors);
  Result.AllocatedSize := Result.SectorsAllocated * MGTSectorSize;
  Result.Size := Result.DeclaredLength;
  if Result.Size < 0 then
    Result.Size := Result.SectorsAllocated * MGTChainPayload;
  Result.FirstSector := GetSector(Data[Offset + deFirstTrack], Data[Offset + deFirstSector]);
  Result.Describe;
end;

function TMGTFileSystem.RenameFile(DiskFile: TMGTFile;
  const NewFileName: string): boolean;
var
  NewName: string;
  Sector, Other: TDSKSector;
  Offset, OtherOffset, Slot, Idx: integer;
  Nested: boolean;
  Value: byte;
begin
  Result := False;
  if DiskFile = nil then exit;
  // Names are padded with spaces, so any typed at the end would be lost. An
  // unchanged name is left as it is, whatever characters the listing dropped.
  NewName := NewFileName.TrimRight;
  if NewName = DiskFile.FileName then exit;

  if NewName = '' then
    raise EConvertError.Create('An MGT file must have a name.');
  for Idx := 1 to Length(NewName) do
    if not (NewName[Idx] in [' '..'~']) or (NewName[Idx] in ['*', '?']) then
      raise EConvertError.Create(
        'MGT names may contain only plain ASCII characters, other than * and ?.');
  if Length(NewName) > deNameLength then
    raise EConvertError.CreateFmt('MGT names may be at most %d characters.',
      [deNameLength]);

  // Only the entry the file was read from, and only while it is still there
  if not GetDirectorySlot(DiskFile.EntryIndex, Sector, Offset) or
    not CompareMem(@Sector.Data[Offset], @DiskFile.Entry[0], MGTDirEntrySize) then exit;

  // The byte naming an entry's directory means that only where there are
  // subdirectories to be in
  Nested := False;
  for Slot := 0 to DirectorySlots - 1 do
    if GetDirectorySlot(Slot, Other, OtherOffset) and
      IsFileEntry(Other.Data, OtherOffset) and
      (Other.Data[OtherOffset] and FileTypeMask = ftMasterDOSDir) then
      Nested := True;

  for Slot := 0 to DirectorySlots - 1 do
  begin
    if (Slot = DiskFile.EntryIndex) or
      not GetDirectorySlot(Slot, Other, OtherOffset) or
      not IsFileEntry(Other.Data, OtherOffset) then continue;
    // Each MasterDOS subdirectory may have a file of the same name
    if Nested and
      (Other.Data[OtherOffset + deDirTag] <> DiskFile.Entry[deDirTag]) then continue;
    if SameText(StrBlockClean(Other.Data, OtherOffset + deName,
      deNameLength).TrimRight, NewName) then
      raise EConvertError.CreateFmt('There is already a file called %s.', [NewName]);
  end;

  for Idx := 0 to deNameLength - 1 do
  begin
    if Idx < Length(NewName) then
      Value := Ord(NewName[Idx + 1])
    else
      Value := Ord(' ');
    Sector.Data[Offset + deName + Idx] := Value;
    DiskFile.Entry[deName + Idx] := Value;
  end;
  Sector.IsChanged := True;
  DiskFile.FileName := NewName;
  Result := True;
end;

// File

constructor TMGTFile.Create(ParentFileSystem: TMGTFileSystem);
begin
  inherited Create;
  FParentFileSystem := ParentFileSystem;
end;

destructor TMGTFile.Destroy;
begin
  FParentFileSystem := nil;
  inherited Destroy;
end;

function TMGTFile.HasHeader: boolean;
begin
  Result := FileType in [ftBasic..ftCode, ftScreen, ftSAMBasic..ftSAMScreen,
    ftDriverApp, ftDriverBoot];
end;

function TMGTFile.IsContiguous: boolean;
begin
  Result := FileType in [ftSpecial, ftUniDOSDir];
end;

function TMGTFile.MapBit(Index: integer): boolean;
begin
  Result := (Index >= 0) and (Index < MGTMapSectors) and
    (Entry[deSectorMap + Index div 8] and (1 shl (Index mod 8)) <> 0);
end;

function TMGTFile.MappedSectorCount: integer;
var
  Index: integer;
begin
  Result := 0;
  for Index := 0 to MGTMapSectors - 1 do
    if MapBit(Index) then
      Inc(Result);
end;

function TMGTFile.DeclaredLength: integer;
var
  Recorded: integer;

  // Only Uni-DOS records a length for these; the others leave it zero
  function RecordedOr(Fallback: integer): integer;
  begin
    if Recorded = 0 then
      Result := Fallback
    else
      Result := Recorded;
  end;

begin
  Recorded := Entry[deLengthHigh] * 65536 + ReadWordLE(Entry, deLength);
  case FileType of
    ftBasic..ftCode, ftScreen, ftOpentype, ftUniDOSCreate:
      Result := Recorded;
    ftSnapshot48: Result := RecordedOr(49152);
    ftMicrodrive: Result := RecordedOr(MappedSectorCount * MGTChainPayload);
    ftSnapshot128: Result := RecordedOr(131073);
    ftExecute: Result := RecordedOr(MGTChainPayload);
    ftSpecial, ftUniDOSDir: Result := MappedSectorCount * MGTSectorSize;
    ftSAMBasic..ftSAMScreen, ftDriverApp, ftDriverBoot:
      Result := SAMTriple(Entry, deSAMLength);
    ftMasterDOSDir: Result := 0;
    else
      Result := -1;
  end;
end;

procedure TMGTFile.Describe;

  function ZXVariable: string;
  begin
    // One based in the low six bits: 1 is 'a'
    Result := Chr(Ord('a') + (Entry[deZXVariable] and $3F) - 1);
  end;

  function SAMVariable: string;
  begin
    Result := StrBlockClean(Entry, deSAMName, Entry[deSAMInfo] and $0F).TrimRight;
  end;

var
  Parameter: integer;
begin
  Parameter := ReadWordLE(Entry, deZXParameter);
  case FileType of
    ftBasic:
    begin
      Meta := 'BASIC';
      // A high byte of 255, or any line past the last BASIC allows, is none
      if Parameter <= 9999 then
        Meta := Meta + Format(' LINE %d', [Parameter]);
    end;
    ftNumberArray: Meta := Format('Numeric array %s()', [ZXVariable]);
    ftStringArray: Meta := Format('String array %s$()', [ZXVariable]);
    ftCode:
    begin
      Meta := Format('CODE %d,%d', [ReadWordLE(Entry, deStart), Size]);
      if (Parameter <> 0) and (Parameter <> $FFFF) then
        Meta := Meta + Format(',%d', [Parameter]);
    end;
    ftSnapshot48: Meta := 'Snapshot (48K)';
    ftMicrodrive: Meta := 'Microdrive';
    ftScreen: Meta := 'SCREEN';
    ftSpecial: Meta := 'Special';
    ftSnapshot128: Meta := 'Snapshot (128K)';
    ftOpentype: Meta := 'Opentype';
    ftExecute: Meta := 'ZX execute';
    ftUniDOSDir: Meta := 'UNI-DOS subdirectory';
    ftUniDOSCreate: Meta := 'UNI-DOS create';
    ftSAMBasic:
    begin
      Meta := 'SAM BASIC';
      if Entry[deSAMExecute] <> $FF then
        Meta := Meta + Format(' LINE %d', [ReadWordLE(Entry, deSAMExecute + 1)]);
    end;
    ftSAMNumberArray: Meta := Format('SAM numeric array %s()', [SAMVariable]);
    ftSAMStringArray: Meta := Format('SAM string array %s$', [SAMVariable]);
    ftSAMCode:
    begin
      // Start addresses count from the 16K of ROM below the first RAM page
      Meta := Format('SAM CODE %d,%d', [SAMTriple(Entry, deSAMStart) + PageSize, Size]);
      if Entry[deSAMExecute] <> $FF then
        Meta := Meta + Format(',%d', [SAMTriple(Entry, deSAMExecute)]);
    end;
    ftSAMScreen: Meta := Format('SAM SCREEN mode %d', [(Entry[deSAMInfo] and $03) + 1]);
    ftMasterDOSDir: Meta := 'MasterDOS subdirectory';
    ftDriverApp: Meta := 'SAM Driver application';
    ftDriverBoot: Meta := 'SAM Driver bootstrap';
    24: Meta := 'EDOS NOMEN';
    25: Meta := 'EDOS system';
    26: Meta := 'EDOS overlay';
    28: Meta := 'HDOS Hdos';
    29: Meta := 'HDOS Hdir';
    30: Meta := 'HDOS Hdisk';
    31: Meta := 'HDOS Hfree/Htmp';
    else
      Meta := Format('Custom 0x%x', [FileType]);
  end;

  // MasterDOS can store a file packed, and it is extracted as it is stored
  if (FileType in [ftSAMBasic..ftSAMScreen]) and (Entry[deSAMFlags] and $04 <> 0) then
    Meta := Meta + ' (compressed)';
  if Entry[0] and ProtectedBit <> 0 then Meta := Meta + ' (protected)';
  if Entry[0] and HiddenBit <> 0 then Meta := Meta + ' (hidden)';
end;

// The data of the sectors linked from the first, stopping at the end marker or
// at a link that repeats, leaves the data area or leads to a missing sector
function TMGTFile.ReadChain: TDiskByteArray;
var
  Visited: array[0..MGTMapSectors - 1] of boolean;
  TrackByte, SectorID: byte;
  Index, Count: integer;
  Sector: TDSKSector;
begin
  Result := nil;
  SetLength(Result, MGTMapSectors * MGTChainPayload);
  Count := 0;
  FillChar(Visited, SizeOf(Visited), 0);
  TrackByte := Entry[deFirstTrack];
  SectorID := Entry[deFirstSector];

  while (TrackByte <> 0) or (SectorID <> 0) do
  begin
    Index := MGTMapIndex(TrackByte, SectorID);
    if (Index < 0) or Visited[Index] then break;
    Visited[Index] := True;

    Sector := FParentFileSystem.GetSector(TrackByte, SectorID);
    if (Sector = nil) or (Sector.DataSize < MGTSectorSize) then break;
    Move(Sector.Data, Result[Count], MGTChainPayload);
    Inc(Count, MGTChainPayload);
    TrackByte := Sector.Data[MGTChainPayload];
    SectorID := Sector.Data[MGTChainPayload + 1];
  end;

  SetLength(Result, Count);
end;

// The data of the sectors the entry's map claims, in disk order
function TMGTFile.ReadMapped(PayloadSize: integer): TDiskByteArray;
var
  Index, Count: integer;
  TrackByte, SectorID: byte;
  Sector: TDSKSector;
begin
  Result := nil;
  SetLength(Result, MappedSectorCount * PayloadSize);
  Count := 0;
  for Index := 0 to MGTMapSectors - 1 do
  begin
    if not MapBit(Index) then continue;
    MGTMapLocation(Index, TrackByte, SectorID);
    Sector := FParentFileSystem.GetSector(TrackByte, SectorID);
    if (Sector = nil) or (Sector.DataSize < MGTSectorSize) then continue;
    Move(Sector.Data, Result[Count], PayloadSize);
    Inc(Count, PayloadSize);
  end;
  SetLength(Result, Count);
end;

// The chain is the first choice. A damaged one can stop early, loop or wander
// off, and the sector map is then the better account of where the file lies. A
// damaged file yields what can be recovered.
function TMGTFile.GetData(WithHeader: boolean): TDiskByteArray;
var
  Chain, Mapped, Data: TDiskByteArray;
  Declared, HeaderLength, First, Last: integer;
begin
  Result := nil;
  if FileType = ftMasterDOSDir then exit;

  HeaderLength := 0;
  if HasHeader then HeaderLength := MGTFileHeaderSize;
  Declared := DeclaredLength;

  Chain := nil;
  if not IsContiguous then
    Chain := ReadChain;

  if (Declared >= 0) and (Length(Chain) >= HeaderLength + Declared) then
    Data := Chain
  else
  begin
    if IsContiguous then
      Mapped := ReadMapped(MGTSectorSize)
    else
      Mapped := ReadMapped(MGTChainPayload);

    // Prefer the map when it agrees with all the chain found, else the longer
    if (Length(Chain) = 0) or ((Length(Mapped) >= Length(Chain)) and
      CompareMem(@Mapped[0], @Chain[0], Length(Chain))) then
      Data := Mapped
    else if Length(Chain) > Length(Mapped) then
      Data := Chain
    else
      Data := Mapped;
  end;

  Last := Length(Data);
  if (Declared >= 0) and (HeaderLength + Declared < Last) then
    Last := HeaderLength + Declared;
  if WithHeader then
    First := 0
  else
    First := Min(HeaderLength, Last);

  Result := Copy(Data, First, Last - First);
end;

procedure TMGTFile.GetAddresses(out Load, Exec: integer);
const
  // Where the Spectrum's memory begins, with its screen
  RAMStart = 16384;
var
  Parameter, Start: integer;
begin
  inherited GetAddresses(Load, Exec);
  case FileType of
    ftCode:
      begin
        Load := ReadWordLE(Entry, deStart);
        Parameter := ReadWordLE(Entry, deZXParameter);
        if (Parameter <> 0) and (Parameter <> $FFFF) then
          Exec := Parameter;
      end;
    ftScreen, ftSnapshot48: Load := RAMStart;
    ftSAMCode:
      begin
        // SAM code above 64K is paged in, so has no one address for the Z80
        Start := SAMTriple(Entry, deSAMStart) + PageSize;
        if Start <= $FFFF then
          Load := Start;
      end;
  end;
end;

function TMGTFile.ViewKind: TMGTViewKind;
begin
  Result := mvNone;
  case FileType of
    ftBasic: Result := mvBasic;
    ftStringArray: Result := mvStringArray;
    // A screen saved from BASIC is CODE; the snapshot button saves a SCREEN
    ftCode, ftScreen:
      if TSpectrumScreen.IsValidScreenSize(Size) then
        Result := mvScreen;
  end;
end;

function TMGTFile.BasicProgram: TDiskByteArray;
var
  Data: TDiskByteArray;
begin
  Result := nil;
  if FileType <> ftBasic then exit;
  Data := GetData(False);
  // Where an array keeps its name, a program keeps its length without variables
  Result := Copy(Data, 0, Min(ReadWordLE(Entry, deZXVariable), Length(Data)));
end;

end.
