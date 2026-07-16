unit DSKFormat;

interface

const
  // DSK file strings
  DiskInfoStandard = 'MV - CPCEMU Disk-File' + #13 + #10 + 'Disk-Info' + #13 + #10;
  DiskInfoExtended = 'EXTENDED CPC DSK File' + #13 + #10 + 'Disk-Info' + #13 + #10;
  DiskInfoTrack = 'Track-Info' + #13 + #10;
  DiskInfoTrackBroken = 'Track-Info   ';
  DiskSectorOffsetBlock = 'Offset-Info' + #13 + #10;
  CreatorSig = 'SPIN Disk Man';
  CreatorDU54 = 'Disk Image (DU54)' + #13 + #10;
  // DU54 writes its creator at offset 16 of the disk info block, where the
  // signature runs one byte past the end of that field and into the creator
  // one, so this is as much of it as can be matched within the block itself
  CreatorDU54InInfoBlock = 'Disk Image (DU54)' + #13;

  MaxTracks = 204;

  // Both formats measure a track in whole blocks of this size, counting the
  // Track-Info block as the first of them
  TrackBlockSize = 256;

  // Extended images give each track one byte of block count, so this is the
  // largest a track can be described as whatever the format
  MaxTrackFileSize = 255 * TrackBlockSize;

type
  // What is left of a 256 byte Track-Info block once its header is accounted
  // for, and so the only room a track has to describe its sectors
  TSectorInfoList = array[0..231] of byte;

  // DSK file format structure
  TDSKInfoBlock = packed record // Disk
    DiskInfoBlock: array[0..33] of char;
    Disk_Creator: array[0..13] of byte;  // diExtendedDSK only
    Disk_NumTracks: byte;
    Disk_NumSides: byte;
    Disk_StdTrackSize: word;            // diStandardDSK only
    Disk_ExtTrackSize: array[0..MaxTracks - 1] of byte; // diExtendedDSK only
  end;

  TTRKInfoBlock = packed record // Track
    TrackData: array[0..12] of char;
    TIB_pad1: array[0..2] of byte;
    TIB_TrackNum: byte;
    TIB_SideNum: byte;
    TIB_DataRate: byte;
    TIB_RecordingMode: byte;
    TIB_SectorSize: byte;
    TIB_NumSectors: byte;
    TIB_GapLength: byte;
    TIB_FillerByte: byte;
    SectorInfoList: TSectorInfoList;
    //    SectorData: array[0..65535] of byte;     // Read separately to avoid messing where Offset-Info should be
  end;

  TSCTInfoBlock = packed record // Sector
    SIB_TrackNum: byte;
    SIB_SideNum: byte;
    SIB_ID: byte;
    SIB_Size: byte;
    SIB_FDC1: byte;
    SIB_FDC2: byte;
    SIB_DataLength: word;
  end;

  TOFFInfoBlock = packed record // Offset Info (SAMdisk)
    OFF_Marker: array[0..12] of char;
    OFF_Unused: byte;
  end;

  TOFFTrackEntry = packed record
    OFF_TrackLength: word;
  end;

const
  // However many sectors a track claims, this is all it has entries for
  MaxTrackInfoSectors = SizeOf(TSectorInfoList) div SizeOf(TSCTInfoBlock);

implementation

end.
