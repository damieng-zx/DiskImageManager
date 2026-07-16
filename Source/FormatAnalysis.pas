unit FormatAnalysis;

{
  Disk Image Manager -  Copyright 2002-2009 Envy Technologies Ltd.

  Virtual disk format and protection analysis
}

interface

uses DskImage, SysUtils;

function AnalyseFormat(Disk: TDSKDisk): string;
function DetectUniformFormat(Disk: TDSKDisk): string;
function DetectProtection(Side: TDSKSide): string;
function DetectInterleave(Track: TDskTrack): string;

implementation

uses Utils;

function AnalyseFormat(Disk: TDSKDisk): string;
var
  Protection: string;
  Format: string;
begin
  if Disk.GetFirstSector = nil then
    Result := 'Unformatted'
  else
  begin
    Result := '';
    Format := '';
    Protection := DetectProtection(Disk.Side[0]);
    if (Disk.IsUniform(True)) then
      Format := DetectUniformFormat(Disk);
    if (Format <> '') then
      Result := Format;
    if (Protection <> '') then
      Result := Trim(Result + ' ' + Protection);
    if (Result = '') then
      Result := 'Unknown';
  end;
end;

const
  EINSTEIN_SIGNATURE: array[0..4] of byte = ($00, $E1, $00, $FB, $00);

// Whether the boot sector looks like a PCW/CPC disk specification (XDPB): a
// known spec id, and a sector size and count that agree with the track it sits
// on. Enough to trust the geometry it describes without naming the format.
function BootSectorIsXDPB(Track: TDSKTrack; Sector: TDSKSector): boolean;
begin
  Result := (Track <> nil) and (Sector <> nil)
    and (Sector.DataSize >= 10)               // room for the ten spec bytes
    and (Sector.Data[0] <= 3)                 // 0..3 PCW/CPC single/double
    and (Sector.Data[4] <= 6)                 // sector size code, 128..8192
    and (Sector.Data[3] = Track.Sectors)      // sectors per track agrees
    and ((128 shl Sector.Data[4]) = Sector.DataSize);
end;

// The usable capacity in whole KB the XDPB describes: every track bar the
// reserved ones, across both sides, of sector data. This mirrors the app's own
// TDSKSpecification.GetUsableCapacity (tracks less reserved, directory not
// deducted) and truncates to KB as StrFileSize does, so the figure agrees with
// the rest of the program.
function UsableCapacityKB(Disk: TDSKDisk; Sector: TDSKSector): integer;
var
  UsableTracks: integer;
  Bytes: int64;
begin
  UsableTracks := (Sector.Data[2] * Disk.Sides) - Sector.Data[5];
  if UsableTracks < 0 then UsableTracks := 0;
  Bytes := int64(UsableTracks) * Sector.Data[3] * (128 shl Sector.Data[4]);
  Result := Bytes div 1024;
end;

function DetectUniformFormat(Disk: TDSKDisk): string;
var
  FirstTrack: TDSKTrack;
  FirstSector: TDSKSector;
  SecondTrackFirstID: integer;
begin
  Result := '';

  // An image can advertise tracks yet hold no formatted sectors (e.g. a
  // 256-byte Extended DSK with an all-zero track-size table). There is no
  // first sector to fingerprint, so report it as unformatted rather than
  // dereferencing nil below.
  FirstTrack := Disk.GetLogicalTrack(0);
  if FirstTrack = nil then
  begin
    Result := 'Unformatted';
    exit;
  end;
  FirstSector := FirstTrack.GetFirstLogicalSector();
  if FirstSector = nil then
  begin
    Result := 'Unformatted';
    exit;
  end;

  // Amstrad formats (9 sectors, 512 size, SS or DS)
  if (FirstTrack.Sectors = 9) and (FirstSector.DataSize = 512) then
  begin
    case FirstSector.ID of
      1: begin
        Result := 'Amstrad PCW/Spectrum +3';
        case FirstSector.GetModChecksum(256) of
          1: Result := 'Amstrad PCW 9512';
          3: Result := 'Spectrum +3';
          255: Result := 'Amstrad PCW 8256';
        end;
        if (Disk.Sides = 1) then
          Result := Result + ' CF2'
        else
          Result := Result + ' CF2DD';
      end;
      65: Result := 'Amstrad CPC system';
      193: Result := 'Amstrad CPC data';
    end;

    // Add indicator where more tracks than normal
    if (Disk.Side[0].HighTrackCount > (Disk.Sides * 40)) then Result := Result + ' (oversized)';
    if (Disk.Side[0].HighTrackCount < (Disk.Sides * 40)) then Result := Result + ' (undersized)';
  end
  else
  begin
    // Other possible formats...
    case FirstSector.ID of
      1: if FirstTrack.Sectors = 8 then Result := 'Amstrad CPC IBM';
      65: Result := 'Amstrad CPC system custom (maybe)';
      193: Result := 'Amstrad CPC data custom (maybe)';
    end;
  end;

  // Custom speccy formats (10 sectors, SS)
  if (Disk.Sides = 1) and (FirstTrack.Sectors = 10) then
  begin
    // HiForm/Ultra208 (Chris Pile) + Ian Collier's skewed versions
    if (FirstSector.DataSize > 10) then
    begin
      // The skew tests below read the first sector of track 1, which a
      // single-track image has not got. An ID no sector can hold leaves the
      // skew unidentified rather than indexing past the side.
      SecondTrackFirstID := -1;
      if (Disk.Side[0].Tracks > 1) and (Disk.Side[0].Track[1].Sectors > 0) then
        SecondTrackFirstID := Disk.Side[0].Track[1].Sector[0].ID;

      if (FirstSector.Data[2] = 42) and (FirstSector.Data[8] = 12) then
        case FirstSector.Data[5] of
          0: if (FirstTrack.Sector[1].ID = 8) then
              case SecondTrackFirstID of
                7: Result := 'Ultra 208/Ian Max';
                8: Result := 'Maybe Ultra 208 or Ian Max (skew lost)';
                else
                  Result := 'Maybe Ultra 208 or Ian Max (custom skew)';
              end
            else
              Result := 'Possibly Ultra 208 or Ian Max (interleave lost)';
          1: if (FirstTrack.Sector[1].ID = 8) then
              case SecondTrackFirstID of
                7: Result := 'Ian High';
                1: Result := 'HiForm 203';
                else
                  Result := 'Maybe HiForm 203 or Ian High (custom skew)';
              end;
          else
            Result := 'Possibly HiForm or Ian High (interleave lost)';
        end;
      // Supermat 192 (Ian Cull)
      if (FirstSector.Data[7] = 3) and (FirstSector.Data[9] = 23) and (FirstSector.Data[2] = 40) then
        Result := 'Supermat 192/XCF2';
      // The same 192K Format program (identical boot banner) writes some disks
      // with two directory blocks and the standard +3 format gap instead of
      // XCF2's three and 23, so the spec block alone tells the variants apart.
      if (FirstSector.Data[7] = 2) and (FirstSector.Data[9] = 82) and (FirstSector.Data[2] = 40) then
        Result := 'Supermat 192 2/82';
    end;
  end;

  // Sam Coupe formats
  if (Disk.Sides = 2) and (FirstTrack.Sectors = 10) and (Disk.Side[0].HighTrackCount = 80) and
    (FirstSector.ID = 1) and (FirstSector.DataSize = 512) then
  begin
    Result := 'MGT SAM Coupe';
    if StrInByteArray(FirstSector.Data, 'BDOS', 232) then
      Result := Result + ' BDOS'
    else
      case FirstSector.Data[210] of
        0, 255: Result := Result + ' SAMDOS';
        else
          Result := Result + ' MasterDOS';
      end;
  end;

  // Einstein format
  if FirstSector.DataSize > 10 then
    if CompareMem(@FirstSector.Data, @EINSTEIN_SIGNATURE, Length(EINSTEIN_SIGNATURE)) then
      Result := 'Einstein';

  // Timex/Sinclair TS2068
  if ((FirstTrack.Sectors = 16) and (FirstSector.DataSize = 256) and (FirstSector.ID = 0)) then
     Result := 'TS2068';

  // Named nothing above, but a boot sector that is a valid disk specification
  // still says how big the disk it describes is. Report that rather than
  // nothing, so an unrecognised but well-formed disk is at least placed.
  if (Result = '') and BootSectorIsXDPB(FirstTrack, FirstSector) then
    Result := SysUtils.Format('Unknown %dKB XDPB format', [UsableCapacityKB(Disk, FirstSector)]);
end;

// ===========================================================================
// Copy protection detection
//
// This is an idiomatic Pascal port of the fingerprinting flow implemented in
// dskmanager-rust (src/protection.rs), itself a direct implementation of
// "Disk-Protection-Fingerprinting.md". It walks Track 0, classifies its
// geometry, and branches out only as far as needed.
//
// Mapping from the Rust model to the Disk Image Manager model:
//   Rust Disk (one disk side) -> TDSKSide
//   disk.get_track(t)         -> GetTrk(Side, t)   (nil when out of range)
//   track.get_sector_by_index -> GetSec(Track, i)  (nil when out of range)
//   sector.advertised_size()  -> AdvSize(Sector)   = 128 shl FDCSize
//   sector.actual_size()      -> Sector.DataSize
//   sector.is_deleted()       -> IsDeleted(Sector) = ST2 bit 6 (0x40)
//   sector.has_error()        -> SectorHasError(Sector)
//   ST1 / ST2 raw byte        -> Sector.FDCStatus[1] / Sector.FDCStatus[2]
// ===========================================================================

type
  TProtectionResult = record
    Found: boolean;
    Name: string;
    Reason: string;
  end;

  TT0Class = (t0SpeedlockPlus3, t0BigSector, t0TenSector, t0TenSectorDDAM,
    t0EighteenSector, t0SixteenSector, t0NineteenSector, t0EightSector,
    t0FiveSector, t0Speedlock9x512, t0Standard);

// --- Result constructors (mirror ProtectionResult::confirmed/probable/maybe) ---

function ProtNone: TProtectionResult;
begin
  Result.Found := False;
  Result.Name := '';
  Result.Reason := '';
end;

function ProtConfirmed(AName, AReason: string): TProtectionResult;
begin
  Result.Found := True;
  Result.Name := AName;
  Result.Reason := AReason;
end;

function ProtProbable(AName, AReason: string): TProtectionResult;
begin
  Result.Found := True;
  Result.Name := AName;
  Result.Reason := 'probably, ' + AReason;
end;

function ProtMaybe(AName, AReason: string): TProtectionResult;
begin
  Result.Found := True;
  Result.Name := AName;
  Result.Reason := 'maybe, ' + AReason;
end;

function ProtToStr(R: TProtectionResult): string;
begin
  if R.Found then
    Result := SysUtils.Format('%s (%s)', [R.Name, R.Reason])
  else
    Result := '';
end;

// --- Geometry / FDC helpers ------------------------------------------------

// Advertised size from the FDC size code N: 128 << N (matches Rust advertised_size).
// Note: TDSKSector.AdvertisedSize is the on-disk record length, NOT this value.
function AdvSize(S: TDSKSector): integer;
begin
  if S.FDCSize <= 8 then
    Result := 128 shl S.FDCSize
  else
    Result := 0;
end;

function IsDeleted(S: TDSKSector): boolean;
begin
  Result := (S.FDCStatus[2] and $40) <> 0;
end;

// Any FDC error: ST1 non-zero, or ST2 non-zero ignoring the deleted-data mark.
function SectorHasError(S: TDSKSector): boolean;
begin
  Result := (S.FDCStatus[1] <> 0) or ((S.FDCStatus[2] and $BF) <> 0);
end;

function GetTrk(Side: TDSKSide; T: integer): TDSKTrack;
begin
  if (T >= 0) and (T < Side.Tracks) then
    Result := Side.Track[T]
  else
    Result := nil;
end;

function GetSec(Track: TDSKTrack; I: integer): TDSKSector;
begin
  if (Track <> nil) and (I >= 0) and (I < Track.Sectors) then
    Result := Track.Sector[I]
  else
    Result := nil;
end;

function IsCpcDisk(T0: TDSKTrack): boolean;
var
  S0: TDSKSector;
begin
  S0 := GetSec(T0, 0);
  Result := (S0 <> nil) and (S0.ID >= 65);
end;

function AnyDeleted(Track: TDSKTrack): boolean;
var
  I: integer;
begin
  Result := False;
  if Track = nil then exit;
  for I := 0 to Track.Sectors - 1 do
    if IsDeleted(Track.Sector[I]) then
    begin
      Result := True;
      exit;
    end;
end;

function TrackHasError(Track: TDSKTrack): boolean;
var
  I: integer;
begin
  Result := False;
  if Track = nil then exit;
  for I := 0 to Track.Sectors - 1 do
    if SectorHasError(Track.Sector[I]) then
    begin
      Result := True;
      exit;
    end;
end;

// Common advertised sector size, or -1 when empty / non-uniform (mirrors
// Rust uniform_sector_size returning None in both those cases).
function UniformAdvSize(Track: TDSKTrack): integer;
var
  I, First: integer;
begin
  if (Track = nil) or (Track.Sectors = 0) then
  begin
    Result := -1;
    exit;
  end;
  First := AdvSize(Track.Sector[0]);
  for I := 1 to Track.Sectors - 1 do
    if AdvSize(Track.Sector[I]) <> First then
    begin
      Result := -1;
      exit;
    end;
  Result := First;
end;

function LastFormattedTrack(Side: TDSKSide): integer;
var
  T: integer;
  Track: TDSKTrack;
begin
  Result := -1;
  for T := 0 to Side.Tracks - 1 do
  begin
    Track := GetTrk(Side, T);
    if (Track <> nil) and (Track.Sectors > 0) then Result := T;
  end;
end;

// Whether every formatted track has the shape the first one has.
//
// The tracks past the last formatted one are not part of that shape. An imager
// reads a fixed number of tracks, so a 40 track disk read as 42 ends in a tail
// of unformatted ones that says nothing about the disk. Counting the tail as a
// shape of its own made every such disk non-uniform, and a bad sector anywhere
// on one was then reported as unknown copy protection.
//
// An unformatted track with formatted tracks still to come is a hole, not a
// tail, and does mean something: an empty track 1 is how the P.M.S. and Paul
// Owens loaders show up, so it has to go on counting as non-uniform.
function SideIsUniform(Side: TDSKSide): boolean;
var
  Sc, Sz, T, Last: integer;
  First: TDSKTrack;
  Track: TDSKTrack;
begin
  Result := True;
  if Side.Tracks = 0 then exit;
  First := GetTrk(Side, 0);
  if First = nil then exit;
  Sc := First.Sectors;
  Sz := UniformAdvSize(First);
  Last := LastFormattedTrack(Side);
  for T := 1 to Last do
  begin
    Track := GetTrk(Side, T);
    if Track = nil then continue;
    if (Track.Sectors <> Sc) or (UniformAdvSize(Track) <> Sz) then
    begin
      Result := False;
      exit;
    end;
  end;
end;

function SideHasFDCErrors(Side: TDSKSide): boolean;
var
  T: integer;
begin
  Result := False;
  for T := 0 to Side.Tracks - 1 do
    if TrackHasError(GetTrk(Side, T)) then
    begin
      Result := True;
      exit;
    end;
end;

// 16 sectors with a full CHRN ramp: id == track == side == size == index.
function IsDiscSysTrack(Track: TDSKTrack): boolean;
var
  I: integer;
  S: TDSKSector;
begin
  Result := False;
  if (Track = nil) or (Track.Sectors <> 16) then exit;
  for I := 0 to 15 do
  begin
    S := Track.Sector[I];
    if not ((S.ID = I) and (S.Track = I) and (S.Side = I) and (S.FDCSize = I)) then exit;
  end;
  Result := True;
end;

// 16 sectors with the weaker Players ramp: id == size == index.
function IsPlayersTrack(Track: TDSKTrack): boolean;
var
  I: integer;
  S: TDSKSector;
begin
  Result := False;
  if (Track = nil) or (Track.Sectors <> 16) then exit;
  for I := 0 to 15 do
  begin
    S := Track.Sector[I];
    if not ((S.ID = I) and (S.FDCSize = I)) then exit;
  end;
  Result := True;
end;

function LargestTrackDataSize(Side: TDSKSide): integer;
var
  T, S, Sum: integer;
  Track: TDSKTrack;
begin
  Result := 0;
  for T := 0 to Side.Tracks - 1 do
  begin
    Track := GetTrk(Side, T);
    if Track = nil then continue;
    Sum := 0;
    for S := 0 to Track.Sectors - 1 do
      Sum := Sum + Track.Sector[S].DataSize;
    if Sum > Result then Result := Sum;
  end;
end;

// --- T0 classification (spec 3.2) ------------------------------------------

function ClassifyT0(T0: TDSKTrack): TT0Class;
var
  Sc, I: integer;
  S0, S8, S: TDSKSector;
  HiFiller, WeakUnder: boolean;
begin
  Sc := T0.Sectors;

  // 10-sector cases are more specific than the >= 7 + DDAM check below.
  if Sc = 10 then
  begin
    S8 := GetSec(T0, 8);
    if (S8 <> nil) and (S8.DataSize = 512) then
    begin
      if AnyDeleted(T0) then
        Result := t0TenSectorDDAM
      else
        Result := t0TenSector;
      exit;
    end;
  end;

  if (Sc >= 7) and AnyDeleted(T0) then
  begin
    Result := t0SpeedlockPlus3;
    exit;
  end;

  if Sc = 1 then
  begin
    S0 := GetSec(T0, 0);
    if (S0 <> nil) and (S0.FDCSize = 6) and (S0.FDCStatus[1] = $20) then
    begin
      Result := t0BigSector;
      exit;
    end;
  end;

  if Sc = 18 then begin Result := t0EighteenSector; exit; end;
  if Sc = 19 then begin Result := t0NineteenSector; exit; end;
  if Sc = 16 then begin Result := t0SixteenSector; exit; end;

  if Sc = 8 then
  begin
    Result := t0EightSector;
    for I := 0 to T0.Sectors - 1 do
      if AdvSize(T0.Sector[I]) <> 512 then
      begin
        Result := t0Standard;
        break;
      end;
    if Result = t0EightSector then exit;
  end;

  if Sc = 5 then
  begin
    Result := t0FiveSector;
    for I := 0 to T0.Sectors - 1 do
      if AdvSize(T0.Sector[I]) <> 1024 then
      begin
        Result := t0Standard;
        break;
      end;
    if Result = t0FiveSector then exit;
  end;

  // Speedlock 9x512 variant: high-ID fillers + a weak N=0 sector.
  HiFiller := False;
  WeakUnder := False;
  for I := 0 to T0.Sectors - 1 do
  begin
    S := T0.Sector[I];
    if (S.ID >= $80) and (S.ID < $C1) and (S.FDCSize = 2) then HiFiller := True;
    if (S.FDCSize = 0) and (((S.FDCStatus[1] and $20) <> 0) or ((S.FDCStatus[2] and $20) <> 0)) then
      WeakUnder := True;
  end;
  if HiFiller and WeakUnder then
    Result := t0Speedlock9x512
  else
    Result := t0Standard;
end;

// --- Step 1a: T0 signature scan (spec 3.1) ---------------------------------

function ScanT0Signatures(T0: TDSKTrack): TProtectionResult;
var
  S0, S2, S7, Sector: TDSKSector;
  SIdx: integer;
  TiAddr, TiPhone: string;
begin
  Result := ProtNone;
  S0 := GetSec(T0, 0);
  if S0 = nil then exit;

  // Alkatraz +3 (note: 1 leading, 3 mid, 2 mid spaces)
  if StrBufPos(S0.Data, ' THE ALKATRAZ PROTECTION SYSTEM   (C) 1987  Appleby Associates') > -1 then
  begin
    Result := ProtConfirmed('Alkatraz +3', 'signed T0/S0');
    exit;
  end;

  // Three Inch Loader
  TiAddr := '***Loader Copyright Three Inch Software 1988, All Rights Reserved. Three Inch Software, 73 Surbiton Road, Kingston upon Thames, KT1 2HG***';
  TiPhone := '***Loader Copyright Three Inch Software 1988, All Rights Reserved. 01-546 2754';

  if StrBufPos(S0.Data, TiAddr) > -1 then
  begin
    Result := ProtConfirmed('Three Inch Loader type 1', 'signed T0/S0');
    exit;
  end;
  if T0.Sectors > 7 then
  begin
    S7 := GetSec(T0, 7);
    if (S7 <> nil) and (StrBufPos(S7.Data, TiAddr) > -1) then
    begin
      Result := ProtConfirmed('Three Inch Loader type 1-0-7', 'signed T0/S7');
      exit;
    end;
  end;
  if StrBufPos(S0.Data, TiPhone) > -1 then
  begin
    Result := ProtConfirmed('Three Inch Loader type 2', 'signed T0/S0');
    exit;
  end;

  // Laser Load (3 spaces after Load, 4 after Computer)
  if T0.Sectors > 2 then
  begin
    S2 := GetSec(T0, 2);
    if (S2 <> nil) and (StrBufPos(S2.Data, 'Laser Load   By C.J.Pink For Consult Computer    Systems') > -1) then
    begin
      Result := ProtConfirmed('Laser Load by C.J. Pink', 'signed T0/S2');
      exit;
    end;
  end;

  // P.M.S.
  if StrBufPos(S0.Data, '[C] P.M.S. 1986') > -1 then
  begin
    Result := ProtConfirmed('P.M.S. 1986', 'signed T0/S0');
    exit;
  end;
  if StrBufPos(S0.Data, 'P.M.S. LOADER [C]1986') > -1 then
  begin
    Result := ProtConfirmed('P.M.S. Loader 1986 v1', 'signed T0/S0');
    exit;
  end;
  if StrBufPos(S0.Data, 'P.M.S.LOADER [C]1986') > -1 then
  begin
    Result := ProtConfirmed('P.M.S. Loader 1986 v2', 'signed T0/S0');
    exit;
  end;
  if StrBufPos(S0.Data, 'P.M.S.LOADER [C]1987') > -1 then
  begin
    Result := ProtConfirmed('P.M.S. 1987', 'signed T0/S0');
    exit;
  end;

  // ERE / Remi HERBULOT
  if T0.Sectors > 6 then
    for SIdx := 0 to T0.Sectors - 1 do
    begin
      Sector := GetSec(T0, SIdx);
      if Sector = nil then continue;
      if StrBufPos(Sector.Data, 'PROTECTION      Remi HERBULOT') > -1 then
      begin
        Result := ProtConfirmed('ERE/Remi HERBULOT', 'signed T0');
        exit;
      end;
      if StrBufPos(Sector.Data, 'PROTECTION  V2.1Remi HERBULOT') > -1 then
      begin
        Result := ProtConfirmed('ERE/Remi HERBULOT 2.1', 'signed T0');
        exit;
      end;
    end;

  // ARMOURLOC ("0K free" exactly at offset 2)
  if (T0.Sectors = 9) and (StrBufPos(S0.Data, '0K free') = 2) then
  begin
    Result := ProtConfirmed('ARMOURLOC', 'anti-hacker protection');
    exit;
  end;

  // Studio B
  if StrBufPos(S0.Data, 'Disc format (c) 1986 Studio B Ltd.') > -1 then
  begin
    Result := ProtConfirmed('Studio B Disc format', 'signed T0/S0');
    exit;
  end;
end;

// --- Step 1 resolvers (spec 4) ---------------------------------------------

// 4.1 - T0 has deleted marks (Speedlock +3)
function ResolveSpeedlockPlus3(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  T1: TDSKTrack;
  T1S0, S6, S8: TDSKSector;
begin
  Result := ProtNone;
  T1 := GetTrk(Side, 1);
  if (T1 = nil) or (T1.Sectors <> 5) then exit;
  T1S0 := GetSec(T1, 0);
  if (T1S0 = nil) or (AdvSize(T1S0) <> 1024) then exit;

  if T0.Sectors = 9 then
  begin
    S6 := GetSec(T0, 6);
    S8 := GetSec(T0, 8);
    if (S6 <> nil) and (S8 <> nil) then
    begin
      if (S6.FDCStatus[2] = $40) and (S8.FDCStatus[2] = $00) then
      begin
        Result := ProtProbable('Speedlock +3 1987', 'unsigned');
        exit;
      end;
      if (S6.FDCStatus[2] = $40) and (S8.FDCStatus[2] = $40) then
      begin
        Result := ProtProbable('Speedlock +3 1988', 'unsigned');
        exit;
      end;
    end;
  end;

  Result := ProtProbable('Speedlock +3 1987/1988',
    SysUtils.Format('unsigned (T0=%d sectors with deleted data)', [T0.Sectors]));
end;

// 4.2 - T0 is 1 giant weak sector
function ResolveBigSector(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  Cpc: boolean;
  T1: TDSKTrack;
  T1S0: TDSKSector;
begin
  Cpc := IsCpcDisk(T0);
  T1 := GetTrk(Side, 1);
  if (T1 <> nil) and (T1.Sectors = 1) then
  begin
    T1S0 := GetSec(T1, 0);
    if (T1S0 <> nil) and (T1S0.FDCStatus[1] = $20) then
    begin
      if Cpc then
        Result := ProtProbable('Hexagon', 'CPC big-sector engine')
      else
        Result := ProtProbable('Speedlock 1989/1990', '+3 big-sector engine');
      exit;
    end;
  end;

  if Cpc then
    Result := ProtProbable('Hexagon', 'CPC, T0 big sector')
  else
    Result := ProtProbable('Speedlock 1989/1990', '+3, T0 big sector');
end;

// 4.3 - T0 has 10 clean sectors, no DDAM (Hexagon)
function ResolveHexagon(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  Cpc: boolean;
  Limit, T, SIdx: integer;
  Track: TDSKTrack;
  S0, Sector: TDSKSector;
begin
  Result := ProtNone;
  Cpc := IsCpcDisk(T0);
  if Side.Tracks < 4 then Limit := Side.Tracks else Limit := 4;
  for T := 0 to Limit - 1 do
  begin
    Track := GetTrk(Side, T);
    if Track = nil then continue;

    for SIdx := 0 to Track.Sectors - 1 do
    begin
      Sector := Track.Sector[SIdx];
      if StrBufPos(Sector.Data, 'HEXAGON DISK PROTECTION c 1989') > -1 then
      begin
        Result := ProtConfirmed('Hexagon', SysUtils.Format('signed T%d/S%d', [T, SIdx]));
        exit;
      end;
      if StrBufPos(Sector.Data, 'HEXAGON Disk Protection c 1989') > -1 then
      begin
        Result := ProtConfirmed('Hexagon', SysUtils.Format('signed T%d/S%d', [T, SIdx]));
        exit;
      end;
    end;

    // Unsigned: single oversized sector with N=6, ST1=0x20, ST2=0x60
    if Track.Sectors = 1 then
    begin
      S0 := GetSec(Track, 0);
      if (S0 <> nil) and (S0.FDCSize = 6) and (S0.FDCStatus[1] = $20) and (S0.FDCStatus[2] = $60) then
      begin
        if Cpc then
          Result := ProtProbable('Hexagon', 'CPC, unsigned')
        else
          Result := ProtProbable('Hexagon', 'unsigned');
        exit;
      end;
    end;
  end;
end;

// 4.3b - T0 has 10 sectors with DDAM (Speedlock 1989 CPC)
function ResolveSpeedlock1989Cpc(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  Cpc: boolean;
  T1: TDSKTrack;
  T1S0: TDSKSector;
begin
  Result := ProtNone;
  Cpc := IsCpcDisk(T0);
  T1 := GetTrk(Side, 1);

  if Cpc then
  begin
    if (T1 <> nil) and (T1.Sectors = 1) then
    begin
      T1S0 := GetSec(T1, 0);
      if (T1S0 <> nil) and (T1S0.FDCStatus[1] = $20) then
      begin
        Result := ProtProbable('Speedlock 1989', 'CPC, 10-sector T0 + DDAM + big-sector T1');
        exit;
      end;
    end;
    Result := ProtProbable('Speedlock 1989', 'CPC, 10-sector T0 + DDAM');
    exit;
  end;

  if (T1 <> nil) and (T1.Sectors = 1) then
  begin
    T1S0 := GetSec(T1, 0);
    if (T1S0 <> nil) and (T1S0.FDCStatus[1] = $20) then
      Result := ProtProbable('Speedlock 1989/1990', '+3, 10-sector T0 + DDAM + big-sector T1');
  end;
end;

// 4.4 - T0 has 18 sectors (Alkatraz CPC)
function Resolve18Sector(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  S0, T1S0: TDSKSector;
  T1: TDSKTrack;
begin
  S0 := GetSec(T0, 0);
  if (S0 <> nil) and ((S0.DataSize = 256) or (AdvSize(S0) = 256)) then
  begin
    Result := ProtConfirmed('Alkatraz CPC', '18-sector T0, 256B sectors');
    exit;
  end;

  T1 := GetTrk(Side, 1);
  if (T1 <> nil) and (T1.Sectors > 0) then
  begin
    T1S0 := GetSec(T1, 0);
    if (T1S0 <> nil) and (T1S0.FDCStatus[2] = $40) then
    begin
      Result := ProtConfirmed('Alkatraz CPC', '18-sector T0');
      exit;
    end;
  end;

  Result := ProtMaybe('18-sector track', 'unknown scheme');
end;

// 4.5 - T0 has 16 sectors (DiscSYS / Players / Mean PS)
function Resolve16Sector(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  SIdx: integer;
  Sector, S4: TDSKSector;
  T2: TDSKTrack;
  Reason, Cleaned: string;
begin
  Result := ProtNone;

  if IsDiscSysTrack(T0) then
  begin
    for SIdx := 0 to T0.Sectors - 1 do
    begin
      Sector := T0.Sector[SIdx];
      if StrBufPos(Sector.Data, 'MEAN PROTECTION SYSTEM') > -1 then
      begin
        Result := ProtConfirmed('Mean Protection System', 'signed T0');
        exit;
      end;
    end;

    Reason := '16-sector CHRN ramp on T0';
    T2 := GetTrk(Side, 2);
    if T2 <> nil then
    begin
      S4 := GetSec(T2, 4);
      if (S4 <> nil) and (S4.DataSize > 160) then
      begin
        Cleaned := StrBlockClean(S4.Data, 85, 22).Trim();
        if Cleaned.StartsWith('discsys', True) and (Length(Cleaned) > 8) then
          Reason := Reason + ' (' + Cleaned.Substring(8).Trim() + ')'
        else if Cleaned.StartsWith('multi-', True) then
          Reason := Reason + ' (' + Cleaned + ')';
      end;
    end;

    Result := ProtConfirmed('DiscSYS', Reason);
    exit;
  end;

  if IsPlayersTrack(T0) then
  begin
    Result := ProtMaybe('Players',
      SysUtils.Format('super-sized %d byte track', [LargestTrackDataSize(Side)]));
    exit;
  end;
end;

// 4.6 - T0 has 19 sectors (KBI-19 / CAAV)
function Resolve19Sector(T0: TDSKTrack): TProtectionResult;
var
  S0, S1: TDSKSector;
begin
  if T0.Sectors > 1 then
  begin
    S1 := GetSec(T0, 1);
    if (S1 <> nil) and (StrBufPos(S1.Data, '(c) 1986 for KBI ') > -1) then
    begin
      Result := ProtConfirmed('KBI-19', 'signed T0/S1');
      exit;
    end;
  end;

  S0 := GetSec(T0, 0);
  if (S0 <> nil) and (StrBufPos(S0.Data, 'ALAIN LAURENT GENERATION 5 1989') > -1) then
  begin
    Result := ProtConfirmed('CAAV', 'signed T0/S0');
    exit;
  end;

  Result := ProtProbable('KBI-19 or CAAV', 'unsigned, 19-sector T0');
end;

// 4.7 - T0 has 8 x 512-byte sectors (unsigned Alkatraz +3 or CPC)
function Resolve8Sector(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  Cpc: boolean;
  T1, Ht: TDSKTrack;
  T1S0, Hs0: TDSKSector;
  Limit, T: integer;
  AName: string;
begin
  Result := ProtNone;
  Cpc := IsCpcDisk(T0);

  T1 := GetTrk(Side, 1);
  if T1 = nil then exit;
  if T1.Sectors <> 8 then exit;
  T1S0 := GetSec(T1, 0);
  if (T1S0 = nil) or (AdvSize(T1S0) <> 512) then exit;

  if Side.Tracks < 42 then Limit := Side.Tracks else Limit := 42;
  for T := 2 to Limit - 1 do
  begin
    Ht := GetTrk(Side, T);
    if Ht = nil then continue;
    if Ht.Sectors = 18 then
    begin
      Hs0 := GetSec(Ht, 0);
      if (Hs0 <> nil) and ((AdvSize(Hs0) = 256) or (Hs0.DataSize = 256)) then
      begin
        if Cpc then AName := 'Alkatraz CPC' else AName := 'Alkatraz +3';
        Result := ProtProbable(AName,
          SysUtils.Format('unsigned (8-sector data + 18-sector protection at T%d)', [T]));
        exit;
      end;
      break;
    end;
    if Ht.Sectors = 8 then continue;
    if Ht.Sectors = 9 then break;
  end;

  if Cpc then exit;
  Result := ProtMaybe('Alkatraz +3', 'unsigned (uniform 8x512 data tracks, no signature found)');
end;

// 4.8 - T0 has 5 x 1024-byte sectors (unsigned Speedlock data side)
function Resolve5Sector(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  Cpc: boolean;
  T1: TDSKTrack;
  T1S0: TDSKSector;
begin
  Result := ProtNone;
  Cpc := IsCpcDisk(T0);

  T1 := GetTrk(Side, 1);
  if (T1 <> nil) and (T1.Sectors = 5) then
  begin
    T1S0 := GetSec(T1, 0);
    if (T1S0 <> nil) and (AdvSize(T1S0) = 1024) then
    begin
      if Cpc then
        Result := ProtProbable('Speedlock (CPC)', 'unsigned data side (5x1024 uniform)')
      else
        Result := ProtProbable('Speedlock +3 1987/1988', 'unsigned data side (5x1024 uniform)');
    end;
  end;
end;

// Speedlock 9x512 variant: high-ID fillers + weak N=0 sector, DDAM bulk data
function ResolveSpeedlock9x512(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  Limit, T: integer;
begin
  Result := ProtNone;
  if Side.Tracks < 40 then Limit := Side.Tracks else Limit := 40;
  for T := 4 to Limit - 1 do
    if AnyDeleted(GetTrk(Side, T)) then
    begin
      Result := ProtConfirmed('Speedlock +3 1987',
        '9x512 variant: high-ID T0 sectors + weak N=0 sector, DDAM data');
      exit;
    end;
end;

// --- Step 2 resolvers (spec 5) ---------------------------------------------

// 5.1 - T1 is empty (track-1-gap family)
function ResolveEmptyT1Family(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  T2: TDSKTrack;
  S2, T2S0, Sector: TDSKSector;
  Sig: string;
  SIdx: integer;
begin
  T2 := GetTrk(Side, 2);
  if T2 = nil then
  begin
    Result := ProtMaybe('P.M.S. Loader 1986/1987', 'unsigned (T0 used / T1 empty / T2 missing)');
    exit;
  end;

  Sig := 'PAUL OWENS' + #128 + 'PROTECTION SYS';
  if T0.Sectors = 9 then
  begin
    S2 := GetSec(T0, 2);
    if (S2 <> nil) and (StrBufPos(S2.Data, Sig) > -1) then
    begin
      Result := ProtConfirmed('Paul Owens', 'signed T0/S2');
      exit;
    end;
  end;

  if T2.Sectors > 0 then
  begin
    T2S0 := GetSec(T2, 0);
    if (T2S0 <> nil) and (StrBufPos(T2S0.Data, 'DISCLOC') > -1) then
    begin
      Result := ProtConfirmed('DiscLoc/Oddball', 'signed T2/S0');
      exit;
    end;
  end;

  if IsDiscSysTrack(T2) then
    for SIdx := 0 to T0.Sectors - 1 do
    begin
      Sector := GetSec(T0, SIdx);
      if (Sector <> nil) and (StrBufPos(Sector.Data, 'MEAN PROTECTION SYSTEM') > -1) then
      begin
        Result := ProtConfirmed('Mean Protection System', 'signed T0 + DiscSYS T2');
        exit;
      end;
    end;

  if T2.Sectors = 6 then
  begin
    T2S0 := GetSec(T2, 0);
    if (T2S0 <> nil) and (T2S0.DataSize = 256) then
    begin
      Result := ProtProbable('Paul Owens', 'unsigned');
      exit;
    end;
  end;

  Result := ProtMaybe('P.M.S. Loader 1986/1987', 'unsigned (T0 used / T1 empty / T2 used)');
end;

// 5.2 - T1 is 5 x 1024, T0 has no DDAM (Speedlock data side)
function ResolveSpeedlock5x1024(T0, T1: TDSKTrack): TProtectionResult;
begin
  Result := ProtNone;
  if AnyDeleted(T0) then exit;
  if IsCpcDisk(T0) then
    Result := ProtProbable('Speedlock (CPC)', 'data side (5x1024 T1, no deleted-data marks on T0)')
  else
    Result := ProtProbable('Speedlock +3 1987/1988', 'data side (5x1024 T1, no deleted-data marks on T0)');
end;

// 5.3 - T1 is 1 weak big sector
function ResolveSpeedlock1989(T0, T1: TDSKTrack): TProtectionResult;
var
  Cpc, HasDdam: boolean;
begin
  Cpc := IsCpcDisk(T0);
  HasDdam := AnyDeleted(T0);

  if Cpc then
    Result := ProtProbable('Hexagon', 'CPC, standard T0 + big-sector T1')
  else if HasDdam then
    Result := ProtProbable('Speedlock 1989/1990', '+3, T0 DDAM + big-sector T1')
  else
    Result := ProtProbable('Speedlock 1989/1990', '+3, standard T0 + big-sector T1');
end;

// --- Step 3: high-track probes (spec 6) ------------------------------------

function ScanHighTracks(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  Tc, Offset, SIdx: integer;
  T1, T3, T8, T9, T38, T39, T40: TDSKTrack;
  T3S0, S9, T0S0, Sector, S4: TDSKSector;
  Sig: string;
begin
  Result := ProtNone;
  Tc := Side.Tracks;

  // Amsoft/EXOPAL - T3/S0
  if Tc > 3 then
  begin
    T3 := GetTrk(Side, 3);
    if (T3 <> nil) and (T3.Sectors > 0) then
    begin
      T3S0 := GetSec(T3, 0);
      if (T3S0 <> nil) and (T3S0.DataSize = 512) then
      begin
        Offset := StrBufPos(T3S0.Data, 'Amsoft disc protection system');
        if (Offset > 1) and (StrBufPos(T3S0.Data, 'EXOPAL') > -1) then
        begin
          Result := ProtConfirmed('Amsoft/EXOPAL', 'signed T3/S0');
          exit;
        end;
      end;
    end;
  end;

  // W.R.M - T8/S9
  if Tc > 9 then
  begin
    T8 := GetTrk(Side, 8);
    if (T8 <> nil) and (T8.Sectors > 9) then
    begin
      S9 := GetSec(T8, 9);
      if (S9 <> nil) and (S9.DataSize > 128) then
        if (StrBufPos(S9.Data, 'W.R.M Disc') = 0) and
           (StrBufPos(S9.Data, 'Protection') > -1) and
           (StrBufPos(S9.Data, 'System (c) 1987') > -1) then
        begin
          Result := ProtConfirmed('W.R.M Disc Protection', 'signed T8/S9');
          exit;
        end;
    end;
  end;

  // Frontier (unsigned) - T9
  if Tc > 10 then
  begin
    T9 := GetTrk(Side, 9);
    if (T9 <> nil) and (T9.Sectors = 1) then
    begin
      T0S0 := GetSec(T0, 0);
      if (T0S0 <> nil) and (T0S0.DataSize = 4096) and (T0S0.FDCStatus[1] = 0) then
      begin
        Result := ProtProbable('Frontier', 'unsigned (T9 single sector, T0/S0 = 4096)');
        exit;
      end;
    end;
  end;

  // Frontier (signed) and Three Inch Loader type 3-1-4 - both on T1
  if Tc > 1 then
  begin
    T1 := GetTrk(Side, 1);
    if T1 <> nil then
    begin
      for SIdx := 0 to T1.Sectors - 1 do
      begin
        Sector := T1.Sector[SIdx];
        if StrBufPos(Sector.Data, 'NEW DISK PROTECTION SYSTEM. (C) 1990 BY NEW FRONTIER SOFT.') > -1 then
        begin
          Result := ProtConfirmed('Frontier', 'signed T1');
          exit;
        end;
      end;

      if T1.Sectors > 4 then
      begin
        S4 := GetSec(T1, 4);
        if S4 <> nil then
        begin
          Sig := 'Loader ' + #127 + '1988 Three Inch Software';
          if StrBufPos(S4.Data, Sig) > -1 then
          begin
            Result := ProtConfirmed('Three Inch Loader type 3-1-4', 'signed T1/S4');
            exit;
          end;
        end;
      end;
    end;
  end;

  // KBI-10 - T38 + T39
  if Tc >= 40 then
  begin
    T38 := GetTrk(Side, 38);
    T39 := GetTrk(Side, 39);
    if (T38 <> nil) and (T39 <> nil) and (T39.Sectors = 10) and (T38.Sectors = 9) then
    begin
      S9 := GetSec(T39, 9);
      if (S9 <> nil) and (S9.FDCStatus[1] = $20) and (S9.FDCStatus[2] = $20) then
      begin
        Result := ProtProbable('KBI-10', 'weak sector T39/S9');
        exit;
      end;
    end;
  end;

  // Infogrames/Logiciel - T39
  if Tc > 39 then
  begin
    T39 := GetTrk(Side, 39);
    if (T39 <> nil) and (T39.Sectors = 9) then
      for SIdx := 0 to T39.Sectors - 1 do
      begin
        Sector := T39.Sector[SIdx];
        if (Sector.FDCSize = 2) and (Sector.DataSize = 540) then
        begin
          Result := ProtProbable('Infogrames/Logiciel', SysUtils.Format('gap data sector T39/S%d', [SIdx]));
          exit;
        end;
      end;
  end;

  // Rainbow Arts - T40
  if Tc > 40 then
  begin
    T40 := GetTrk(Side, 40);
    if (T40 <> nil) and (T40.Sectors = 9) then
      for SIdx := 0 to T40.Sectors - 1 do
      begin
        Sector := T40.Sector[SIdx];
        if (Sector.ID = 198) and (Sector.FDCStatus[1] = $20) and (Sector.FDCStatus[2] = $20) then
        begin
          Result := ProtProbable('Rainbow Arts', SysUtils.Format('weak sector T40/S%d', [SIdx]));
          exit;
        end;
      end;
  end;
end;

// --- Step 4: mid-disk odd-sector sweep (spec 7) ----------------------------

function SweepMidDisk(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  Cpc: boolean;
  Limit, T: integer;
  Ht: TDSKTrack;
  Hs0, S0, S1: TDSKSector;
  AName: string;
begin
  Result := ProtNone;
  Cpc := IsCpcDisk(T0);
  if Side.Tracks < 42 then Limit := Side.Tracks else Limit := 42;

  for T := 2 to Limit - 1 do
  begin
    Ht := GetTrk(Side, T);
    if Ht = nil then continue;
    if (Ht.Sectors = 0) or (Ht.Sectors = 9) then continue;

    // 18-sector -> Alkatraz CPC
    if Ht.Sectors = 18 then
    begin
      Hs0 := GetSec(Ht, 0);
      if (Hs0 <> nil) and ((Hs0.DataSize = 256) or (AdvSize(Hs0) = 256)) then
      begin
        Result := ProtConfirmed('Alkatraz CPC', SysUtils.Format('18-sector T%d', [T]));
        exit;
      end;
    end;

    // 16-sector -> DiscSYS or Players
    if Ht.Sectors = 16 then
    begin
      if IsDiscSysTrack(Ht) then
      begin
        Result := ProtConfirmed('DiscSYS', SysUtils.Format('16-sector CHRN ramp at T%d', [T]));
        exit;
      end;
      if IsPlayersTrack(Ht) then
      begin
        Result := ProtMaybe('Players', SysUtils.Format('16-sector id==size at T%d', [T]));
        exit;
      end;
    end;

    // 19-sector -> KBI-19 / CAAV
    if Ht.Sectors = 19 then
    begin
      if Ht.Sectors > 1 then
      begin
        S1 := GetSec(Ht, 1);
        if (S1 <> nil) and (StrBufPos(S1.Data, '(c) 1986 for KBI ') > -1) then
        begin
          Result := ProtConfirmed('KBI-19', SysUtils.Format('signed T%d/S1', [T]));
          exit;
        end;
      end;
      S0 := GetSec(Ht, 0);
      if (S0 <> nil) and (StrBufPos(S0.Data, 'ALAIN LAURENT GENERATION 5 1989') > -1) then
      begin
        Result := ProtConfirmed('CAAV', SysUtils.Format('signed T%d/S0', [T]));
        exit;
      end;
      Result := ProtProbable('KBI-19 or CAAV', SysUtils.Format('unsigned, 19-sector T%d', [T]));
      exit;
    end;

    // 5-sector -> unsigned Speedlock data side
    if Ht.Sectors = 5 then
    begin
      Hs0 := GetSec(Ht, 0);
      if (Hs0 <> nil) and (AdvSize(Hs0) = 1024) then
      begin
        if Cpc then AName := 'Speedlock (CPC)' else AName := 'Speedlock +3 1987/1988';
        Result := ProtProbable(AName, SysUtils.Format('5x1024 at T%d', [T]));
        exit;
      end;
    end;

    // 8-sector -> unsigned Alkatraz +3 data track (+3 only)
    if Ht.Sectors = 8 then
    begin
      Hs0 := GetSec(Ht, 0);
      if (Hs0 <> nil) and (AdvSize(Hs0) = 512) and (not Cpc) then
      begin
        Result := ProtMaybe('Alkatraz +3', SysUtils.Format('unsigned (8x512 data at T%d)', [T]));
        exit;
      end;
    end;

    // Single big sector with CRC -> Speedlock 1989 / Hexagon
    if Ht.Sectors = 1 then
    begin
      Hs0 := GetSec(Ht, 0);
      if (Hs0 <> nil) and (Hs0.FDCSize = 6) and (Hs0.FDCStatus[1] = $20) then
      begin
        if Cpc then
          Result := ProtProbable('Hexagon', SysUtils.Format('big-sector at T%d (CPC)', [T]))
        else
          Result := ProtProbable('Speedlock 1989/1990', SysUtils.Format('big-sector at T%d (+3)', [T]));
        exit;
      end;
    end;
  end;
end;

// --- Stripped-FDC fallbacks (spec 9) ---------------------------------------

function StrippedFdcFallbacks(Side: TDSKSide; T0: TDSKTrack): TProtectionResult;
var
  T1: TDSKTrack;
  T1S0: TDSKSector;
begin
  Result := ProtNone;
  if SideHasFDCErrors(Side) then exit;

  if T0.Sectors >= 8 then
  begin
    T1 := GetTrk(Side, 1);
    if (T1 <> nil) and (T1.Sectors = 5) then
    begin
      T1S0 := GetSec(T1, 0);
      if (T1S0 <> nil) and (AdvSize(T1S0) = 1024) then
      begin
        if IsCpcDisk(T0) then
          Result := ProtProbable('Speedlock (CPC)', 'layout matches, stripped FDC flags')
        else
          Result := ProtProbable('Speedlock +3 1987/1988', 'layout matches, stripped FDC flags');
        exit;
      end;
    end;
  end;

  if (T0.Sectors >= 8) and (Side.Tracks > 40) then
  begin
    T1 := GetTrk(Side, 1);
    if (T1 <> nil) and (T1.Sectors = 1) then
    begin
      T1S0 := GetSec(T1, 0);
      if (T1S0 <> nil) and (T1S0.FDCSize = 6) then
      begin
        if IsCpcDisk(T0) then
          Result := ProtProbable('Hexagon', 'layout matches, stripped FDC flags (CPC)')
        else
          Result := ProtProbable('Speedlock 1989/1990', 'layout matches, stripped FDC flags');
      end;
    end;
  end;
end;

// --- Unknown-protection fallback (non-uniform disk with FDC errors) ---------

// Every known protection has been ruled out by the time this is reached, so
// all that is left to go on is the shape of the disk. Errors on a disk whose
// tracks are all alike are damage, and damage is not worth reporting; it takes
// a disk that is also shaped like nothing a formatter would produce to be
// worth saying anything about.
function UnknownFallback(Side: TDSKSide): TProtectionResult;
begin
  Result := ProtNone;
  if SideIsUniform(Side) then exit;
  if not SideHasFDCErrors(Side) then exit;

  Result := ProtConfirmed('Unknown copy protection', 'non-uniform disk with FDC errors');
end;

// --- Main detection flow (spec 2) ------------------------------------------

function DetectSide(Side: TDSKSide): TProtectionResult;
var
  T0, T1: TDSKTrack;
  T0S0, T1S0, Sector: TDSKSector;
  T0Sc, T0Sz, SIdx: integer;
begin
  Result := ProtNone;
  if Side.Tracks < 2 then exit;

  T0 := GetTrk(Side, 0);
  if (T0 = nil) or (T0.Sectors < 1) then exit;
  T0S0 := GetSec(T0, 0);
  if (T0S0 = nil) or (T0S0.DataSize < 128) then exit;

  // Pre-screen: a uniform disk with no FDC errors is unprotected, except for
  // the two uniform shapes that indicate an unsigned data side.
  if SideIsUniform(Side) and (not SideHasFDCErrors(Side)) then
  begin
    T0Sc := T0.Sectors;
    T0Sz := UniformAdvSize(T0);
    if (T0Sc = 5) and (T0Sz = 1024) then
      // could be unsigned Speedlock data side - continue
    else if (T0Sc = 8) and (T0Sz = 512) then
      // could be unsigned Alkatraz +3 - continue
    else
      exit;
  end;

  // Step 1a: T0 signatures
  Result := ScanT0Signatures(T0);
  if Result.Found then exit;

  // Step 1b: classify T0 geometry -> resolver
  case ClassifyT0(T0) of
    t0SpeedlockPlus3:
      begin Result := ResolveSpeedlockPlus3(Side, T0); if Result.Found then exit; end;
    t0BigSector:
      begin Result := ResolveBigSector(Side, T0); if Result.Found then exit; end;
    t0TenSector:
      begin Result := ResolveHexagon(Side, T0); if Result.Found then exit; end;
    t0TenSectorDDAM:
      begin Result := ResolveSpeedlock1989Cpc(Side, T0); if Result.Found then exit; end;
    t0EighteenSector:
      begin Result := Resolve18Sector(Side, T0); exit; end;
    t0SixteenSector:
      begin Result := Resolve16Sector(Side, T0); if Result.Found then exit; end;
    t0NineteenSector:
      begin Result := Resolve19Sector(T0); exit; end;
    t0EightSector:
      begin Result := Resolve8Sector(Side, T0); if Result.Found then exit; end;
    t0FiveSector:
      begin Result := Resolve5Sector(Side, T0); if Result.Found then exit; end;
    t0Speedlock9x512:
      begin Result := ResolveSpeedlock9x512(Side, T0); if Result.Found then exit; end;
    t0Standard: ;
  end;

  // Step 2: Track 1
  T1 := GetTrk(Side, 1);
  if T1 <> nil then
  begin
    if T1.Sectors = 0 then
    begin
      Result := ResolveEmptyT1Family(Side, T0);
      exit;
    end;

    if T1.Sectors = 5 then
    begin
      T1S0 := GetSec(T1, 0);
      if (T1S0 <> nil) and (AdvSize(T1S0) = 1024) then
      begin
        Result := ResolveSpeedlock5x1024(T0, T1);
        exit;
      end;
    end;

    if T1.Sectors = 1 then
    begin
      T1S0 := GetSec(T1, 0);
      if (T1S0 <> nil) and (T1S0.FDCStatus[1] = $20) then
      begin
        Result := ResolveSpeedlock1989(T0, T1);
        exit;
      end;
    end;

    if T1.Sectors = 16 then
    begin
      if IsDiscSysTrack(T1) then
      begin
        for SIdx := 0 to T0.Sectors - 1 do
        begin
          Sector := GetSec(T0, SIdx);
          if (Sector <> nil) and (StrBufPos(Sector.Data, 'MEAN PROTECTION SYSTEM') > -1) then
          begin
            Result := ProtConfirmed('Mean Protection System',
              SysUtils.Format('signed T0/S%d + DiscSYS T1', [SIdx]));
            exit;
          end;
        end;
        Result := ProtConfirmed('DiscSYS', '16-sector CHRN ramp on T1');
        exit;
      end;
      if IsPlayersTrack(T1) then
      begin
        Result := ProtMaybe('Players', '16-sector id==size pattern on T1');
        exit;
      end;
    end;
  end;

  // Step 3: high-track probes
  Result := ScanHighTracks(Side, T0);
  if Result.Found then exit;

  // Step 4: mid-disk sweep
  Result := SweepMidDisk(Side, T0);
  if Result.Found then exit;

  // Stripped-FDC fallbacks
  Result := StrippedFdcFallbacks(Side, T0);
  if Result.Found then exit;

  // Unknown protection fallback
  Result := UnknownFallback(Side);
end;

function DetectProtection(Side: TDSKSide): string;
begin
  Result := ProtToStr(DetectSide(Side));
end;

function DetectInterleave(Track: TDskTrack): string;
var
  LowIdx, NextLowIdx, LowID, NextLowID, SIdx, ExpectedID: byte;
  Interleave: integer;
begin
  LowIdx := 255;
  NextLowIdx := 255;
  Interleave := 0;

  if (Track.Sectors < 3) then
  begin
    Result := ' Too few sectors';
    Exit;
  end;

  // Scan through the track and figure out the lowest two ID's
  LowID := 255;
  NextLowID := 255;
  for SIdx := 0 to Track.Sectors - 1 do
    if (Track.Sector[SIdx].ID < LowID) then
    begin
      NextLowID := LowID;
      NextLowIDX := LowIdx;
      LowID := Track.Sector[SIdx].ID;
      LowIdx := SIdx;
    end
    else
    if (Track.Sector[SIdx].ID < NextLowID) then
    begin
      NextLowID := Track.Sector[SIdx].ID;
      NextLowIdx := SIdx;
    end;

  // Make sure the ID's are sequential
  if (LowIdx < 255) and (NextLowIdx < 255) and (NextLowID = LowID + 1) then
  begin
    // Positive skew (or negative less than sector-count)
    if (LowIdx < NextLowIdx) then
      Interleave := NextLowIdx - LowIdx;
    // Negative skew (or positive greater than sector-count)
    if (LowIdx > NextLowIdx) then
      Interleave := LowIdx - NextLowIdx;
  end
  else
    Result := 'Non-sequential IDs';

  // Confirm the interleave for every sector
  ExpectedID := Track.Sector[0].ID;
  for SIdx := 0 to Track.Sectors - 1 do
  begin
    if Track.Sector[SIdx].ID <> ExpectedID then
    begin
      Result := Format('Expected %d but sector %d ID was %d not %d', [Interleave, SIdx, Track.Sector[SIdx].ID, ExpectedID]);
      Exit;
    end;
    ExpectedID := ExpectedID + 1;
  end;

  Result := Format('%d', [Interleave]);
end;

end.
