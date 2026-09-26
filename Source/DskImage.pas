unit DskImage;

{$MODE Delphi}

{
  Disk Image Manager -  Virtual disk management

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DSKFormat, TeleDisk, Utils, Classes, Dialogs, SysUtils, Math, Character, ZStream;

const
  MaxSectorSize = 32768;
  // Each sector owns a fixed ~32 KiB buffer. Keep one image below ~128 MiB of
  // sector objects even when its file declares many sectors without any data.
  MaxImageSectors = 4096;
  Alt8KSize = 6144;
  FDCSectorSizes: array[0..8] of word = (128, 256, 512, 1024, 2048, 4096, 8192, 16384, MaxSectorSize);
  MGTRawSize = 819200;  // Raw MGT/SAM image: 2 sides x 80 tracks x 10 sectors x 512 bytes

type
  // Physical disk structure
  TDSKImage = class;
  TDSKDisk = class;
  TDSKSide = class;
  TDSKTrack = class;
  TDSKSector = class;

  // Logical intepretations
  TDSKFormatSpecification = class;
  TDSKSpecification = class;

  // Directory entry cursor: walks fixed-size entries packed across the logical
  // sectors of a disk, crossing sector boundaries as it goes. Shared by the
  // CP/M and MGT file systems, whose directories differ only in the entry size,
  // the entry count and which sector the walk starts from.
  TDSKDirEntry = record
    Sector: TDSKSector;
    Offset: integer;
    Index: integer;
  end;

  TDSKDirEntryEnumerator = class(TObject)
  private
    FDisk: TDSKDisk;
    FSector: TDSKSector;
    FOffset, FIndex, FEntrySize, FMaxEntries: integer;
    FStarted: boolean;
    FCurrent: TDSKDirEntry;
  public
    constructor Create(ADisk: TDSKDisk; AStart: TDSKSector; AEntrySize, AMaxEntries: integer);
    function MoveNext: boolean;
    property Current: TDSKDirEntry read FCurrent;
  end;

  TDSKDirEntryWalk = record
    Disk: TDSKDisk;
    Start: TDSKSector;
    EntrySize: integer;
    MaxEntries: integer;
    function GetEnumerator: TDSKDirEntryEnumerator;
  end;

  // Whole-disk walks, so a method that just visits every track or every sector
  // can say 'for Track in Disk.AllTracks' rather than hand-roll the nested
  // side/track/sector loop. Both visit in side-major order, exactly as the
  // hand-rolled loops did.
  TDSKTrackEnumerator = class(TObject)
  private
    FDisk: TDSKDisk;
    FSideIdx, FTrackIdx: integer;
    FCurrent: TDSKTrack;
  public
    constructor Create(ADisk: TDSKDisk);
    function MoveNext: boolean;
    property Current: TDSKTrack read FCurrent;
  end;

  TDSKTrackWalk = record
    Disk: TDSKDisk;
    function GetEnumerator: TDSKTrackEnumerator;
  end;

  TDSKSectorEnumerator = class(TObject)
  private
    FDisk: TDSKDisk;
    FSideIdx, FTrackIdx, FSectorIdx: integer;
    FCurrent: TDSKSector;
  public
    constructor Create(ADisk: TDSKDisk);
    function MoveNext: boolean;
    property Current: TDSKSector read FCurrent;
  end;

  TDSKSectorWalk = record
    Disk: TDSKDisk;
    function GetEnumerator: TDSKSectorEnumerator;
  end;

  // Image
  TDSKImageFormat = (diStandardDSK, diExtendedDSK, diRawMGT, diTeleDisk, diNotYetSaved, diInvalid);

  TDSKImage = class(TObject)
  private
    FCorrupt: boolean;
    FCreator: string;
    FDisk: TDSKDisk;
    FFileName: TFileName;
    FFileSize: int64;
    FIsChanged: boolean;
    procedure SetIsChanged(NewValue: boolean);
    function LoadFileDSK(DiskFile: TStream): boolean;
    function LoadFileMGT(DiskFile: TStream): boolean;
    function LoadFileTD0(DiskFile: TStream): boolean;
    function RecoverExtTrackSize(DiskFile: TStream; ExpTrack, ExpSide: integer): integer;
    function SaveFileDSK(DiskFile: TFileStream; SaveFileFormat: TDSKImageFormat; Compress: boolean): boolean;
    function SaveFileMGT(DiskFile: TFileStream): boolean;
    function SaveFileTD0(DiskFile: TFileStream): boolean;
  public
    FileFormat: TDSKImageFormat;
    // Free text carried with the image, which only Teledisk has room for
    Comment: string;
    Messages: TStringList;

    constructor Create;
    constructor CreateFromFile(FileName: TFileName);
    constructor CreateFromStream(Stream: TStream; FileName: TFileName);
    destructor Destroy; override;

    // Whether the disk as it stands can be described by SaveFileFormat at all.
    // Answers False and says why in Messages when it cannot, so that the reason
    // is available without writing anything or putting a dialog on the screen.
    function CanSave(SaveFileFormat: TDSKImageFormat): boolean;
    function SaveFile(SaveFileName: TFileName; SaveFileFormat: TDSKImageFormat; Copy: boolean; Compress: boolean): boolean;
    function FindText(From: TDSKSector; Text: string; CaseSensitive: boolean;
      IncludeFrom: boolean = True): TDSKSector;
    function HasV5Extensions: boolean;
    function HasOffsetInfo: boolean;
    function HasVariantSectors: boolean;

    property Creator: string read FCreator write FCreator;
    property Corrupt: boolean read FCorrupt write FCorrupt;
    property Disk: TDSKDisk read FDisk write FDisk;
    property FileName: TFileName read FFileName write FFileName;
    property FileSize: int64 read FFileSize write FFileSize;
    property IsChanged: boolean read FIsChanged write SetIsChanged;
  end;


  // Disk
  TDSKDisk = class(TObject)
  private
    FParentImage: TDSKImage;
    FSpecification: TDSKSpecification;
    function GetFormattedCapacity: integer;
    function GetSides: byte;
    function GetTrackTotal: word;
    procedure SetSides(NewSides: byte);
  public
    Side: array of TDSKSide;

    constructor Create(ParentImage: TDSKImage);
    destructor Destroy; override;

    function BootableOn: string;
    function DetectFormat: string;
    function DetectCopyProtection: string;
    function GetFirstSector: TDSKSector;
    function GetLogicalTrack(LogicalTrack: word): TDSKTrack;
    function GetNextLogicalSector(Sector: TDSKSector): TDSKSector;
    function GetSectorByBlock(Block: integer): TDSKSector;
    function DirectoryEntries(Start: TDSKSector; EntrySize, MaxEntries: integer): TDSKDirEntryWalk;
    function AllTracks: TDSKTrackWalk;
    function AllSectors: TDSKSectorWalk;
    function GetAllStrings(MinLength: integer; MinUniques: integer): TStringList;
    function HasFDCErrors: boolean;
    function IsTrackSizeUniform: boolean;
    function IsUniform(IgnoreEmptyTracks: boolean): boolean;
    procedure Format(Formatter: TDSKFormatSpecification);

    property FormattedCapacity: integer read GetFormattedCapacity;
    property Sides: byte read GetSides write SetSides;
    property Specification: TDSKSpecification read FSpecification;
    property TrackTotal: word read GetTrackTotal;
    property ParentImage: TDSKImage read FParentImage;
  end;


  TDSKTrackProperty = (tpDataRate, tpRecordingMode, tpBitLength);

  // Side
  TDSKSide = class(TObject)
  private
    FParentDisk: TDSKDisk;
    function GetTracks: byte;
    function GetHighTrackCount: byte;
    function HasTrackProperty(Prop: TDSKTrackProperty): boolean;
    procedure SetTracks(NewTracks: byte);
  public
    Side: byte;
    Track: array of TDSKTrack;

    constructor Create(ParentDisk: TDSKDisk);
    destructor Destroy; override;

    function GetLargestTrackSize: integer;
    function SafeTrack(Index: integer): TDSKTrack;
    function HasDataRate: boolean;
    function HasRecordingMode: boolean;
    function HasVariantSectors: boolean;
    function HasBitLength: boolean;

    property HighTrackCount: byte read GetHighTrackCount;
    property ParentDisk: TDSKDisk read FParentDisk;
    property Tracks: byte read GetTracks write SetTracks;
  end;

  TDSKDataRate = (drUnknown, drSingleOrDoubleDensity, drHighDensity, drExtendedDensity);
  TDSKRecordingMode = (rmUnknown, rmFM, rmMFM);

  // Disk track
  TDSKTrack = class(TObject)
  private
    FParentSide: TDSKSide;
    function GetIsFormatted: boolean;
    function GetLowSectorID: byte;
    function GetSectors: byte;
    procedure SetSectors(NewSectors: byte);
  public
    DataRate: TDSKDataRate;
    Filler: byte;
    GapLength: byte;
    Logical: word;
    RecordingMode: TDSKRecordingMode;
    Sector: array of TDSKSector;
    SectorSize: word;
    Side: byte;
    Track: byte;
    BitLength: word;

    constructor Create(ParentSide: TDSKSide);
    destructor Destroy; override;

    procedure Format(Formatter: TDSKFormatSpecification);
    procedure Unformat;
    procedure MarkChanged;
    function ParentImage: TDSKImage;
    function GetTrackSizeFromSectors: integer;
    function GetFirstLogicalSector: TDSKSector;
    function SafeSector(Index: integer): TDSKSector;
    function GetLogicalSectorByID(SectorID: byte): TDSKSector;
    function HasMultiSectoredSector: boolean;
    function HasIndexPointOffsets: boolean;

    property IsFormatted: boolean read GetIsFormatted;
    property LowSectorID: byte read GetLowSectorID;
    property ParentSide: TDSKSide read FParentSide;
    property Sectors: byte read GetSectors write SetSectors;
    property Size: integer read GetTrackSizeFromSectors;
  end;


  // Sector
  TDSKSectorStatus = (ssUnformatted, ssFormattedBlank, ssFormattedFilled, ssFormattedInUse);

  TDSKSector = class(TObject)
  private
    FAdvertisedSize: integer;
    FDataSize: word;
    FIsChanged: boolean;
    FParentTrack: TDSKTrack;
    function GetStatus: TDSKSectorStatus;
    procedure SetIsChanged(NewValue: boolean);
  public
    Data: array[0..MaxSectorSize] of byte;
    FDCSize: byte;
    FDCStatus: array[1..2] of byte;
    ID: byte;
    Sector: byte;
    Side: byte;
    Track: byte;
    IndexPointOffset: word;

    constructor Create(ParentTrack: TDSKTrack);
    destructor Destroy; override;

    function GetFillByte: integer;
    function GetModChecksum(ModValue: integer): integer;
    function FindText(Text: string; CaseSensitive: boolean): integer;
    function GetCopyCount: integer;
    function GetCopySize: word;
    function GetCopy(Idx: integer): PByte;

    procedure FillSector(Filler: byte);
    procedure ResetFDC;
    procedure Unformat;
    function ParentImage: TDSKImage;

    property AdvertisedSize: integer read FAdvertisedSize write FAdvertisedSize;
    property DataSize: word read FDataSize write FDataSize;
    // Setting this True also marks the image, so that an edit made through any
    // of the property windows is one the app knows to offer to save
    property IsChanged: boolean read FIsChanged write SetIsChanged;
    property ParentTrack: TDSKTrack read FParentTrack;
    property Status: TDSKSectorStatus read GetStatus;
  end;


  // Specification (Optional PCW/CPC+3 disk specification)
  TDSKSpecFormat = (dsFormatPCW_SS, dsFormatCPC_System, dsFormatCPC_Data, dsFormatPCW_DS,
    dsFormatAssumedPCW_SS, dsFormatEinstein, dsFormatMGT, dsFormatTS2068, dsFormatInvalid);
  TDSKSpecSide = (dsSideSingle, dsSideDoubleAlternate, dsSideDoubleSuccessive, dsSideDoubleReverse, dsSideInvalid);
  TDSKSpecTrack = (dsTrackSingle, dsTrackDouble, dsTrackInvalid);
  TDSKAllocationSize = (asByte, asWord);

  TDSKSpecification = class(TObject)
  private
    FParentDisk: TDSKDisk;
    FIsChanged: boolean;

    FAllocationSize: TDSKAllocationSize;
    FBlockShift: byte;
    FChecksum: byte;
    FDirectoryBlocks: byte;
    FFormat: TDSKSpecFormat;
    FGapFormat: byte;
    FGapReadWrite: byte;
    FReservedTracks: byte;
    FSectorsPerTrack: byte;
    FFDCSectorSize: byte;
    FSectorSize: word;
    FSide: TDSKSpecSide;
    FTrack: TDSKSpecTrack;
    FTracksPerSide: byte;
    procedure SetBlockShift(NewBlockShift: byte);
    procedure SetChecksum(NewChecksum: byte);
    procedure SetDefaults;
    procedure SetDirectoryBlocks(NewDirectoryBlocks: byte);
    procedure SetFDCSectorSize(NewFDCSectorSize: byte);
    procedure SetFormat(NewFormat: TDSKSpecFormat);
    procedure SetGapFormat(NewGapFormat: byte);
    procedure SetGapReadwrite(NewGapReadWrite: byte);
    procedure SetReservedTracks(NewReservedTracks: byte);
    procedure SetSectorsPerTrack(NewSectorsPerTrack: byte);
    procedure SetSectorSize(NewSectorSize: word);
    procedure SetSide(NewSide: TDSKSpecSide);
    procedure SetTrack(NewTrack: TDSKSpecTrack);
    procedure SetTracksPerSide(NewTracksPerSide: byte);
  public
    Source: string;

    constructor Create(ParentDisk: TDSKDisk);
    destructor Destroy; override;

    procedure Identify;
    function Write: boolean;
    function GetBlockSize: integer;
    function GetBlockCount: word;
    function GetUsableCapacity: integer;
    function GetRecordsPerTrack: integer;

    property AllocationSize: TDSKAllocationSize read FAllocationSize write FAllocationSize;
    property BlockShift: byte read FBlockShift write SetBlockShift;
    property Checksum: byte read FChecksum write SetChecksum;
    property DirectoryBlocks: byte read FDirectoryBlocks write SetDirectoryBlocks;
    property FDCSectorSize: byte read FFDCSectorSize write SetFDCSectorSize;
    property Format: TDSKSpecFormat read FFormat write SetFormat;
    property GapFormat: byte read FGapFormat write SetGapFormat;
    property GapReadWrite: byte read FGapReadWrite write SetGapReadWrite;
    property IsChanged: boolean read FIsChanged write FIsChanged;
    property ReservedTracks: byte read FReservedTracks write SetReservedTracks;
    property SectorsPerTrack: byte read FSectorsPerTrack write SetSectorsPerTrack;
    property SectorSize: word read FSectorSize write SetSectorSize;
    property Side: TDSKSpecSide read FSide write SetSide;
    property Track: TDSKSpecTrack read FTrack write SetTrack;
    property TracksPerSide: byte read FTracksPerSide write SetTracksPerSide;
  end;

  // Disk format specification
  TDSKFormatSpecification = class(TObject)
  private
    FSectorIDs: array of byte;
    procedure BuildSectorIDs;
  public
    Bootable: boolean;
    BlockShift: byte;
    DirBlocks: byte;
    FDCSectorSize: byte;
    FillerByte: byte;
    FirstSector: byte;
    GapFormat: byte;
    GapRW: byte;
    Interleave: shortint;
    Name: string;
    ResTracks: byte;
    SectorSize: word;
    SectorsPerTrack: byte;
    SkewSide: shortint;
    SkewTrack: shortint;
    Sides: TDSKSpecSide;
    TracksPerSide: word;
    RecordingMode: TDSKRecordingMode;
    DataRate: TDSKDataRate;

    constructor Create(Format: integer);
    function GetCapacityBytes: integer;
    function GetBlockSize: integer;
    function GetDirectoryEntries: integer;
    function GetSectorID(Side: byte; LogicalTrack: word; Sector: byte): byte;
    function GetSidesCount: byte;
    function GetUsableBytes: integer;
  end;

const
  DSKImageFormats: array[TDSKImageFormat] of string = (
    'Standard DSK',
    'Extended DSK',
    'MGT image',
    'Teledisk TD0',
    'Not yet saved',
    'Invalid'
    );

  DSKSpecFormats: array[TDSKSpecFormat] of string = (
    'Amstrad PCW/+3 DD/SS/ST',
    'Amstrad CPC DD/SS/ST system',
    'Amstrad CPC DD/SS/ST data',
    'Amstrad PCW DD/DS/DT',
    'Amstrad PCW/+3 DD/SS/ST (Assumed)',
    'Tatung Einstein',
    'MGT',
    'Timex/Sinclair TS2068',
    'Invalid'
    );

  DSKSpecAllocations: array[TDSKAllocationSize] of string = (
    '8-bit/byte',
    '16-bit/word'
    );

  DSKSpecSides: array[TDSKSpecSide] of string = (
    'Single',
    'Double (Alternate)',
    'Double (Successive)',
    'Double (Reverse)',
    'Invalid'
    );

  DSKSpecTracks: array[TDSKSpecTrack] of string = (
    'Single',
    'Double',
    'Invalid'
    );

  DSKSectorStatus: array[TDSKSectorStatus] of string = (
    'Unformatted',
    'Formatted (track filler)',
    'Formatted (odd filler)',
    'Formatted (in use)'
    );

  // In the order of TDSKRecordingMode, which is the order the file states them
  // in: these were the other way round, so FM read as MFM and MFM as FM
  DSKRecordingMode: array[TDSKRecordingMode] of string = (
    'Unknown',
    'FM',
    'MFM'
    );

  DSKDataRate: array[TDSKDataRate] of string = (
    'Unknown',
    'Single/Double',
    'High',
    'Extended'
    );

  // FileSystem
  DirEntSize = 32;

// A track's data rate and recording mode come from a byte on the disk or from
// a combo box that answers -1 when nothing is picked, and both are wider than
// the enums they are cast to. An ordinal the enum has no value for then indexes
// past the end of the name table describing it - a table of strings, so what
// comes back is a pointer into whatever follows it. Anything that is not a
// value the enum really has becomes Unknown.
function ToDataRate(Value: integer): TDSKDataRate;
function ToRecordingMode(Value: integer): TDSKRecordingMode;

function GetFDCSectorSize(SectorSize: word): byte;

// Bytes a sector of FDC size code FDCSize holds, or 0 when the code is not one
// the controller defines. The code is a raw byte off the disk and the sector
// properties window will set any of the 256 of them, so indexing the table with
// it unchecked reads past the end of it.
function GetFDCSizeBytes(FDCSize: byte): word;

function GetTrackFileSize(TrackDataSize: integer): integer;

implementation

uses FormatAnalysis, LZHuf, Windows;

// Image
constructor TDSKImage.Create;
begin
  inherited;
  Disk := TDSKDisk.Create(Self);
  Creator := CreatorSig;
  Corrupt := False;
  Messages := TStringList.Create();
end;

constructor TDSKImage.CreateFromFile(FileName: TFileName);
var
  FileStream: TFileStream;
  GZStream: TGZFileStream;
  MemStream: TMemoryStream;
  Buffer: array[0..65535] of byte;
  BytesRead: integer;
const
  fmShareDenyNoneWrite = $0070; // Enables READ + WRITE + DELETE sharing
begin
  Create;

  if ExtractFileExt(FileName) = '.gz' then
  begin
    GZStream := TGZFileStream.Create(FileName, gzopenread);
    try
      // Unpack before loading. A gz stream cannot say how long it is, which
      // left FileSize unset and every truncation check below switched off, and
      // the loader seeks back over the track it has just read.
      MemStream := TMemoryStream.Create;
      try
        repeat
          BytesRead := GZStream.Read(Buffer, SizeOf(Buffer));
          if BytesRead > 0 then
            MemStream.WriteBuffer(Buffer, BytesRead);
        until BytesRead < SizeOf(Buffer);
        MemStream.Position := 0;

        self.FileName := FileName;
        FileSize := MemStream.Size;
        CreateFromStream(MemStream, FileName);
      finally
        MemStream.Free;
      end;
    finally
      GZStream.Free;
    end;
  end
  else
  begin
    self.FileName := FileName;
    FileStream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNoneWrite);
    try
      FileSize := FileStream.Size;
      CreateFromStream(FileStream, FileName);
    finally
      FileStream.Free;
    end;
  end;
end;

constructor TDSKImage.CreateFromStream(Stream: TStream; FileName: TFileName);
var
  DSKInfoBlock: TDSKInfoBlock;
  TD0Header: TTD0Header;
begin
  FileFormat := diInvalid;
  // Read as much of a DSK header as there is. A Teledisk image can be shorter
  // than one, and demanding the whole block failed it before it was looked at.
  FillChar(DSKInfoBlock, SizeOf(DSKInfoBlock), 0);
  Stream.Read(DSKInfoBlock, SizeOf(DSKInfoBlock));
  Move(DSKInfoBlock, TD0Header, SizeOf(TD0Header));

  // Detect image format. One chain, so that recognising a standard image is the
  // end of it: the standard test used to stand alone and the extended tests ran
  // on regardless, leaving a signature that matched both to be decided by
  // whichever came last rather than by which it actually is.
  if CompareBlock(DSKInfoBlock.DiskInfoBlock, 'MV - CPC') then
    FileFormat := diStandardDSK
  else
  if CompareBlock(DSKInfoBlock.DiskInfoBlock, 'EXTENDED CPC DSK File') then
    FileFormat := diExtendedDSK
  else
  if CompareBlockInsensitive(DSKInfoBlock.DiskInfoBlock, 'EXTENDED CPC DSK FILE') then
  begin
    FileFormat := diExtendedDSK;
    Corrupt := True;
    Messages.Add('File signature has incorrect case.');
  end;

  if FileFormat <> diInvalid then
  begin
    Stream.Seek(0, soFromBeginning);
    LoadFileDSK(Stream);
    FIsChanged := False;
  end
  else if (Stream.Size >= SizeOf(TD0Header)) and IsTD0Header(TD0Header) then
  begin
    Stream.Seek(0, soFromBeginning);
    FileFormat := diTeleDisk;
    LoadFileTD0(Stream);
    FIsChanged := False;
  end
  else if SameText(ExtractFileExt(FileName), '.mgt') and (Stream.Size = MGTRawSize) then
  begin
    // Raw MGT/SAM image: a headerless sector dump.
    Stream.Seek(0, soFromBeginning);
    FileFormat := diRawMGT;
    LoadFileMGT(Stream);
    FIsChanged := False;
  end
  else
  begin
    MessageDlg('Load failure', FileName + ' is unknown file type. Load aborted.', mtWarning, [mbOK], 0);
    Corrupt := True;
  end;
end;

destructor TDSKImage.Destroy;
begin
  Disk.Free;
  Messages.Free;
  inherited Destroy;
end;

procedure TDSKImage.SetIsChanged(NewValue: boolean);
begin
  FIsChanged := NewValue;
end;

function TDSKImage.HasV5Extensions: boolean;
var
  Side: TDSKSide;
begin
  for Side in Disk.Side do
    if Side.HasDataRate or Side.HasRecordingMode or Side.HasVariantSectors then
    begin
      Result := True;
      exit;
    end;
  Result := False;
end;

function TDSKImage.HasVariantSectors: boolean;
var
  Side: TDSKSide;
begin
  Result := True;
  for Side in Disk.Side do
    if Side.HasVariantSectors then exit;
  Result := False;
end;

function TDSKImage.HasOffsetInfo: boolean;
var
  Side: TDSKSide;
  Track: TDSKTrack;
  Sector: TDSKSector;
begin
  Result := True;
  for Side in Disk.Side do
    for Track in Side.Track do
    begin
      if Track.BitLength > 0 then exit;
      for Sector in Track.Sector do
        if (Sector.IndexPointOffset > 0) then exit;
    end;
  Result := False;
end;

function TDSKImage.FindText(From: TDSKSector; Text: string; CaseSensitive: boolean;
  IncludeFrom: boolean): TDSKSector;
var
  NextSector: TDSKSector;
begin
  Result := nil;
  if From = nil then
  begin
    if (Length(Disk.Side) = 0) or (Length(Disk.Side[0].Track) = 0) or
       (Length(Disk.Side[0].Track[0].Sector) = 0) then
      exit;
    NextSector := Disk.Side[0].Track[0].Sector[0];
  end
  else if IncludeFrom then
    NextSector := From
  else
    NextSector := Disk.GetNextLogicalSector(From);

  while (NextSector <> nil) and (NextSector.FindText(Text, CaseSensitive) < 0) do
  begin
    NextSector := Disk.GetNextLogicalSector(NextSector);
  end;

  if NextSector = nil then
    MessageDlg(SysUtils.Format('Cannot find "%s"', [Text]), mtInformation, [mbOK], 0)
  else
    Result := NextSector;
end;

// Recover the byte length of an Extended DSK track whose size-table entry is
// zero. Peeks at the Track-Info block at the current position (restoring it
// afterwards). Only succeeds when a valid block is present whose track/side
// numbers match the expected ones - otherwise the zero entry denotes a
// genuinely unformatted track and the peek would land on the next track's data.
// Returns the full track length (Track-Info block + sector data), or 0.
function TDSKImage.RecoverExtTrackSize(DiskFile: TStream; ExpTrack, ExpSide: integer): integer;
var
  SavePos: int64;
  PeekTRK: TTRKInfoBlock;
  PeekSCT: TSCTInfoBlock;
  BytesRead, EIdx, DataLen: integer;
begin
  Result := 0;
  SavePos := DiskFile.Position;
  if SavePos + SizeOf(PeekTRK) > DiskFile.Size then
    exit;

  BytesRead := DiskFile.Read(PeekTRK, SizeOf(PeekTRK));
  DiskFile.Position := SavePos;
  if BytesRead < SizeOf(PeekTRK) then
    exit;

  // Must be a real Track-Info block belonging to the expected track and side.
  if not CompareBlock(PeekTRK.TrackData, DiskInfoTrack) then
    exit;
  if (PeekTRK.TIB_TrackNum <> ExpTrack) or (PeekTRK.TIB_SideNum <> ExpSide) then
    exit;

  Result := 256; // The Track-Info block itself
  for EIdx := 0 to PeekTRK.TIB_NumSectors - 1 do
  begin
    if (EIdx + 1) * SizeOf(PeekSCT) > SizeOf(PeekTRK.SectorInfoList) then
      Break;
    Move(PeekTRK.SectorInfoList[EIdx * SizeOf(PeekSCT)], PeekSCT, SizeOf(PeekSCT));
    DataLen := PeekSCT.SIB_DataLength;
    if (DataLen = 0) and (PeekSCT.SIB_Size <= High(FDCSectorSizes)) then
      DataLen := FDCSectorSizes[PeekSCT.SIB_Size];
    Result := Result + DataLen;
  end;
end;

function TDSKImage.LoadFileDSK(DiskFile: TStream): boolean;
var
  DSKInfoBlock: TDSKInfoBlock;
  TRKInfoBlock: TTRKInfoBlock;
  SCTInfoBlock: TSCTInfoBlock;
  OFFInfoBlock: TOFFInfoBlock;
  Track: TDSKTrack;
  OFFTrackEntry: TOFFTrackEntry;
  SIdx, TIdx, EIdx, LoadedSectors, TrackSectors: integer;
  TOff: integer;
  ReadSize: integer;
  TrackSizeIdx: integer;
  SizeT: word;
  FoundIncorrectTrackMarkers: boolean;
  NextTrackPosition: integer;
  ErrorMessage: string;
  RecoveredTracks, RecoveredSize: integer;
  BytesLeft, SkipTo: int64;
  UnknownTrackModes: boolean;
begin
  Result := False;
  UnknownTrackModes := False;
  FoundIncorrectTrackMarkers := False;
  NextTrackPosition := 0;
  RecoveredTracks := 0;
  LoadedSectors := 0;

  if DiskFile.Size - DiskFile.Position < SizeOf(DSKInfoBlock) then
  begin
    Messages.Add('Disk-Info block is truncated.');
    Corrupt := True;
    exit;
  end;
  DiskFile.ReadBuffer(DSKInfoBlock, SizeOf(DSKInfoBlock));

  // Get the creator (DU54 puts in wrong place)
  if CompareBlockStart(DSKInfoBlock.DiskInfoBlock, CreatorDU54InInfoBlock, 16) then
    Creator := CreatorDU54
  else
    Creator := StrBlockClean(DSKInfoBlock.Disk_Creator, 0, 14);

  if (Creator.Trim = '') then
    Messages.Add('Missing Creator signature.');

  // The Extended header holds one track size byte per track per side, so it is
  // the two multiplied that has to fit, not the track count alone
  if DSKInfoBlock.Disk_NumTracks * DSKInfoBlock.Disk_NumSides > MaxTracks then
  begin
    Messages.Add(SysUtils.Format('Image indicates %d tracks over %d sides, more than the %d track sizes a header holds.',
      [DSKInfoBlock.Disk_NumTracks, DSKInfoBlock.Disk_NumSides, MaxTracks]));
    Corrupt := True;
  end;

  // Build sides & tracks
  Disk.Sides := DSKInfoBlock.Disk_NumSides;
  for SIdx := 0 to DSKInfoBlock.Disk_NumSides - 1 do
    Disk.Side[SIdx].Tracks := DSKInfoBlock.Disk_NumTracks;

  // Load the tracks in
  for TIdx := 0 to DSKInfoBlock.Disk_NumTracks - 1 do
  begin
    for SIdx := 0 to DSKInfoBlock.Disk_NumSides - 1 do
    begin
      with Disk.Side[SIdx].Track[TIdx] do
      begin
        case FileFormat of
          // A standard image with nothing formatted on it records a track size
          // of 0, which this app writes itself, and SizeT is unsigned: taking
          // the Track-Info block off a size that never counted one wraps round
          diStandardDSK:
            if DSKInfoBlock.Disk_StdTrackSize > 256 then
              SizeT := DSKInfoBlock.Disk_StdTrackSize - 256
            else
              SizeT := 0;
          diExtendedDSK:
          begin
            // Flagging the image corrupt above does not stop the load, so an
            // image claiming more tracks and sides than the header has sizes
            // for still has to be kept out of the table here. A track with no
            // size is treated as unformatted, which leaves the recovery below
            // free to find it if the data is really there.
            TrackSizeIdx := (TIdx * DSKInfoBlock.Disk_NumSides) + SIdx;
            if TrackSizeIdx > High(DSKInfoBlock.Disk_ExtTrackSize) then
              SizeT := 0
            else
            begin
              SizeT := (DSKInfoBlock.Disk_ExtTrackSize[TrackSizeIdx] * 256);
              if (SizeT > 0) then
                SizeT := SizeT - 256; // Remove track-info size
            end;
          end;
          else
            SizeT := 0;
        end;

        TOff := DiskFile.Position;

        // Bad place to set this, we don't know disk format yet...
        Logical := (TIdx * DSKInfoBlock.Disk_NumSides) + SIdx;

        // Some writers (e.g. CPDRead) emit an Extended DSK with a blank track-
        // size table even though real track data follows. Recover by reading
        // the actual Track-Info block at the current position.
        if (FileFormat = diExtendedDSK) and (SizeT = 0) then
        begin
          RecoveredSize := RecoverExtTrackSize(DiskFile, TIdx, SIdx);
          if RecoveredSize > 256 then
          begin
            SizeT := RecoveredSize - 256;
            Inc(RecoveredTracks);
          end;
        end;

        if SizeT > 0 then // Don't load if track is unformatted
        begin
          ReadSize := SizeT + 256;
          if (FileSize > 0) and (TOff + ReadSize > FileSize) then
          begin
            Messages.Add(SysUtils.Format('Side %d track %d indicated %d bytes of data' +
              ' but file had only %d bytes left.', [SIdx, TIdx, SizeT, FileSize - TOff]));
            Corrupt := True;
            ReadSize := FileSize - TOff;
          end;

          // Noticing the truncation is no use if the read then asks for the
          // bytes regardless, and there is nothing to load from a track whose
          // header is not all there
          if ReadSize < SizeOf(TRKInfoBlock) then
          begin
            Messages.Add(SysUtils.Format('Side %d track %d has no room left for a track header. Load stopped.',
              [SIdx, TIdx]));
            Corrupt := True;
            exit;
          end;

          DiskFile.ReadBuffer(TRKInfoBlock, SizeOf(TRKInfoBlock));

          // Test to make sure this was a track
          if (TRKInfoBlock.TrackData = DiskInfoTrackBroken) then
          begin
            if (not FoundIncorrectTrackMarkers) then
            begin
              Messages.Add('Disk image uses incorrect "Track-Info" markers padded with spaces not CRLF.');
              FoundIncorrectTrackMarkers := True;
              Corrupt := True;
            end;
          end
          else
          if TRKInfoBlock.TrackData <> DiskInfoTrack then
          begin
            DiskFile.Position := NextTrackPosition;
            DiskFile.ReadBuffer(TRKInfoBlock, SizeOf(TRKInfoBlock));
            Messages.Add(SysUtils.Format('Side %d track %d contained %d bytes unused by a sector', [SIdx, TIdx, NextTrackPosition - TOff]));
            TOff := DiskFile.Position - 256;

            if TRKInfoBlock.TrackData <> DiskInfoTrack then
            begin
              ErrorMessage := SysUtils.Format('Side %d track %d not found at offset %d to %d. Load stopped.',
                [SIdx, TIdx, TOff, DiskFile.Position]);
              Messages.Add(ErrorMessage);
              MessageDlg(ExtractFileName(FileName) + ': ' + ErrorMessage, mtError, [mbOK], 0);
              Corrupt := True;
              exit;
            end;
          end;

          NextTrackPosition := TOff + SizeT + 256;

          // Set various track info properties
          Track := TRKInfoBlock.TIB_TrackNum;
          Side := TRKInfoBlock.TIB_SideNum;
          // A Track-Info block is 256 bytes and carries its sector entries in
          // what is left after the header, so the count is capped by the room
          // for them however many the file claims
          TrackSectors := Min(TRKInfoBlock.TIB_NumSectors, MaxTrackInfoSectors);
          // A Track-Info block can describe 29 empty sectors in 256 bytes,
          // while each in-memory sector owns a 32 KiB buffer. Bound the total
          // before allocating any more, including recovered Extended tracks.
          if TrackSectors > MaxImageSectors - LoadedSectors then
          begin
            Messages.Add(SysUtils.Format('Image declares more than %d sectors; load stopped.', [MaxImageSectors]));
            Corrupt := True;
            exit;
          end;
          Inc(LoadedSectors, TrackSectors);

          if TRKInfoBlock.TIB_NumSectors > MaxTrackInfoSectors then
          begin
            Messages.Add(SysUtils.Format('Side %d track %d indicated %d sectors, more than the %d a track holds.',
              [SIdx, TIdx, TRKInfoBlock.TIB_NumSectors, MaxTrackInfoSectors]));
            Corrupt := True;
          end;
          Sectors := TrackSectors;
          // The track's sector size is written back out from this, so it has to
          // be read whatever the format. Taking it only from standard images
          // left every extended track at 0, and saving turned that back into a
          // size code of 0, which says 128 bytes, for every track on the disk.
          if TRKInfoBlock.TIB_SectorSize <= High(FDCSectorSizes) then
            SectorSize := FDCSectorSizes[TRKInfoBlock.TIB_SectorSize]
          else
            SectorSize := MaxSectorSize;
          GapLength := TRKInfoBlock.TIB_GapLength;
          Filler := TRKInfoBlock.TIB_FillerByte;

          // Extended V5 support for data rate and recording mode
          if FileFormat = diExtendedDSK then
          begin
            DataRate := ToDataRate(TRKInfoBlock.TIB_DataRate);
            RecordingMode := ToRecordingMode(TRKInfoBlock.TIB_RecordingMode);
            if (DataRate = drUnknown) and (TRKInfoBlock.TIB_DataRate <> 0) then
              UnknownTrackModes := True;
            if (RecordingMode = rmUnknown) and (TRKInfoBlock.TIB_RecordingMode <> 0) then
              UnknownTrackModes := True;
          end;

          // Load the actual sectors in
          for EIdx := 0 to Sectors - 1 do
            with Sector[EIdx] do
            begin
              Move(TRKInfoBlock.SectorInfoList[EIdx * SizeOf(SCTInfoBlock)], SCTInfoBlock, SizeOf(SCTInfoBlock));
              Sector := EIdx;
              Track := SCTInfoBlock.SIB_TrackNum;
              Side := SCTInfoBlock.SIB_SideNum;
              ID := SCTInfoBlock.SIB_ID;
              FDCSize := SCTInfoBlock.SIB_Size;
              FDCStatus[1] := SCTInfoBlock.SIB_FDC1;
              FDCStatus[2] := SCTInfoBlock.SIB_FDC2;

              case FileFormat of
                diStandardDSK:
                begin
                  DataSize := MaxSectorSize;
                  if (SCTInfoBlock.SIB_Size <= High(FDCSectorSizes)) then
                    DataSize := FDCSectorSizes[SCTInfoBlock.SIB_Size];
                end;
                diExtendedDSK: DataSize := SCTInfoBlock.SIB_DataLength;
                else
                  DataSize := 0;
              end;

              AdvertisedSize := DataSize;
              if DataSize > MaxSectorSize then
              begin
                Messages.Add(SysUtils.Format('Side %d track %d sector %d exceeds %d byte size limit.',
                  [TIdx, SIdx, EIdx, MaxSectorSize]));
                Corrupt := True;
                DataSize := MaxSectorSize;
              end;

              // The file can equally run out part way through a track's sectors
              if (FileSize > 0) and (DiskFile.Position + DataSize > FileSize) then
              begin
                Messages.Add(SysUtils.Format('Side %d track %d sector %d ran past the end of the file.',
                  [SIdx, TIdx, EIdx]));
                Corrupt := True;
                // The position can already be past the end, from the skip below
                // stepping over a record that overran the buffer. A negative
                // remainder assigned into a word wraps to tens of kilobytes, and
                // the read that followed asked for far more than was ever there.
                BytesLeft := FileSize - DiskFile.Position;
                if BytesLeft < 0 then
                  BytesLeft := 0;
                DataSize := BytesLeft;
              end;

              if DataSize > 0 then
                DiskFile.ReadBuffer(Data, DataSize);

              // Keep the stream aligned when a record on disk exceeded our
              // buffer, stopping at the end of the file rather than seeking off
              // the end of it and leaving every later check to compare against a
              // position the file does not reach
              if AdvertisedSize > DataSize then
              begin
                SkipTo := DiskFile.Position + (AdvertisedSize - DataSize);
                if (FileSize > 0) and (SkipTo > FileSize) then
                  SkipTo := FileSize;
                DiskFile.Position := SkipTo;
              end;
            end;
        end;
      end;
    end;
  end;

  // Said once for the image rather than per track: a writer that gets these
  // wrong gets them wrong everywhere, and the tracks are still readable
  if UnknownTrackModes then
    Messages.Add('Track data rate or recording mode held a value the format does not define; shown as unknown.');

  if RecoveredTracks > 0 then
    Messages.Add(SysUtils.Format(
      'Extended DSK track-size table was missing; recovered %d track(s) by scanning',
      [RecoveredTracks]));

  if (FileFormat = diExtendedDSK) and (DiskFile.Position < DiskFile.Size) then
  begin
    if DiskFile.Size - DiskFile.Position < SizeOf(OFFInfoBlock) then
    begin
      Messages.Add('Offset-Info marker is truncated.');
      Corrupt := True;
      exit;
    end;
    DiskFile.ReadBuffer(OFFInfoBlock, SizeOf(OFFInfoBlock));
    if (OFFInfoBlock.OFF_Marker = DiskSectorOffsetBlock) then
    begin
      for TIdx := 0 to DSKInfoBlock.Disk_NumTracks - 1 do
        for SIdx := 0 to DSKInfoBlock.Disk_NumSides - 1 do
        begin
          Track := Disk.Side[SIdx].Track[TIdx];
          if DiskFile.Size - DiskFile.Position <
            SizeOf(OFFTrackEntry) + Track.Sectors * SizeOf(word) then
          begin
            Messages.Add(SysUtils.Format('Side %d track %d Offset-Info entries are truncated.', [SIdx, TIdx]));
            Corrupt := True;
            exit;
          end;
          DiskFile.ReadBuffer(OFFTrackEntry, SizeOf(OFFTrackEntry));
          Track.BitLength := OFFTrackEntry.OFF_TrackLength;
          for EIdx := 0 to Track.Sectors - 1 do
            Track.Sector[EIdx].IndexPointOffset := DiskFile.ReadWord;
        end;
    end;
  end;
  Result := True;
end;

// Load a raw MGT/SAM image: a headerless dump of 2 sides x 80 tracks x 10
// sectors x 512 bytes. Sides are stored successively (all of side 0, then all
// of side 1); each track holds sectors 1..10 in order, 512 bytes each.
function TDSKImage.LoadFileMGT(DiskFile: TStream): boolean;
const
  MGTSides = 2;
  MGTTracks = 80;
  MGTSectorsPerTrack = 10;
  MGTSectorSize = 512;
  MGTFirstSectorID = 1;
  MGTFDCSize = 2;     // FDC size code for 512-byte sectors
  MGTGapLength = $17; // standard MGT/+3 format gap
var
  SIdx, TIdx, EIdx: integer;
begin
  Result := False;

  Disk.Sides := MGTSides;
  for SIdx := 0 to MGTSides - 1 do
  begin
    Disk.Side[SIdx].Side := SIdx;
    Disk.Side[SIdx].Tracks := MGTTracks;
  end;

  for SIdx := 0 to MGTSides - 1 do
    for TIdx := 0 to MGTTracks - 1 do
      with Disk.Side[SIdx].Track[TIdx] do
      begin
        Track := TIdx;
        Side := SIdx;
        // SAM/+D number side-1 tracks as physical track + 128, which is how the
        // directory's start-track byte is encoded; mirror it so GetLogicalTrack
        // resolves files on either side.
        Logical := (SIdx * 128) + TIdx;
        Sectors := MGTSectorsPerTrack;
        SectorSize := MGTSectorSize;
        Filler := 0;
        GapLength := MGTGapLength;

        for EIdx := 0 to MGTSectorsPerTrack - 1 do
          with Sector[EIdx] do
          begin
            Sector := EIdx;
            Track := TIdx;
            Side := SIdx;
            ID := MGTFirstSectorID + EIdx;
            FDCSize := MGTFDCSize;
            FDCStatus[1] := 0;
            FDCStatus[2] := 0;
            DataSize := MGTSectorSize;
            AdvertisedSize := MGTSectorSize;
            DiskFile.ReadBuffer(Data, MGTSectorSize);
          end;
      end;

  Result := True;
end;

// Load a Teledisk image. The header is always plain, and everything after it
// is LZHUF-compressed when the signature is 'td'. Tracks come as records in
// whatever order they were read, so the disk grows to take each one and the
// track numbering is settled once they are all in.
function TDSKImage.LoadFileTD0(DiskFile: TStream): boolean;
const
  // Teledisk records neither, so a track gets what a +3/PCW format writes
  TD0Filler = $E5;
  TD0GapLength = $4E;
var
  Header: TTD0Header;
  CommentHeader: TTD0CommentHeader;
  TrackHeader: TTD0TrackHeader;
  SectorHeader: TTD0SectorHeader;
  Body: TStream;
  Unpacked: TMemoryStream;
  CommentText: ansistring;
  Field: array of byte;
  FieldLength: word;
  SIdx, TIdx, EIdx, Head, Size, CRCBad, Unreadable, LoadedSectors: integer;
  TD0Track: TDSKTrack;
  DiskFM, Ended: boolean;

  // Take Count bytes from the body, or answer False if it has not got them
  function Fetch(var Buf; Count: integer): boolean;
  begin
    Result := Body.Position + Count <= Body.Size;
    if Result and (Count > 0) then
      Body.ReadBuffer(Buf, Count);
  end;

  procedure Fail(const Reason: string);
  begin
    Messages.Add(Reason);
    Corrupt := True;
  end;

begin
  Result := False;
  DiskFile.ReadBuffer(Header, SizeOf(Header));
  Creator := SysUtils.Format('Teledisk %d.%d', [Header.Version div 10, Header.Version mod 10]);

  // One file of a multi-volume set is only part of a disk
  if Header.Sequence <> 0 then
  begin
    Fail(SysUtils.Format('This is volume %d of a multi-volume Teledisk set, which cannot be loaded.',
      [Header.Sequence + 1]));
    exit;
  end;

  if (Header.Signature = TD0SignatureAdvanced) and (Header.Version < TD0VersionLZHuf) then
  begin
    Fail(SysUtils.Format('Teledisk %d.%d advanced compression is not supported.',
      [Header.Version div 10, Header.Version mod 10]));
    exit;
  end;

  Unpacked := nil;
  try
    if Header.Signature = TD0SignatureAdvanced then
    begin
      Unpacked := TMemoryStream.Create;
      try
        LZHufDecompress(DiskFile, Unpacked);
      except
        on E: Exception do
        begin
          Fail('Compressed data could not be unpacked: ' + E.Message);
          exit;
        end;
      end;
      Unpacked.Position := 0;
      Body := Unpacked;
    end
    else
      Body := DiskFile;

    if (Header.Stepping and TD0StepHasComment) <> 0 then
    begin
      if not Fetch(CommentHeader, SizeOf(CommentHeader)) then
      begin
        Fail('Comment ran past the end of the file.');
        exit;
      end;
      SetLength(CommentText, CommentHeader.Length);
      if not Fetch(PAnsiChar(CommentText)^, CommentHeader.Length) then
      begin
        Fail('Comment ran past the end of the file.');
        exit;
      end;
      if TD0Crc(PAnsiChar(CommentText)^, Length(CommentText),
        TD0Crc(CommentHeader.Length, SizeOf(CommentHeader) - SizeOf(CommentHeader.CRC))) <> CommentHeader.CRC then
        Messages.Add('Comment failed its CRC check.');
      // Each line of the comment ends with a NUL
      Comment := StringReplace(TrimRight(StringReplace(CommentText, #0, #10, [rfReplaceAll])),
        #10, LineEnding, [rfReplaceAll]);
    end;

    if (Header.Stepping and TD0StepMask) = 1 then
      Messages.Add('Imaged double-stepped, as a 40-track disk in an 80-track drive.')
    else if (Header.Stepping and TD0StepMask) = 2 then
      Messages.Add('Imaged stepping even tracks only.');

    DiskFM := (Header.DataRate and TD0RateFM) <> 0;
    // Teledisk gives 1 or 2; anything else is taken from the tracks themselves
    Disk.Sides := EnsureRange(Header.Sides, 1, 2);
    CRCBad := 0;
    Unreadable := 0;
    LoadedSectors := 0;
    Ended := False;

    while not Ended do
    begin
      if not Fetch(TrackHeader, 1) then
      begin
        Fail('Image ended without its end-of-image marker.');
        break;
      end;
      if TrackHeader.Sectors = TD0EndOfImage then
      begin
        Ended := True;
        break;
      end;
      if not Fetch(TrackHeader.Cylinder, SizeOf(TrackHeader) - 1) then
      begin
        Fail('Track header ran past the end of the file.');
        break;
      end;
      if Byte(TD0Crc(TrackHeader, 3)) <> TrackHeader.CRC then
        Messages.Add(SysUtils.Format('Track header for cylinder %d head %d failed its CRC check.',
          [TrackHeader.Cylinder, TrackHeader.Head and 1]));

      // A side has at most 255 tracks
      if TrackHeader.Cylinder = 255 then
      begin
        Fail('Track header gave cylinder 255, past the last a side can hold.');
        break;
      end;

      // A TD0 track has no DSK-style 29-sector limit, but every declared
      // sector would allocate a full buffer, even when it has no data field.
      // Count repeated tracks too: they are freed and rebuilt on every record.
      if TrackHeader.Sectors > MaxImageSectors - LoadedSectors then
      begin
        Fail(SysUtils.Format('Image declares more than %d sectors; load stopped.', [MaxImageSectors]));
        break;
      end;
      // Before allocating the track's sectors, ensure at least their six-byte
      // headers are present. Data fields need additional bytes and are checked
      // individually below.
      if Body.Size - Body.Position < int64(TrackHeader.Sectors) * SizeOf(SectorHeader) then
      begin
        Fail(SysUtils.Format('Cylinder %d sector headers ran past the end of the file.',
          [TrackHeader.Cylinder]));
        break;
      end;
      Inc(LoadedSectors, TrackHeader.Sectors);

      Head := TrackHeader.Head and 1;
      if Head >= Disk.Sides then
        Disk.Sides := Head + 1;
      if TrackHeader.Cylinder >= Disk.Side[Head].Tracks then
        Disk.Side[Head].Tracks := TrackHeader.Cylinder + 1;

      TD0Track := Disk.Side[Head].Track[TrackHeader.Cylinder];
      if TD0Track.Sectors > 0 then
      begin
        Messages.Add(SysUtils.Format('Cylinder %d head %d appears more than once; the last is kept.',
          [TrackHeader.Cylinder, Head]));
        TD0Track.Sectors := 0;
      end;

      TD0Track.Filler := TD0Filler;
      TD0Track.GapLength := TD0GapLength;
      case Header.DataRate and TD0RateMask of
        TD0Rate500: TD0Track.DataRate := drHighDensity;
        else
          TD0Track.DataRate := drSingleOrDoubleDensity;
      end;
      if DiskFM or ((TrackHeader.Head and TD0HeadFM) <> 0) then
        TD0Track.RecordingMode := rmFM
      else
        TD0Track.RecordingMode := rmMFM;
      TD0Track.Sectors := TrackHeader.Sectors;

      for EIdx := 0 to TrackHeader.Sectors - 1 do
        with TD0Track.Sector[EIdx] do
        begin
          if not Fetch(SectorHeader, SizeOf(SectorHeader)) then
          begin
            Fail(SysUtils.Format('Cylinder %d head %d sector %d ran past the end of the file.',
              [TrackHeader.Cylinder, Head, EIdx]));
            TD0Track.Sectors := EIdx;
            exit;
          end;

          Sector := EIdx;
          Track := SectorHeader.Cylinder;
          Side := SectorHeader.Head;
          ID := SectorHeader.ID;
          FDCSize := SectorHeader.Size;

          // Teledisk's flags as the status the controller would have given
          if (SectorHeader.Flags and TD0FlagCRCError) <> 0 then
          begin
            FDCStatus[1] := FDCStatus[1] or $20;
            FDCStatus[2] := FDCStatus[2] or $20;
          end;
          if (SectorHeader.Flags and TD0FlagDeleted) <> 0 then
            FDCStatus[2] := FDCStatus[2] or $40;
          if (SectorHeader.Flags and (TD0FlagsWithoutData or TD0FlagNoID)) <> 0 then
          begin
            FDCStatus[1] := FDCStatus[1] or $01;
            if (SectorHeader.Flags and TD0FlagsWithoutData) <> 0 then
              FDCStatus[2] := FDCStatus[2] or $01;
          end;

          DataSize := 0;
          if (SectorHeader.Flags and TD0FlagsWithoutData) = 0 then
          begin
            if not Fetch(FieldLength, SizeOf(FieldLength)) or (FieldLength = 0) then
            begin
              Fail(SysUtils.Format('Cylinder %d head %d sector ID %d data ran past the end of the file.',
                [TrackHeader.Cylinder, Head, ID]));
              TD0Track.Sectors := EIdx;
              exit;
            end;
            FieldLength := LEtoN(FieldLength);
            SetLength(Field, FieldLength);
            if not Fetch(Field[0], FieldLength) then
            begin
              Fail(SysUtils.Format('Cylinder %d head %d sector ID %d data ran past the end of the file.',
                [TrackHeader.Cylinder, Head, ID]));
              TD0Track.Sectors := EIdx;
              exit;
            end;

            Size := GetFDCSizeBytes(SectorHeader.Size);
            if Size = 0 then
              Inc(Unreadable)
            else if not DecodeTD0SectorData(Copy(Field, 1, FieldLength - 1), Field[0], Data, Size, TD0Filler) then
            begin
              Messages.Add(SysUtils.Format('Cylinder %d head %d sector ID %d data could not be decoded.',
                [TrackHeader.Cylinder, Head, ID]));
              Corrupt := True;
            end
            else
            begin
              DataSize := Size;
              if Byte(TD0Crc(Data, Size)) <> SectorHeader.CRC then
                Inc(CRCBad);
            end;
          end;
          AdvertisedSize := DataSize;
        end;
    end;

    if CRCBad > 0 then
      Messages.Add(SysUtils.Format('%d sector(s) did not match the CRC Teledisk recorded for their data.', [CRCBad]));
    if Unreadable > 0 then
      Messages.Add(SysUtils.Format('%d sector(s) had a size code with no size, so their data was dropped.', [Unreadable]));
  finally
    Unpacked.Free;

    // Every side takes the same count of tracks, however many each record
    // reached, and the numbering follows once the side count is known
    TIdx := 0;
    for SIdx := 0 to Disk.Sides - 1 do
      TIdx := Max(TIdx, Disk.Side[SIdx].Tracks);
    for SIdx := 0 to Disk.Sides - 1 do
    begin
      Disk.Side[SIdx].Tracks := TIdx;
      for EIdx := 0 to TIdx - 1 do
        with Disk.Side[SIdx].Track[EIdx] do
        begin
          Track := EIdx;
          Side := SIdx;
          Logical := (EIdx * Disk.Sides) + SIdx;
        end;
    end;
  end;

  Result := Ended and not Corrupt;
end;

function TDSKImage.SaveFile(SaveFileName: TFileName; SaveFileFormat: TDSKImageFormat; Copy: boolean; Compress: boolean): boolean;
var
  DiskFile: TFileStream;
  FileSize: int64;
  TempFileName: string;
  WideTempName, WideSaveName: WideString;
begin
  Result := False;
  if Corrupt then
  begin
    MessageDlg('Image is corrupt. Save aborted.', mtError, [mbOK], 0);
    exit;
  end;

  // Keep the output beside the destination so the final replacement stays on
  // the same volume. GetTempFileName reserves a unique name for this save.
  TempFileName := GetTempFileName(ExtractFilePath(ExpandFileName(SaveFileName)), 'DIM');
  try
    DiskFile := TFileStream.Create(TempFileName, fmCreate or fmOpenWrite);
    try
      case SaveFileFormat of
        diStandardDSK: Result := SaveFileDSK(DiskFile, diStandardDSK, False);
        diExtendedDSK: Result := SaveFileDSK(DiskFile, diExtendedDSK, Compress);
        diRawMGT: Result := SaveFileMGT(DiskFile);
        diTeleDisk: Result := SaveFileTD0(DiskFile);
        else
          MessageDlg(SysUtils.Format('Unknown file format %i', [SaveFileFormat]), mtError, [mbOK], 0);
      end;

      FileSize := DiskFile.Size;
    finally
      DiskFile.Free;
    end;

    if Result then
    begin
      // RenameFile cannot replace an existing target on Windows. MoveFileExW
      // replaces it in one same-volume operation and keeps Unicode paths intact.
      WideTempName := UTF8Decode(TempFileName);
      WideSaveName := UTF8Decode(SaveFileName);
      if not Windows.MoveFileExW(PWideChar(WideTempName), PWideChar(WideSaveName),
        MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then
        RaiseLastOSError;
    end;
  finally
    // Also runs for exceptions in the writer or in the final replacement.
    SysUtils.DeleteFile(TempFileName);
  end;

  if not Result then
    MessageDlg('Could not save file. Save aborted.', mtError, [mbOK], 0)
  else
  if not Copy then
  begin
    FIsChanged := False;
    FileName := SaveFileName;
    Self.FileFormat := SaveFileFormat;
    Self.FileSize := FileSize;
  end;
end;

function TDSKImage.CanSave(SaveFileFormat: TDSKImageFormat): boolean;
var
  Side: TDSKSide;
  Track: TDSKTrack;
  Sector: TDSKSector;
begin
  Result := False;

  if Disk.Sides = 0 then
  begin
    Messages.Add('Disk has no sides to write.');
    exit;
  end;

  // Neither DSK format has anywhere to say that one side holds more tracks than
  // another: there is a single track count for the whole disk. It was taken
  // from side 0 and then used to index every side, so a side with fewer tracks
  // than the first was read past the end of, and whatever that found was
  // written into the file as a track.
  for Side in Disk.Side do
    if Side.Tracks <> Disk.Side[0].Tracks then
    begin
      Messages.Add(SysUtils.Format(
        'Side %d has %d tracks and side 0 has %d. The format gives the whole disk one track count.',
        [Side.Side, Side.Tracks, Disk.Side[0].Tracks]));
      exit;
    end;

  // Teledisk works out how much data a sector has from its size code alone, so
  // a sector holding data under a code that gives no size cannot be written
  if SaveFileFormat = diTeleDisk then
  begin
    for Side in Disk.Side do
      for Track in Side.Track do
        for Sector in Track.Sector do
          if (Sector.DataSize > 0) and (Sector.FDCSize > TD0MaxSizeCode) then
          begin
            Messages.Add(SysUtils.Format('Side %d track %d sector ID %d has size code %d, which gives no size to write its data as.',
              [Track.Side, Track.Logical, Sector.ID, Sector.FDCSize]));
            exit;
          end;
    Result := True;
    exit;
  end;

  for Side in Disk.Side do
    for Track in Side.Track do
    begin
      // Both formats describe a track's sectors in its Track-Info block, which
      // has only so many entries. The track properties window will set a sector
      // count well past that, and writing one would run off the end of the block.
      if Track.Sectors > MaxTrackInfoSectors then
      begin
        Messages.Add(SysUtils.Format('Side %d track %d has %d sectors, more than the %d a track holds.',
          [Track.Side, Track.Logical, Track.Sectors, MaxTrackInfoSectors]));
        exit;
      end;

      // A header records a track's size in 256-byte blocks, in one byte per
      // track for extended and one word for the whole disk for standard, so a
      // track past that cannot be described in either
      if GetTrackFileSize(Track.Size) > MaxTrackFileSize then
      begin
        Messages.Add(SysUtils.Format('Side %d track %d holds %d bytes, more than the %d a track can be described as.',
          [Track.Side, Track.Logical, Track.Size, MaxTrackFileSize - TrackBlockSize]));
        exit;
      end;
    end;

  // One track size byte per track per side has to fit the header, and there is
  // no honest way to write a disk bigger than that: dropping the tracks that do
  // not fit would quietly lose them
  if (SaveFileFormat = diExtendedDSK) and
    (Disk.Side[0].Tracks * Disk.Sides > MaxTracks) then
  begin
    Messages.Add(SysUtils.Format('%d tracks over %d sides needs %d track sizes, more than the %d a header holds.',
      [Disk.Side[0].Tracks, Disk.Sides, Disk.Side[0].Tracks * Disk.Sides, MaxTracks]));
    exit;
  end;

  Result := True;
end;

// Pad a track out to the size its header gives, with the byte the track is
// filled with so the padding looks like the rest of the unused track
procedure WriteFiller(DiskFile: TFileStream; Count: integer; Filler: byte);
var
  Block: array[0..TrackBlockSize - 1] of byte;
  Chunk: integer;
begin
  if Count <= 0 then exit;
  FillChar(Block, SizeOf(Block), Filler);
  while Count > 0 do
  begin
    Chunk := Count;
    if Chunk > SizeOf(Block) then Chunk := SizeOf(Block);
    DiskFile.WriteBuffer(Block, Chunk);
    Dec(Count, Chunk);
  end;
end;

// Save a DSK file
function TDSKImage.SaveFileDSK(DiskFile: TFileStream; SaveFileFormat: TDSKImageFormat; Compress: boolean): boolean;
var
  DSKInfoBlock: TDSKInfoBlock;
  TRKInfoBlock: TTRKInfoBlock;
  SCTInfoBlock: TSCTInfoBlock;
  OFFInfoBlock: TOFFInfoBlock;
  SIdx, TIdx, EIdx: integer;
  Side: TDSKSide;
  Track: TDSKTrack;
begin
  Result := False;
  FillChar(DSKInfoBlock, SizeOf(DSKInfoBlock), 0);

  if not CanSave(SaveFileFormat) then exit;

  // Construct disk info
  with DSKInfoBlock do
  begin
    Disk_NumTracks := Disk.Side[0].Tracks;
    Disk_NumSides := Disk.Sides;
    Move(CreatorSig, Disk_Creator, Length(CreatorSig));
    case SaveFileFormat of
      diExtendedDSK:
      begin
        DiskInfoBlock := DiskInfoExtended;
        // One track size byte per track per side has to fit the header, and
        // there is no honest way to write a disk bigger than that: dropping
        // the tracks that do not fit would quietly lose them
        // The track size table is checked to fit in CanSave above

        for SIdx := 0 to Disk_NumSides - 1 do
          for TIdx := 0 to Disk_NumTracks - 1 do
            if (Compress and (Disk.Side[SIdx].Track[TIdx].Sectors = 0)) then
              Disk_ExtTrackSize[(TIdx * Disk_NumSides) + SIdx] := 0
            else
            if Disk.Side[SIdx].Track[TIdx].Size > 0 then
              Disk_ExtTrackSize[(TIdx * Disk_NumSides) + SIdx] :=
                GetTrackFileSize(Disk.Side[SIdx].Track[TIdx].Size) div TrackBlockSize
            else
              Disk_ExtTrackSize[(TIdx * Disk_NumSides) + SIdx] := 0;
      end;
      else
      begin
        DiskInfoBlock := DiskInfoStandard;
        // A standard image gives every track the one size, so the largest track
        // has to set it. Track.Size counts only sector data where the header's
        // size also counts the Track-Info block, and comparing the two straight
        // let a track larger than the first go unnoticed and be written past
        // where the header said the next one starts.
        Disk_StdTrackSize := 0;
        for SIdx := 0 to Disk_NumSides - 1 do
          for TIdx := 0 to Disk_NumTracks - 1 do
          begin
            Track := Disk.Side[SIdx].Track[TIdx];
            Track.DataRate := drUnknown;
            Track.RecordingMode := rmUnknown;
            if (Track.Size > 0) and (GetTrackFileSize(Track.Size) > Disk_StdTrackSize) then
              Disk_StdTrackSize := GetTrackFileSize(Track.Size);
          end;
      end;
    end;
  end;

  DiskFile.WriteBuffer(DSKInfoBlock, SizeOf(DSKInfoBlock));

  for TIdx := 0 to DSKInfoBlock.Disk_NumTracks - 1 do
    for Side in Disk.Side do
    begin
      with Side.Track[TIdx] do
      begin
        // Set various track info properties
        FillChar(TRKInfoBlock, SizeOf(TRKInfoBlock), 0);
        with TRKInfoBlock do
        begin
          TrackData := DiskInfoTrack;
          TIB_TrackNum := Track;
          TIB_SideNum := Side;
          TIB_NumSectors := Sectors;
          TIB_SectorSize := GetFDCSectorSize(SectorSize);
          TIB_GapLength := GapLength;
          TIB_FillerByte := Filler;
          // Extended V5 support for data rate and recording mode
          if SaveFileFormat = diExtendedDSK then
          begin
            TIB_DataRate := Ord(DataRate);
            TIB_RecordingMode := Ord(RecordingMode);
          end;
        end;

        // Write tracks
        if Size > 0 then
        begin
          // Write sector info out
          for EIdx := 0 to Sectors - 1 do
            with Sector[EIdx] do
            begin
              FillChar(SCTInfoBlock, SizeOf(SCTInfoBlock), 0);
              with SCTInfoBlock do
              begin
                SIB_TrackNum := Track;
                SIB_SideNum := Side;
                SIB_ID := ID;
                SIB_Size := FDCSize;
                SIB_FDC1 := FDCStatus[1];
                SIB_FDC2 := FDCStatus[2];
                if (SaveFileFormat = diExtendedDSK) then
                  SIB_DataLength := DataSize;
              end;
              Move(SCTInfoBlock, TRKInfoBlock.SectorInfoList[EIdx * SizeOf(SCTInfoBlock)], SizeOf(SCTInfoBlock));
            end;

          DiskFile.WriteBuffer(TRKInfoBlock, SizeOf(TRKInfoBlock));

          // Now write actual sector data
          for EIdx := 0 to Sectors - 1 do
            DiskFile.WriteBuffer(Sector[EIdx].Data, Sector[EIdx].DataSize);

          // The size a header gives a track is a promise about where the next
          // one starts, and it is made in whole 256-byte blocks. Writing only
          // the sectors broke that promise for any track that did not fill its
          // last block, leaving every track after it at the wrong offset.
          if SaveFileFormat = diStandardDSK then
            WriteFiller(DiskFile, DSKInfoBlock.Disk_StdTrackSize - TrackBlockSize - Size, Filler)
          else
            WriteFiller(DiskFile, GetTrackFileSize(Size) - TrackBlockSize - Size, Filler);
        end
        else
        if (SaveFileFormat = diStandardDSK) and (DSKInfoBlock.Disk_StdTrackSize > 0) then
        begin
          // A standard image has no way to say a track is not there: they all
          // take the header's size, so an unformatted one still has to fill it
          DiskFile.WriteBuffer(TRKInfoBlock, SizeOf(TRKInfoBlock));
          WriteFiller(DiskFile, DSKInfoBlock.Disk_StdTrackSize - TrackBlockSize, Filler);
        end;
      end;
    end;

  if (SaveFileFormat = diExtendedDSK) and (HasOffsetInfo) then
  begin
    FillChar(OFFInfoBlock, SizeOf(OFFInfoBlock), 0);
    OFFInfoBlock.OFF_Marker := DiskSectorOffsetBlock;
    DiskFile.WriteBuffer(OFFInfoBlock, SizeOf(OFFInfoBlock));
    for TIdx := 0 to DSKInfoBlock.Disk_NumTracks - 1 do
      for Side in Disk.Side do
      begin
        Track := Side.Track[TIdx];
        DiskFile.WriteWord(Track.BitLength);
        for EIdx := 0 to Track.Sectors - 1 do
          DiskFile.WriteWord(Track.Sector[EIdx].IndexPointOffset);
      end;
    DiskFile.WriteByte(0); // Not in the spec but in the SAMdisk images
  end;

  Result := True;
end;

// Save a raw MGT/SAM image: a headerless dump of 2 sides x 80 tracks x 10
// sectors x 512 bytes, sides stored successively (all of side 0, then all of
// side 1). Sectors are written in ID order 1..10; anything missing is written
// as 512 filler bytes so the file is always exactly MGTRawSize.
function TDSKImage.SaveFileMGT(DiskFile: TFileStream): boolean;
const
  MGTSides = 2;
  MGTTracks = 80;
  MGTSectorsPerTrack = 10;
  MGTSectorSize = 512;
  MGTFirstSectorID = 1;
var
  SIdx, TIdx, SectorID, ByteIdx: integer;
  Blank: array[0..MGTSectorSize - 1] of byte;
  Sector: TDSKSector;
  Track: TDSKTrack;
begin
  FillChar(Blank, SizeOf(Blank), 0);

  for SIdx := 0 to MGTSides - 1 do
    for TIdx := 0 to MGTTracks - 1 do
    begin
      Track := nil;
      if (SIdx < Disk.Sides) and (TIdx < Disk.Side[SIdx].Tracks) then
        Track := Disk.Side[SIdx].Track[TIdx];

      for SectorID := MGTFirstSectorID to MGTFirstSectorID + MGTSectorsPerTrack - 1 do
      begin
        Sector := nil;
        if Track <> nil then
          Sector := Track.GetLogicalSectorByID(SectorID);

        if (Sector <> nil) and (Sector.DataSize >= MGTSectorSize) then
          DiskFile.WriteBuffer(Sector.Data, MGTSectorSize)
        else if Sector <> nil then
        begin
          // Short sector: write what we have, then pad to 512.
          DiskFile.WriteBuffer(Sector.Data, Sector.DataSize);
          for ByteIdx := Sector.DataSize to MGTSectorSize - 1 do
            DiskFile.WriteByte(0);
        end
        else
          DiskFile.WriteBuffer(Blank, MGTSectorSize);
      end;
    end;

  Result := True;
end;

// Save a Teledisk image with advanced compression. Teledisk has no room for a
// track's gap, filler, index offsets or bit length, nor for more than one copy
// of a sector, and it sizes every sector from its size code: what does not fit
// is said in Messages rather than refused, as the Standard DSK save does.
function TDSKImage.SaveFileTD0(DiskFile: TFileStream): boolean;
var
  Header: TTD0Header;
  CommentHeader: TTD0CommentHeader;
  TrackHeader: TTD0TrackHeader;
  SectorHeader: TTD0SectorHeader;
  Payload, Compressed: TMemoryStream;
  CommentText: ansistring;
  Buffer: array[0..MaxSectorSize] of byte;
  SIdx, TIdx, Size, CopySize: integer;
  Track, FirstTrack: TDSKTrack;
  Sector: TDSKSector;
  AllFM, DroppedCopies, Padded, Truncated: boolean;
  Year, Month, Day, Hour, Minute, Second, MilliSecond: word;
  Stamp: TDateTime;
begin
  Result := False;
  if not CanSave(diTeleDisk) then exit;

  AllFM := True;
  FirstTrack := nil;
  for Track in Disk.AllTracks do
    if Track.Sectors > 0 then
    begin
      if FirstTrack = nil then FirstTrack := Track;
      if Track.RecordingMode <> rmFM then AllFM := False;
    end;
  if FirstTrack = nil then AllFM := False;

  DroppedCopies := False;
  Padded := False;
  Truncated := False;

  Payload := TMemoryStream.Create;
  Compressed := TMemoryStream.Create;
  try
    if Comment <> '' then
    begin
      // One NUL-terminated line per line of the comment
      CommentText := StringReplace(AdjustLineBreaks(Comment, tlbsLF), #10, #0, [rfReplaceAll]) + #0;
      Stamp := Now;
      DecodeDate(Stamp, Year, Month, Day);
      DecodeTime(Stamp, Hour, Minute, Second, MilliSecond);
      CommentHeader.Length := NtoLE(word(Length(CommentText)));
      CommentHeader.Year := Year - 1900;
      CommentHeader.Month := Month - 1;
      CommentHeader.Day := Day;
      CommentHeader.Hour := Hour;
      CommentHeader.Minute := Minute;
      CommentHeader.Second := Second;
      CommentHeader.CRC := NtoLE(TD0Crc(PAnsiChar(CommentText)^, Length(CommentText),
        TD0Crc(CommentHeader.Length, SizeOf(CommentHeader) - SizeOf(CommentHeader.CRC))));
      Payload.WriteBuffer(CommentHeader, SizeOf(CommentHeader));
      Payload.WriteBuffer(PAnsiChar(CommentText)^, Length(CommentText));
    end;

    for TIdx := 0 to Disk.Side[0].Tracks - 1 do
      for SIdx := 0 to Disk.Sides - 1 do
      begin
        Track := Disk.Side[SIdx].Track[TIdx];
        TrackHeader.Sectors := Track.Sectors;
        TrackHeader.Cylinder := TIdx;
        TrackHeader.Head := SIdx;
        if (Track.RecordingMode = rmFM) and not AllFM then
          TrackHeader.Head := TrackHeader.Head or TD0HeadFM;
        TrackHeader.CRC := Byte(TD0Crc(TrackHeader, 3));
        Payload.WriteBuffer(TrackHeader, SizeOf(TrackHeader));

        for Sector in Track.Sector do
        begin
          SectorHeader.Cylinder := Sector.Track;
          SectorHeader.Head := Sector.Side;
          SectorHeader.ID := Sector.ID;
          SectorHeader.Size := Sector.FDCSize;
          SectorHeader.Flags := 0;
          SectorHeader.CRC := 0;
          if ((Sector.FDCStatus[1] and $20) <> 0) or ((Sector.FDCStatus[2] and $20) <> 0) then
            SectorHeader.Flags := SectorHeader.Flags or TD0FlagCRCError;
          if (Sector.FDCStatus[2] and $40) <> 0 then
            SectorHeader.Flags := SectorHeader.Flags or TD0FlagDeleted;

          // A missing address mark on a sector that has data is its ID that
          // was not found
          if ((Sector.FDCStatus[1] and $01) <> 0) and (Sector.DataSize > 0) then
            SectorHeader.Flags := SectorHeader.Flags or TD0FlagNoID;

          if Sector.DataSize = 0 then
          begin
            SectorHeader.Flags := SectorHeader.Flags or TD0FlagNoData;
            Payload.WriteBuffer(SectorHeader, SizeOf(SectorHeader));
            continue;
          end;

          // The size code says how much there is, and a weak sector's first
          // copy is the one a controller reading it would most likely give
          Size := GetFDCSizeBytes(Sector.FDCSize);
          if Sector.GetCopyCount > 1 then
          begin
            DroppedCopies := True;
            CopySize := Sector.GetCopySize;
          end
          else
            CopySize := Sector.DataSize;
          if CopySize < Size then Padded := True;
          if CopySize > Size then
          begin
            Truncated := True;
            CopySize := Size;
          end;
          FillChar(Buffer, Size, Track.Filler);
          Move(Sector.Data, Buffer, CopySize);

          SectorHeader.CRC := Byte(TD0Crc(Buffer, Size));
          Payload.WriteBuffer(SectorHeader, SizeOf(SectorHeader));
          EncodeTD0SectorData(Payload, Buffer, Size);
        end;
      end;

    Payload.WriteByte(TD0EndOfImage);

    Payload.Position := 0;
    LZHufCompress(Payload, Compressed);

    FillChar(Header, SizeOf(Header), 0);
    Header.Signature := TD0SignatureAdvanced;
    Header.CheckSig := Random(256);
    Header.Version := TD0VersionWritten;
    Header.DataRate := TD0Rate250;
    if (FirstTrack <> nil) and (FirstTrack.DataRate in [drHighDensity, drExtendedDensity]) then
      Header.DataRate := TD0Rate500;
    if AllFM then
      Header.DataRate := Header.DataRate or TD0RateFM;
    // The drive the disk was read in: 5.25" 360K, 3.5" 720K or 3.5" 1.44M
    if Header.DataRate and TD0RateMask = TD0Rate500 then
      Header.DriveType := 4
    else if Disk.Side[0].Tracks <= 42 then
      Header.DriveType := 1
    else
      Header.DriveType := 3;
    if Comment <> '' then
      Header.Stepping := TD0StepHasComment;
    Header.Sides := Disk.Sides;
    Header.CRC := NtoLE(TD0Crc(Header, 10));

    DiskFile.WriteBuffer(Header, SizeOf(Header));
    Compressed.Position := 0;
    DiskFile.CopyFrom(Compressed, Compressed.Size);
  finally
    Compressed.Free;
    Payload.Free;
  end;

  if DroppedCopies then
    Messages.Add('Teledisk holds one copy of a sector; weak sectors kept only their first.');
  if Padded then
    Messages.Add('Sectors shorter than their size code were padded with the track filler.');
  if Truncated then
    Messages.Add('Sectors longer than their size code were cut to it.');

  Result := True;
end;

// Disk                                                  .
constructor TDSKDisk.Create(ParentImage: TDSKImage);
begin
  inherited Create;
  FParentImage := ParentImage;
  FSpecification := TDSKSpecification.Create(Self);
end;

destructor TDSKDisk.Destroy;
begin
  SetSides(0);
  FParentImage := nil;
  FSpecification.Free;
  inherited Destroy;
end;

function TDSKDisk.GetSectorByBlock(Block: integer): TDSKSector;
var
  TargetOffset, Offset: integer;
  Sector: TDSKSector;
  Track: TDSKTrack;
begin
  Result := nil;

  // In theory blocks should be a multiple of sectors
  TargetOffset := Block * Specification.GetBlockSize();

  Offset := 0;
  Track := GetLogicalTrack(Specification.ReservedTracks);
  if Track = nil then exit;
  Sector := Track.GetFirstLogicalSector();

  while (Sector <> nil) and (Offset + Sector.GetCopySize <= TargetOffset) do
  begin
    Offset := Offset + Sector.GetCopySize;
    Sector := GetNextLogicalSector(Sector);
  end;

  Result := Sector;
end;

constructor TDSKDirEntryEnumerator.Create(ADisk: TDSKDisk; AStart: TDSKSector;
  AEntrySize, AMaxEntries: integer);
begin
  inherited Create;
  FDisk := ADisk;
  FSector := AStart;
  FEntrySize := AEntrySize;
  FMaxEntries := AMaxEntries;
  FOffset := 0;
  FIndex := 0;
  FStarted := False;
end;

function TDSKDirEntryEnumerator.MoveNext: boolean;
begin
  // The first call yields entry 0; later calls step on by one entry, so the
  // sector-boundary check below sees the same offsets the hand-rolled loops did
  if FStarted then
  begin
    Inc(FIndex);
    FOffset := FOffset + FEntrySize;
  end
  else
    FStarted := True;

  Result := False;
  if (FSector = nil) or (FIndex >= FMaxEntries) then exit;

  // Cross into the next logical sector when this one has no room left for a
  // whole entry; the directory can run off the end of a truncated image
  if FOffset + FEntrySize > FSector.GetCopySize then
  begin
    FSector := FDisk.GetNextLogicalSector(FSector);
    if FSector = nil then exit;
    FOffset := 0;
  end;

  FCurrent.Sector := FSector;
  FCurrent.Offset := FOffset;
  FCurrent.Index := FIndex;
  Result := True;
end;

function TDSKDirEntryWalk.GetEnumerator: TDSKDirEntryEnumerator;
begin
  Result := TDSKDirEntryEnumerator.Create(Disk, Start, EntrySize, MaxEntries);
end;

// Walk fixed-size directory entries packed across the disk's logical sectors,
// starting at Start and stopping after MaxEntries or when the data runs out.
function TDSKDisk.DirectoryEntries(Start: TDSKSector; EntrySize, MaxEntries: integer): TDSKDirEntryWalk;
begin
  Result.Disk := Self;
  Result.Start := Start;
  Result.EntrySize := EntrySize;
  Result.MaxEntries := MaxEntries;
end;

constructor TDSKTrackEnumerator.Create(ADisk: TDSKDisk);
begin
  inherited Create;
  FDisk := ADisk;
  FSideIdx := 0;
  FTrackIdx := -1;
end;

function TDSKTrackEnumerator.MoveNext: boolean;
begin
  Inc(FTrackIdx);
  while FSideIdx < FDisk.Sides do
  begin
    if FTrackIdx < FDisk.Side[FSideIdx].Tracks then
    begin
      FCurrent := FDisk.Side[FSideIdx].Track[FTrackIdx];
      exit(True);
    end;
    Inc(FSideIdx);
    FTrackIdx := 0;
  end;
  Result := False;
end;

function TDSKTrackWalk.GetEnumerator: TDSKTrackEnumerator;
begin
  Result := TDSKTrackEnumerator.Create(Disk);
end;

constructor TDSKSectorEnumerator.Create(ADisk: TDSKDisk);
begin
  inherited Create;
  FDisk := ADisk;
  FSideIdx := 0;
  FTrackIdx := 0;
  FSectorIdx := -1;
end;

function TDSKSectorEnumerator.MoveNext: boolean;
begin
  Inc(FSectorIdx);
  while FSideIdx < FDisk.Sides do
  begin
    if FTrackIdx < FDisk.Side[FSideIdx].Tracks then
    begin
      if FSectorIdx < FDisk.Side[FSideIdx].Track[FTrackIdx].Sectors then
      begin
        FCurrent := FDisk.Side[FSideIdx].Track[FTrackIdx].Sector[FSectorIdx];
        exit(True);
      end;
      Inc(FTrackIdx);
      FSectorIdx := 0;
    end
    else
    begin
      Inc(FSideIdx);
      FTrackIdx := 0;
      FSectorIdx := 0;
    end;
  end;
  Result := False;
end;

function TDSKSectorWalk.GetEnumerator: TDSKSectorEnumerator;
begin
  Result := TDSKSectorEnumerator.Create(Disk);
end;

function TDSKDisk.AllTracks: TDSKTrackWalk;
begin
  Result.Disk := Self;
end;

function TDSKDisk.AllSectors: TDSKSectorWalk;
begin
  Result.Disk := Self;
end;

function TDSKDisk.GetNextLogicalSector(Sector: TDSKSector): TDSKSector;
var
  NextSectorID: integer;
  CheckSector: TDSKSector;
  CheckTrack: TDSKTrack;
begin
  Result := nil;
  NextSectorId := Sector.ID + 1;
  CheckTrack := Sector.ParentTrack;

  while (CheckTrack <> nil) do
  begin
    // Find the next highest sector number on this track
    for CheckSector in CheckTrack.Sector do
    begin
      if CheckSector.ID >= NextSectorID then
        if (Result = nil) or (Result.ID > CheckSector.ID) then
          Result := CheckSector;
    end;
    if (Result <> nil) then exit;

    // Find the next logical track
    NextSectorID := 0;
    // Raw MGT numbers side 1 from 128, leaving 80..127 unused after the
    // 80 tracks on side 0. Continue across that gap rather than stopping.
    if (FParentImage.FileFormat = diRawMGT) and (CheckTrack.Logical = 79) then
      CheckTrack := GetLogicalTrack(128)
    else
      CheckTrack := GetLogicalTrack(CheckTrack.Logical + 1);
  end;
end;

procedure TDSKDisk.Format(Formatter: TDSKFormatSpecification);
var
  SIdx, TIdx: integer;
begin
  // Formatting is public as well as used by the New dialog. Refuse an image
  // beyond the sector-object budget before changing its existing geometry.
  if int64(Formatter.TracksPerSide) * Formatter.GetSidesCount *
    Formatter.SectorsPerTrack > MaxImageSectors then
    raise ERangeError.CreateFmt('A disk can hold at most %d sectors in memory.', [MaxImageSectors]);

  FParentImage.IsChanged := True;
  Sides := Formatter.GetSidesCount;
  for SIdx := 0 to Formatter.GetSidesCount - 1 do
    for TIdx := 0 to Formatter.TracksPerSide - 1 do
    begin
      Side[SIdx].SetTracks(Formatter.TracksPerSide);
      Side[SIdx].Track[TIdx].Track := TIdx;
      Side[SIdx].Track[TIdx].Side := SIdx;
      Side[SIdx].Track[TIdx].Format(Formatter);
    end;
end;

function TDSKDisk.GetSides: byte;
begin
  if Side = nil then
    Result := 0
  else
    Result := High(Side) + 1;
end;

procedure TDSKDisk.SetSides(NewSides: byte);
var
  OldSides: byte;
  Idx: byte;
begin
  OldSides := Sides;
  if OldSides > NewSides then
  begin
    for Idx := NewSides to OldSides - 1 do
      Side[Idx].Free;
    SetLength(Side, NewSides);
  end;

  if NewSides > OldSides then
  begin
    SetLength(Side, NewSides);
    for Idx := OldSides to NewSides - 1 do
    begin
      Side[Idx] := TDSKSide.Create(Self);
      Side[Idx].Side := Idx;
    end;
  end;
end;

function TDSKDisk.GetFormattedCapacity: integer;
var
  Track: TDSKTrack;
begin
  Result := 0;
  for Track in AllTracks do
    Result := Result + Track.Size;
end;

function TDSKDisk.GetTrackTotal: word;
var
  Side: TDSKSide;
begin
  Result := 0;
  for Side in self.Side do
    Result := Result + Side.Tracks;
end;

function TDSKDisk.GetLogicalTrack(LogicalTrack: word): TDSKTrack;
var
  Track: TDSKTrack;
begin
  Result := nil;
  for Track in AllTracks do
    if Track.Logical = LogicalTrack then
    begin
      Result := Track;
      exit;
    end;
end;

// Whether every track on the disk holds the same number of bytes. A disk with
// no tracks at all is trivially uniform: a header can say one side and no
// tracks, and reading the size of the first of none went straight through a
// side whose track array had never been allocated.
function TDSKDisk.IsTrackSizeUniform: boolean;
var
  Track: TDSKTrack;
  Size: integer;
  First: boolean;
begin
  Result := True;
  Size := 0;
  First := True;
  for Track in AllTracks do
  begin
    if First then
    begin
      Size := Track.Size;
      First := False;
    end;
    if Size <> Track.Size then
    begin
      Result := False;
      exit;
    end;
  end;
end;

function TDSKDisk.DetectFormat: string;
begin
  Result := DetectUniformFormat(self);
end;

function TDSKDisk.DetectCopyProtection: string;
begin
  if (self.Sides < 1) then
     Result := ''
  else
      Result := DetectProtection(self.Side[0]);
end;

function TDSKDisk.BootableOn: string;
var
  Mod256: integer;
begin
  Result := '';
  if Sides = 0 then exit;
  if (Side[0].Tracks > 0) and (Side[0].Track[0].Sectors > 0) then
  begin
    if Side[0].Track[0].Sector[0].Status = ssFormattedInUse then
    begin
      Mod256 := Side[0].Track[0].Sector[0].GetModChecksum(256);
      case Mod256 of
        1: Result := 'Amstrad PCW 9512';
        3: Result := 'Spectrum +3';
        255: Result := 'Amstrad PCW 8256';
        else
          case Side[0].Track[0].LowSectorID of
            65: Result := 'Amstrad CPC 664/6128';
            193: Result := ''; // CPC Data is not bootable
            else
              Result := SysUtils.Format('Unknown (%d checksum)', [Mod256]);
          end;
      end;
    end;
    with Side[0].Track[0].Sector[0] do
      if (FDCStatus[1] and 32 = 32) or (FDCStatus[2] and 64 = 64) then
        Result := Result + ' (Corrupt?)';
  end;
end;

const
  TrimChars: array[0..30] of char = (' ', '''', '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', '{',
    '}', ':', '"', '<', '>', '?', '-', '=', '[', ']', ';', ',', '.', '/', '`', '~');

function TDSKDisk.GetAllStrings(MinLength: integer; MinUniques: integer): TStringList;
var
  Sector: TDSKSector;
  CurrentText: string;
  Index, CIdx: integer;
  NextByte: byte;
  Uniques: TStringList;
  Seen: TStringList;
  CurrChar: char;
  Found: string;
begin
  Result := TStringList.Create;
  CurrentText := '';
  // Nil on a disk with no sectors to walk, which ends the loop below at once
  Sector := GetFirstSector();
  Index := 0;
  Uniques := TStringList.Create;
  Uniques.Duplicates := DupIgnore;
  Uniques.Sorted := True;

  // Strings already reported, so a repeat of one is skipped rather than listed
  // again. Sorted for the lookup, and cased so only exact repeats are dropped:
  // 'HELLO' and 'hello' are different bytes on the disk and both worth seeing.
  Seen := TStringList.Create;
  Seen.Sorted := True;
  Seen.CaseSensitive := True;

  try
    while Sector <> nil do
    begin
      NextByte := Sector.Data[Index];
      if (NextByte >= 32) and (NextByte <= 127) then
      begin
        CurrentText := CurrentText + Chr(NextByte);
      end
      else
      begin
        if CurrentText.Trim(TrimChars).Length >= MinLength then
        begin
          Uniques.Clear;
          for CIdx := 1 to CurrentText.Length do
          begin
            CurrChar := CurrentText[CIdx];
            if IsUpper(CurrChar) or IsLower(CurrChar) then Uniques.Append(CurrChar);
            if (Uniques.Count >= MinUniques) then break;
          end;

          if (Uniques.Count >= MinUniques) then
          begin
            Found := CurrentText.Trim();
            if Seen.IndexOf(Found) < 0 then
            begin
              Seen.Add(Found);
              Result.Append(Found);
            end;
          end;
        end;
        CurrentText := '';
      end;

      Inc(Index);
      if Index >= Sector.DataSize then
      begin
        Sector := GetNextLogicalSector(Sector);
        Index := 0;
      end;
    end;
  finally
    Uniques.Free;
    Seen.Free;
  end;
end;

function TDSKDisk.HasFDCErrors: boolean;
var
  Sector: TDSKSector;
begin
  Result := False;
  for Sector in AllSectors do
    if ((Sector.FDCStatus[1] <> 0) and (Sector.FDCStatus[1] <> 128)) or (Sector.FDCStatus[2] <> 0) then
    begin
      Result := True;
      exit;
    end;
end;

function TDSKDisk.IsUniform(IgnoreEmptyTracks: boolean): boolean;
var
  CheckTracks, CheckSectors, CheckSectorSize: integer;
  Side: TDSKSide;
  Track: TDSKTrack;
  Sector: TDSKSector;
begin
  Result := True;
  if GetFirstSector <> nil then
  begin
    CheckTracks := self.Side[0].Tracks;
    CheckSectors := self.Side[0].Track[0].Sectors;
    CheckSectorSize := self.Side[0].Track[0].Sector[0].DataSize;
    for Side in self.Side do
    begin
      if CheckTracks <> Side.Tracks then
      begin
        Result := False;
        exit;
      end;

      for Track in Side.Track do
      begin
        if not ((Track.Sectors = 0) and IgnoreEmptyTracks) then
          if CheckSectors <> Track.Sectors then
          begin
            Result := False;
            exit;
          end;

        for Sector in Track.Sector do
          if CheckSectorSize <> Sector.DataSize then
          begin
            Result := False;
            exit;
          end;
      end;
    end;
  end;
end;

function TDSKDisk.GetFirstSector: TDSKSector;
begin
  Result := nil;
  if (Sides > 0) and (Side[0].Tracks > 0) and (Side[0].Track[0].Sectors > 0) then
    Result := Side[0].Track[0].Sector[0];
end;

// Side                                                  .
constructor TDSKSide.Create(ParentDisk: TDSKDisk);
begin
  inherited Create;
  FParentDisk := ParentDisk;
end;

destructor TDSKSide.Destroy;
begin
  SetTracks(0);
  FParentDisk := nil;
  inherited Destroy;
end;

function TDSKSide.GetTracks: byte;
begin
  if Track = nil then
    Result := 0
  else
    Result := High(Track) + 1;
end;

function TDSKSide.GetHighTrackCount: byte;
begin
  // Test the count before the track it indexes: a side with no tracks at all
  // would otherwise read Track[-1] on the way to answering 0
  Result := Tracks;
  while (Result > 1) and (not Track[Result - 1].IsFormatted) do
    Result := Result - 1;
end;

function TDSKSide.GetLargestTrackSize: integer;
var
  Track: TDSKTrack;
  Size: integer;
begin
  Result := 0;
  for Track in self.Track do
  begin
    Size := Track.GetTrackSizeFromSectors();
    if Size > Result then
      Result := Size;
  end;
end;

// Track by index, or nil when the index is out of range
function TDSKSide.SafeTrack(Index: integer): TDSKTrack;
begin
  if (Index >= 0) and (Index < Tracks) then
    Result := Track[Index]
  else
    Result := nil;
end;

function TDSKSide.HasTrackProperty(Prop: TDSKTrackProperty): boolean;
var
  Track: TDSKTrack;
begin
  Result := True;
  for Track in self.Track do
    case Prop of
      tpDataRate: if Track.DataRate <> drUnknown then exit;
      tpRecordingMode: if Track.RecordingMode <> rmUnknown then exit;
      tpBitLength: if Track.BitLength > 0 then exit;
    end;
  Result := False;
end;

function TDSKSide.HasDataRate: boolean;
begin
  Result := HasTrackProperty(tpDataRate);
end;

function TDSKSide.HasRecordingMode: boolean;
begin
  Result := HasTrackProperty(tpRecordingMode);
end;

function TDSKSide.HasBitLength: boolean;
begin
  Result := HasTrackProperty(tpBitLength);
end;

function TDSKSide.HasVariantSectors: boolean;
var
  Track: TDSKTrack;
  Sector: TDSKSector;
begin
  Result := True;
  for Track in self.Track do
    for Sector in Track.Sector do
      if Sector.GetCopyCount > 1 then exit;
  Result := False;
end;

procedure TDSKSide.SetTracks(NewTracks: byte);
var
  OldTracks: byte;
  Idx: byte;
begin
  OldTracks := Tracks;
  if OldTracks > NewTracks then
  begin
    for Idx := NewTracks to OldTracks - 1 do
      Track[Idx].Free;
    SetLength(Track, NewTracks);
  end;

  if NewTracks > OldTracks then
  begin
    SetLength(Track, NewTracks);
    for Idx := OldTracks to NewTracks - 1 do
      Track[Idx] := TDSKTrack.Create(Self);
  end;
end;

// Track                                                .
constructor TDSKTrack.Create(ParentSide: TDSKSide);
begin
  inherited Create;
  FParentSide := ParentSide;
end;

destructor TDSKTrack.Destroy;
begin
  SetSectors(0);
  FParentSide := nil;
  inherited Destroy;
end;

function TDSKTrack.GetLowSectorID: byte;
var
  Sector: TDSKSector;
begin
  Result := 255;
  for Sector in self.Sector do
    if Sector.ID < Result then
      Result := Sector.ID;
end;

function TDSKTrack.GetTrackSizeFromSectors: integer;
var
  Sector: TDSKSector;
begin
  Result := 0;
  for Sector in self.Sector do
    Result := Result + Sector.DataSize;
end;

function TDSKTrack.GetFirstLogicalSector: TDSKSector;
var
  Sector: TDSKSector;
begin
  Result := nil;
  if not IsFormatted then exit;

  Result := self.Sector[0];
  for Sector in self.Sector do
    if Sector.ID < Result.ID then
      Result := Sector;
end;

// Sector by index, or nil when the index is out of range
function TDSKTrack.SafeSector(Index: integer): TDSKSector;
begin
  if (Index >= 0) and (Index < Sectors) then
    Result := Sector[Index]
  else
    Result := nil;
end;

function TDSKTrack.GetLogicalSectorByID(SectorID: byte): TDSKSector;
var
  Sector: TDSKSector;
begin
  Result := nil;
  if not IsFormatted then exit;

  for Sector in self.Sector do
    if Sector.ID = SectorID then
      Result := Sector;
end;


function TDSKTrack.HasMultiSectoredSector: boolean;
var
  CheckSector: TDSKSector;
begin
  Result := True;
  for CheckSector in Sector do
    if CheckSector.GetCopyCount > 1 then exit;
  Result := False;
end;

function TDSKTrack.HasIndexPointOffsets: boolean;
var
  CheckSector: TDSKSector;
begin
  Result := True;
  for CheckSector in Sector do
    if CheckSector.IndexPointOffset > 0 then exit;
  Result := False;
end;

function TDSKTrack.GetIsFormatted: boolean;
begin
  Result := Sectors > 0;
end;

function TDSKTrack.GetSectors: byte;
begin
  if Sector = nil then
    Result := 0
  else
    Result := High(Sector) + 1;
end;

// The image this track belongs to, or nil if any link in the chain is missing
function TDSKTrack.ParentImage: TDSKImage;
begin
  Result := nil;
  if (FParentSide <> nil) and (FParentSide.ParentDisk <> nil) then
    Result := FParentSide.ParentDisk.ParentImage;
end;

// Note that this track has been edited, so the image knows it has something
// worth saving. Tracks carry no changed flag of their own; the image is the
// only thing that acts on one.
procedure TDSKTrack.MarkChanged;
var
  Image: TDSKImage;
begin
  Image := ParentImage;
  if Image <> nil then
    Image.IsChanged := True;
end;

procedure TDSKTrack.Unformat;
begin
  Sectors := 0;
  MarkChanged;
end;

procedure TDSKTrack.SetSectors(NewSectors: byte);
var
  OldSectors: byte;
  SIdx: byte;
begin
  OldSectors := Sectors;

  if OldSectors > NewSectors then
  begin
    for SIdx := NewSectors to OldSectors - 1 do
      Sector[SIdx].Free;
    SetLength(Sector, NewSectors);
  end;

  if NewSectors > OldSectors then
  begin
    SetLength(Sector, NewSectors);
    for SIdx := OldSectors to NewSectors - 1 do
      Sector[SIdx] := TDSKSector.Create(Self);
  end;
end;

procedure TDSKTrack.Format(Formatter: TDSKFormatSpecification);
var
  EIdx: byte;
  FormatSectorSize: word;
begin
  // A sector's buffer is a fixed MaxSectorSize but a specification states its
  // sector size in a word, and filling one to a size the buffer has not got
  // writes straight past it. The load path caps this; formatting has to too.
  FormatSectorSize := Formatter.SectorSize;
  if FormatSectorSize > MaxSectorSize then
    FormatSectorSize := MaxSectorSize;

  Filler := Formatter.FillerByte;
  SectorSize := FormatSectorSize;
  Sectors := Formatter.SectorsPerTrack;
  GapLength := Formatter.GapFormat;
  DataRate := Formatter.DataRate;
  RecordingMode := Formatter.RecordingMode;

  case Formatter.Sides of
    dsSideSingle: Logical := Track;
    dsSideDoubleAlternate: Logical := (Track * Formatter.GetSidesCount) + Side;
    dsSideDoubleSuccessive: Logical := (Side * Formatter.TracksPerSide) + Track;
    // Side 1 is numbered from the outside back in, so it carries on from the
    // last track of side 0 rather than counting down into it: numbering it
    // TracksPerSide - Track gave side 1 the numbers side 0 already had, and
    // every track but the first answered to two tracks at once
    dsSideDoubleReverse:
      if Side = 0 then
        Logical := Track
      else
        Logical := (Formatter.TracksPerSide * 2) - 1 - Track;
  end;

  for EIdx := 0 to Sectors - 1 do
  begin
    Sector[EIdx].Side := Side;
    Sector[EIdx].Track := Track;
    Sector[EIdx].Sector := EIdx;
    Sector[EIdx].FDCSize := Formatter.FDCSectorSize;
    Sector[EIdx].DataSize := FormatSectorSize;
    Sector[EIdx].ID := Formatter.GetSectorID(Side, Logical, Sector[EIdx].Sector);
    Sector[EIdx].FillSector(Formatter.FillerByte);
  end;
end;

// Sector
constructor TDSKSector.Create(ParentTrack: TDSKTrack);
begin
  inherited Create;
  FParentTrack := ParentTrack;
  ResetFDC;
  IsChanged := False;
  IndexPointOffset := 0;
end;

destructor TDSKSector.Destroy;
begin
  FParentTrack := nil;
  inherited Destroy;
end;

// The image this sector belongs to, or nil if any link in the chain is missing
function TDSKSector.ParentImage: TDSKImage;
begin
  Result := nil;
  if FParentTrack <> nil then
    Result := FParentTrack.ParentImage;
end;

// Marking a sector changed marks the image with it. Only the image is asked
// whether there is anything to save, so a sector that knew it had been edited
// while the image did not meant every edit made through the sector and track
// property windows was dropped on close without so much as a prompt.
procedure TDSKSector.SetIsChanged(NewValue: boolean);
var
  Image: TDSKImage;
begin
  FIsChanged := NewValue;
  if not NewValue then exit;

  Image := ParentImage;
  if Image <> nil then
    Image.IsChanged := True;
end;

function TDSKSector.GetStatus: TDSKSectorStatus;
var
  FillByte: integer;
begin
  FillByte := GetFillByte;
  case FillByte of
    -2: Result := ssUnformatted;
    -1: Result := ssFormattedInUse;
    else
      if FillByte = ParentTrack.Filler then
        Result := ssFormattedBlank
      else
        Result := ssFormattedFilled;
  end;
end;

function TDSKSector.GetCopyCount: integer;
var
  DeclaredSize: integer;
begin
  Result := 1;
  DeclaredSize := GetFDCSizeBytes(FDCSize);
  if (DeclaredSize = 0) or (DataSize mod DeclaredSize <> 0) then exit;
  Result := DataSize div DeclaredSize;
end;

// Size of one copy of a (possibly multi-copy v5 weak) sector.
function TDSKSector.GetCopySize: word;
var
  Count: integer;
begin
  Count := GetCopyCount;
  if Count > 1 then
    Result := DataSize div Count
  else
    Result := DataSize;
end;

// Pointer to the Idx'th copy. Idx is clamped to [0, GetCopyCount-1].
function TDSKSector.GetCopy(Idx: integer): PByte;
var
  Count: integer;
begin
  Count := GetCopyCount;
  if Idx < 0 then Idx := 0;
  if Idx >= Count then Idx := Count - 1;
  Result := @Data[Idx * GetCopySize];
end;

// Get filler byte or -1 if in use, -2 if unformatted.
// Inspects copy 0 only; weak-sector copies 1..K-1 typically differ by design.
function TDSKSector.GetFillByte: integer;
var
  Idx: integer;
  Limit: integer;
begin
  Result := -2;
  if DataSize > 0 then
    Result := Data[0];
  Limit := GetCopySize;
  for Idx := 0 to Limit - 1 do
    if Data[Idx] <> Data[0] then
    begin
      Result := -1;
      break;
    end;
end;

procedure TDSKSector.ResetFDC;
var
  Idx: integer;
begin
  for Idx := 1 to SizeOf(FDCStatus) do
    if FDCStatus[Idx] <> 0 then
    begin
      FDCStatus[Idx] := 0;
      IsChanged := True;
    end;
end;

procedure TDSKSector.FillSector(Filler: byte);
begin
  if GetFillByte <> Filler then
  begin
    FillChar(Data, DataSize, Filler);
    IsChanged := True;
  end;
end;

procedure TDSKSector.Unformat;
begin
  if DataSize > 0 then
  begin
    FDCSize := 0;
    DataSize := 0;
    IsChanged := True;
  end;
end;

// Modular sum over copy 0 — for a v5 weak sector, summing concatenated copies
// would not match what real hardware sees in any single read.
function TDSKSector.GetModChecksum(ModValue: integer): integer;
var
  Idx: integer;
  Limit: integer;
begin
  Result := 0;
  Limit := GetCopySize;
  for Idx := 0 to Limit - 1 do
    Result := (Result + Data[Idx]) mod ModValue;
end;

// Index of the last byte of the first match, or -1. Each starting position is
// tried in full: walking the data once and restarting the search on a mismatch
// skipped the byte that failed, so a match whose start repeats its own first
// byte was missed entirely, and 'AB' was not found in 'AAB'.
function TDSKSector.FindText(Text: string; CaseSensitive: boolean): integer;
var
  Start, Idx: integer;
  Matched: boolean;
  TestChar, WantChar: char;
begin
  Result := -1;
  if (DataSize = 0) or (Length(Text) = 0) or (Length(Text) > DataSize) then
    exit;

  for Start := 0 to DataSize - Length(Text) do
  begin
    Matched := True;
    for Idx := 1 to Length(Text) do
    begin
      TestChar := char(Data[Start + Idx - 1]);
      WantChar := Text[Idx];
      if not CaseSensitive then
      begin
        TestChar := UpCase(TestChar);
        WantChar := UpCase(WantChar);
      end;
      if TestChar <> WantChar then
      begin
        Matched := False;
        break;
      end;
    end;

    if Matched then
    begin
      Result := Start + Length(Text) - 1;
      exit;
    end;
  end;
end;

// Disk specification                                        .
constructor TDSKSpecification.Create(ParentDisk: TDSKDisk);
begin
  inherited Create;
  FParentDisk := ParentDisk;
  // This class has no Read, so the bare Read left here resolved to the one in
  // System and did nothing at all, leaving a new specification's fields as
  // whatever they happened to be until something called Identify
  SetDefaults;
end;

destructor TDSKSpecification.Destroy;
begin
  FParentDisk := nil;
  inherited Destroy;
end;

procedure TDSKSpecification.SetBlockShift(NewBlockShift: byte);
begin
  if NewBlockShift <> FBlockShift then
  begin
    FIsChanged := True;
    FBlockShift := NewBlockShift;
  end;
end;

function TDSKSpecification.GetBlockSize: integer;
begin
  Result := BlockShiftToBlockSize(BlockShift);
end;

function TDSKSpecification.GetBlockCount: word;
begin
  Result := GetUsableCapacity div GetBlockSize;
end;

function TDSKSpecification.GetUsableCapacity: integer;
var
  UsableTracks: integer;
begin
  UsableTracks := FTracksPerSide;
  if Side <> dsSideSingle then UsableTracks := UsableTracks + UsableTracks;
  UsableTracks := UsableTracks - ReservedTracks;
  Result := UsableTracks * SectorsPerTrack * SectorSize;
end;

function TDSKSpecification.GetRecordsPerTrack: integer;
begin
  Result := (SectorSize * SectorsPerTrack) div 128;
end;

procedure TDSKSpecification.SetChecksum(NewChecksum: byte);
begin
  if NewChecksum <> FChecksum then
  begin
    FIsChanged := True;
    FChecksum := NewChecksum;
  end;
end;

procedure TDSKSpecification.SetDirectoryBlocks(NewDirectoryBlocks: byte);
begin
  if NewDirectoryBlocks <> FDirectoryBlocks then
  begin
    FIsChanged := True;
    FDirectoryBlocks := NewDirectoryBlocks;
  end;
end;

procedure TDSKSpecification.SetFormat(NewFormat: TDSKSpecFormat);
begin
  if NewFormat <> FFormat then
  begin
    FIsChanged := True;
    FFormat := NewFormat;
  end;
end;

procedure TDSKSpecification.SetGapFormat(NewGapFormat: byte);
begin
  if NewGapFormat <> FGapFormat then
  begin
    FIsChanged := True;
    FGapFormat := NewGapFormat;
  end;
end;

procedure TDSKSpecification.SetGapReadwrite(NewGapReadWrite: byte);
begin
  if NewGapReadWrite <> FGapReadWrite then
  begin
    FIsChanged := True;
    FGapReadWrite := NewGapReadWrite;
  end;
end;

procedure TDSKSpecification.SetReservedTracks(NewReservedTracks: byte);
begin
  if NewReservedTracks <> FReservedTracks then
  begin
    FIsChanged := True;
    FReservedTracks := NewReservedTracks;
  end;
end;

procedure TDSKSpecification.SetSectorsPerTrack(NewSectorsPerTrack: byte);
begin
  if NewSectorsPerTrack <> FSectorsPerTrack then
  begin
    FIsChanged := True;
    FSectorsPerTrack := NewSectorsPerTrack;
  end;
end;

procedure TDSKSpecification.SetFDCSectorSize(NewFDCSectorSize: byte);
begin
  if NewFDCSectorSize <> FFDCSectorSize then
  begin
    FIsChanged := True;
    FFDCSectorSize := NewFDCSectorSize;
  end;
end;

procedure TDSKSpecification.SetSectorSize(NewSectorSize: word);
begin
  if NewSectorSize <> FSectorSize then
  begin
    FIsChanged := True;
    FSectorSize := NewSectorSize;
  end;
end;

procedure TDSKSpecification.SetSide(NewSide: TDSKSpecSide);
begin
  if NewSide <> FSide then
  begin
    FIsChanged := True;
    FSide := NewSide;
  end;
end;

procedure TDSKSpecification.SetTrack(NewTrack: TDSKSpecTrack);
begin
  if NewTrack <> FTrack then
  begin
    FIsChanged := True;
    FTrack := NewTrack;
  end;
end;

procedure TDSKSpecification.SetTracksPerSide(NewTracksPerSide: byte);
begin
  if NewTracksPerSide <> FTracksPerSide then
  begin
    FIsChanged := True;
    FTracksPerSide := NewTracksPerSide;
  end;
end;

procedure TDSKSpecification.SetDefaults;
begin
  FFormat := dsFormatAssumedPCW_SS;
  FSide := dsSideSingle;
  FTrack := dsTrackSingle;
  FTracksPerSide := 40;
  FSectorsPerTrack := 9;
  FSectorSize := 512;
  FReservedTracks := 1;
  FBlockShift := 3;
  FDirectoryBlocks := 2;
  FGapReadWrite := 42;
  FGapFormat := 82;

  if GetBlockCount > 255 then
    FAllocationSize := asWord
  else
    FAllocationSize := asByte;
end;

procedure TDSKSpecification.Identify;
var
  FirstTrack: TDSKTrack;
  FirstSector: TDSKSector;
  CheckByte: byte;
  Idx: integer;
begin
  FFormat := dsFormatInvalid;

  if FParentDisk.DetectFormat = 'Einstein' then
  begin
    FFormat := dsFormatEinstein;
    Source := 'Signature 00 E1 00 FB 00 FA on first logical sector';
    SectorSize := 512;
    SectorsPerTrack := 10;
    TracksPerSide := 40;
    BlockShift := 4;
    FReservedTracks := 2;
    FDirectoryBlocks := 1;
    FAllocationSize := asWord;
    exit;
  end;

  if FParentDisk.DetectFormat = 'TS2068' then
  begin
    FFormat := dsFormatTS2068;
    Source := '16x 256 byte sectors per track, starting ID 0';
    SectorSize := 256;
    SectorsPerTrack := 16;
    TracksPerSide := 40;
    GapReadWrite := 12;
    GapFormat := 23;
    FReservedTracks := 2;
    FDirectoryBlocks := 1;
    exit;
  end;

  if FParentDisk.DetectFormat.StartsWith('MGT ') then
  begin
    FFormat := dsFormatMGT;
    Source := 'Double sided 80 track 10 sectors of 512 bytes';
    SectorSize := 512;
    SectorsPerTrack := 10;
    // 80, as the line above says and as 2 sides x 80 x 10 x 512 = MGTRawSize
    // requires. 40 described half a disk.
    TracksPerSide := 80;
    FSide := dsSideDoubleSuccessive;
    ReservedTracks := 0;
    FDirectoryBlocks := 4;
    // Settled, like the Einstein and TS2068 formats above. Without this the
    // disk spec probe below had another go at it, and a fresh MGT disk, whose
    // first sector is all zeroes, came back out of it as a PCW.
    exit;
  end;

  // An image need not have a logical track 0 at all, so there may be no first
  // sector to identify the format from
  FirstTrack := FParentDisk.GetLogicalTrack(0);
  if FirstTrack = nil then exit;
  FirstSector := FirstTrack.GetFirstLogicalSector();
  if FirstSector = nil then exit;

  with FirstSector do
  begin
    case ID of
      65: begin // CPC System
        SetDefaults;
        Source := 'First logical sector has ID of 65';
        FFormat := dsFormatCPC_System;
        FReservedTracks := 2;
        exit;
      end;
      193: begin // CPC Data
        SetDefaults;
        Source := 'First logical sector has ID of 193';
        FFormat := dsFormatCPC_Data;
        FReservedTracks := 0;
        exit;
      end;
    end;

    // The checksum at byte 15 is read as well as the first eleven fields.
    if FirstSector.DataSize < 16 then exit;

    // Are the first eleven bytes all the same value? Testing the byte before
    // the bound read one past the last it needed: the loop only leaves when Idx
    // reaches 11, and it read Data[11] on the way out to decide that. Testing
    // the bound first stops at exactly the same place without the extra read.
    CheckByte := FirstSector.Data[0];
    Idx := 1;
    while (Idx <= 10) and (CheckByte = FirstSector.Data[Idx]) do
      Inc(Idx);
    if Idx = 11 then
    begin
      SetDefaults;
      Source := SysUtils.Format('Sector 0 spec block is all %x', [CheckByte]);
    end;

    // Okay, finally lets check for a disk specification
    case Data[0] of
      0: FFormat := dsFormatPCW_SS;
      1: FFormat := dsFormatCPC_System;
      2: FFormat := dsFormatCPC_Data;
      3: FFormat := dsFormatPCW_DS;
      else
        exit;
    end;

    Source := 'Sector 0 spec block';

    case (Data[1] and $3) of
      0: FSide := dsSideSingle;
      1: FSide := dsSideDoubleAlternate;
      2: FSide := dsSideDoubleSuccessive;
    end;

    if (Data[1] and $80) = $80 then
      FTrack := dsTrackDouble
    else
      FTrack := dsTrackSingle;

    FTracksPerSide := Data[2];
    FSectorsPerTrack := Data[3];

    if Data[4] <= High(FDCSectorSizes) then
      FSectorSize := FDCSectorSizes[Data[4]]
    else
      FSectorSize := 0;

    FReservedTracks := Data[5];
    FBlockShift := Data[6];
    FDirectoryBlocks := Data[7];
    FGapReadWrite := Data[8];
    FGapFormat := Data[9];
    FChecksum := Data[15];

    // A block shift past MaxBlockShift describes no disk that exists, and is as
    // good a sign the spec block is not one as the other fields being nonsense
    if (FTracksPerSide = 0) or (FSectorsPerTrack = 0) or
      (FTracksPerSide > MaxTracks) or (FSectorSize = 0) or
      (FBlockShift > MaxBlockShift) then
    begin
      SetDefaults;
      Source := 'Default fallback +3/PCW 180K';
      exit;
    end;

    if GetBlockCount > 255 then
        FAllocationSize := asWord
    else
        FAllocationSize := asByte;
  end;
end;

function TDSKSpecification.Write: boolean;
begin
  Result := False;
  if FParentDisk.GetFirstSector = nil then exit;
  if FParentDisk.GetFirstSector.DataSize < 16 then exit;
  with FParentDisk.Side[0].Track[0].Sector[0] do
    begin
      case FFormat of
        dsFormatPCW_SS: Data[0] := 0;
        dsFormatCPC_System: Data[0] := 1;
        dsFormatCPC_Data: Data[0] := 2;
        dsFormatPCW_DS: Data[0] := 3;
      end;

      case FSide of
        dsSideSingle: Data[1] := 0;
        dsSideDoubleAlternate: Data[1] := 1;
        dsSideDoubleSuccessive: Data[1] := 2;
      end;
      if FTrack = dsTrackDouble then
        Data[1] := (Data[1] or $80);

      Data[2] := FTracksPerSide;
      Data[3] := FSectorsPerTrack;
      Data[4] := Trunc(Log2(FSectorSize) - 7);
      Data[5] := FReservedTracks;
      Data[6] := FBlockShift;
      Data[7] := FDirectoryBlocks;
      Data[8] := FGapReadWrite;
      Data[9] := FGapFormat;
      Data[10] := 0;
      Data[11] := 0;
      Data[12] := 0;
      Data[13] := 0;
      Data[14] := 0;
      Data[15] := FChecksum;
      Result := True;
    end;
end;

// Disk format specifications                                  .
function TDSKFormatSpecification.GetCapacityBytes: integer;
begin
  Result := TracksPerSide * GetSidesCount * SectorsPerTrack * SectorSize;
end;

function TDSKFormatSpecification.GetBlockSize: integer;
begin
  Result := BlockShiftToBlockSize(BlockShift);
end;

function TDSKFormatSpecification.GetDirectoryEntries: integer;
begin
  Result := (DirBlocks * GetBlockSize) div 32;
end;

function TDSKFormatSpecification.GetUsableBytes: integer;
var
  UsableTracks, UsableSectors, UsableBytes, WastedBytes: integer;
begin
  UsableTracks := (TracksPerSide * GetSidesCount) - ResTracks;
  UsableSectors := (UsableTracks * SectorsPerTrack);
  UsableBytes := (UsableSectors * SectorSize) - (DirBlocks * GetBlockSize);
  WastedBytes := UsableBytes mod GetBlockSize;
  Result := UsableBytes - WastedBytes;
end;

function TDSKFormatSpecification.GetSidesCount: byte;
begin
  if Sides = dsSideSingle then
    Result := 1
  else
    Result := 2;
end;

function TDSKFormatSpecification.GetSectorID(Side: byte; LogicalTrack: word; Sector: byte): byte;
var
  TrackSkewIdx: integer;
begin
  BuildSectorIDs;

  // No sectors means no table to take an ID out of
  if Length(FSectorIDs) = 0 then
  begin
    Result := 0;
    exit;
  end;

  if (SkewTrack = 0) and ((SkewSide = 0) or (Sides = dsSideSingle)) then
  begin
    Result := FSectorIDs[Sector mod SectorsPerTrack];
    exit;
  end;

  TrackSkewIdx := SkewTrack * LogicalTrack;

  case Sides of
    dsSideDoubleAlternate:
    begin
      TrackSkewIdx := TrackSkewIdx + (SkewSide * Side);
    end;

    dsSideDoubleSuccessive:
    begin
      TrackSkewIdx := TrackSkewIdx + (SkewSide * Side);
    end;

    // The skew follows the track the head is over, and on side 1 of a reversed
    // disk that is not what the logical number counts. This sat in the case's
    // else branch, which only dsSideInvalid ever reaches, so it never ran.
    dsSideDoubleReverse:
      if (Side = 1) then
        TrackSkewIdx := ((((TracksPerSide * 2) - 1 - LogicalTrack) * SkewTrack)) + SkewSide;
  end;

  // A track skew can be negative, and Pascal's mod keeps the sign of what it is
  // dividing, so this indexed the table from before its start. The second mod
  // brings a negative remainder back into the table without disturbing a
  // positive one.
  Result := FSectorIDs[((TrackSkewIdx + Sector) mod SectorsPerTrack +
    SectorsPerTrack) mod SectorsPerTrack];
end;

// Build the sector ID table for the interleave and skew: walk the track in
// steps of Interleave, laying the IDs down in order from FirstSector and
// stepping past any position already taken.
//
// Which positions are taken used to be told by the ID written there being
// non-zero, but 0 is a sector ID like any other - the TS2068 format this app
// identifies starts at it, and an ID that runs past 255 wraps onto it. Writing
// one left its position looking empty, so a later sector overwrote it: with
// first sector 0, interleave 2 and ten sectors the track came out holding two
// of one ID, none of another, and an ID no sector should have had at all. What
// is taken is now tracked separately from what is stored.
procedure TDSKFormatSpecification.BuildSectorIDs;
var
  EIdx, LastSectorID: byte;
  SIdx: integer;
  Taken: array of boolean;
begin
  if SectorsPerTrack = 0 then
  begin
    SetLength(FSectorIDs, 0);
    exit;
  end;

  SIdx := 0;
  LastSectorID := FirstSector;

  SetLength(FSectorIDs, SectorsPerTrack);
  SetLength(Taken, SectorsPerTrack);
  for EIdx := 0 to SectorsPerTrack - 1 do
  begin
    FSectorIDs[EIdx] := 0;
    Taken[EIdx] := False;
  end;

  for EIdx := 0 to SectorsPerTrack - 1 do
  begin
    while Taken[SIdx mod SectorsPerTrack] do
      if Interleave > 0 then
        Inc(SIdx)
      else
      begin
        Dec(SIdx);
        if SIdx < 0 then
          SIdx := SectorsPerTrack + SIdx;
      end;

    FSectorIDs[SIdx mod SectorsPerTrack] := LastSectorID;
    Taken[SIdx mod SectorsPerTrack] := True;
    Inc(LastSectorID);
    SIdx := SIdx + Interleave;
    if SIdx < 0 then
      SIdx := SectorsPerTrack + SIdx;
  end;
end;

constructor TDSKFormatSpecification.Create(Format: integer);
begin
  inherited Create();

  // Amstrad PCW/Spectrum +3 CF2 (start from this)
  Name := 'Amstrad PCW/Spectrum +3';
  Sides := dsSideSingle;
  TracksPerSide := 40;
  SectorsPerTrack := 9;
  SectorSize := 512;
  GapRW := 42;
  GapFormat := 82;
  ResTracks := 1;
  DirBlocks := 2;
  BlockShift := 3;
  FillerByte := 229;
  FirstSector := 1;
  Interleave := 1;
  SkewSide := 0;
  SkewTrack := 0;
  RecordingMode := rmMFM;
  DataRate := drSingleOrDoubleDensity;

  // And make appropriate changes
  case Format of
    1:
    begin
      Name := 'Amstrad PCW CF2DD';
      Sides := dsSideDoubleAlternate;
      TracksPerSide := 80;
      DirBlocks := 2;
      BlockShift := 4;
    end;
    2:
    begin
      Name := 'Amstrad CPC System';
      ResTracks := 2;
      FirstSector := 65;
      Interleave := 2;
    end;
    3:
    begin
      Name := 'Amstrad CPC data';
      ResTracks := 0;
      FirstSector := 193;
      Interleave := 2;
    end;
    4:
    begin
      Name := 'HiForm 203/Ian High';
      TracksPerSide := 42;
      SectorsPerTrack := 10;
      GapFormat := 22;
      GapRW := 12;
      Interleave := 3;
    end;
    5:
    begin
      Name := 'SuperMat 192/XCF2';
      TracksPerSide := 40;
      SectorsPerTrack := 10;
      DirBlocks := 3;
      GapFormat := 23;
      GapRW := 12;
    end;
    6:
    begin
      Name := 'Ultra 208/Ian Max';
      TracksPerSide := 42;
      SectorsPerTrack := 10;
      DirBlocks := 2;
      ResTracks := 0;
      Interleave := 3;
      SkewTrack := 2;
      GapFormat := 22; // Puts 128 into the spec block!?
      GapRW := 12;
    end;
    7:
    begin
      Name := 'Amstrad CPC IBM';
      SectorsPerTrack := 8;
      FirstSector := 1;
      Interleave := 2;
      GapFormat := 80;
    end;
    8:
    begin
      Name := 'MGT Sam Coupe';
      Sides := dsSideDoubleAlternate;
      TracksPerSide := 80;
      SectorsPerTrack := 10;
    end;
  end;
  self.FDCSectorSize := GetFDCSectorSize(self.SectorSize);
end;

function ToDataRate(Value: integer): TDSKDataRate;
begin
  if (Value < Ord(Low(TDSKDataRate))) or (Value > Ord(High(TDSKDataRate))) then
    Result := drUnknown
  else
    Result := TDSKDataRate(Value);
end;

function ToRecordingMode(Value: integer): TDSKRecordingMode;
begin
  if (Value < Ord(Low(TDSKRecordingMode))) or (Value > Ord(High(TDSKRecordingMode))) then
    Result := rmUnknown
  else
    Result := TDSKRecordingMode(Value);
end;

function GetFDCSectorSize(SectorSize: word): byte;
var
  Idx: integer;
begin
  Result := High(FDCSectorSizes);
  for Idx := High(FDCSectorSizes) downto Low(FDCSectorSizes) do
    if SectorSize <= FDCSectorSizes[Idx] then
      Result := Idx;
end;

function GetFDCSizeBytes(FDCSize: byte): word;
begin
  if FDCSize > High(FDCSectorSizes) then
    Result := 0
  else
    Result := FDCSectorSizes[FDCSize];
end;

// The room a track takes in the file: its Track-Info block, plus its sector
// data rounded up to whole blocks. Both formats size tracks in these blocks, so
// this is what a header says about a track however much its sectors add up to.
function GetTrackFileSize(TrackDataSize: integer): integer;
begin
  Result := ((TrackDataSize + TrackBlockSize - 1) div TrackBlockSize + 1) * TrackBlockSize;
end;

end.
