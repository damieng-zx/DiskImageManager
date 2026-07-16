unit TestFormatAnalysis;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the format and copy-protection analysis.

  Disks are formatted synthetically with a TDSKFormatSpecification, then damaged
  in the specific way each test is about, so the analyser is driven by real
  geometry rather than a hand-built blob.

  Format indices passed to TDSKFormatSpecification.Create (see DskImage.pas):
    0 = Amstrad PCW/Spectrum +3 (40T, SS, 9 x 512)
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, DskImage, FormatAnalysis;

type
  TFormatAnalysisTest = class(TTestCase)
  private
    function MakeFormatted(FormatIndex: integer): TDSKImage;
    function BuildUniform(Sides, Tracks, Sectors, SectorSize, FirstID: integer): TDSKImage;
    procedure BreakSector(Sector: TDSKSector);
  published
    procedure TestCleanUniformDiskIsUnprotected;
    procedure TestUniformDiskWithBadSectorIsUnprotected;
    procedure TestUniformDiskWithUnformattedTailIsUnprotected;
    procedure TestGenuinelyNonUniformDiskWithErrorsIsReported;
    procedure TestEmptyTrack1IsStillProtection;
    procedure TestBadHighTracksAreNotProtection;
    procedure TestSupermat192XCF2StillDetected;
    procedure TestSupermat192TwoEightyTwoVariantDetected;
    procedure TestUnknownXDPBReportsCapacity;
    procedure TestUnknownNonXDPBStaysBlank;
  end;

implementation

function TFormatAnalysisTest.MakeFormatted(FormatIndex: integer): TDSKImage;
var
  Spec: TDSKFormatSpecification;
begin
  Result := TDSKImage.Create;
  Spec := TDSKFormatSpecification.Create(FormatIndex);
  try
    Result.Disk.Format(Spec);
  finally
    Spec.Free;
  end;
end;

// A uniform single/double sided disk built by hand, sector IDs running up from
// FirstID so the logically-first sector is index 0. Lets a test set the boot
// sector's spec bytes without depending on a stored image.
function TFormatAnalysisTest.BuildUniform(Sides, Tracks, Sectors, SectorSize, FirstID: integer): TDSKImage;
var
  SIdx, TIdx, EIdx: integer;
  Trk: TDSKTrack;
  Sec: TDSKSector;
begin
  Result := TDSKImage.Create;
  Result.Disk.Sides := Sides;
  for SIdx := 0 to Sides - 1 do
  begin
    Result.Disk.Side[SIdx].Side := SIdx;
    Result.Disk.Side[SIdx].Tracks := Tracks;
    for TIdx := 0 to Tracks - 1 do
    begin
      Trk := Result.Disk.Side[SIdx].Track[TIdx];
      Trk.Track := TIdx;
      Trk.Side := SIdx;
      Trk.Logical := (SIdx * Tracks) + TIdx;
      Trk.Sectors := Sectors;
      Trk.SectorSize := SectorSize;
      for EIdx := 0 to Sectors - 1 do
      begin
        Sec := Trk.Sector[EIdx];
        Sec.Sector := EIdx;
        Sec.Track := TIdx;
        Sec.Side := SIdx;
        Sec.ID := FirstID + EIdx;
        Sec.FDCSize := GetFDCSectorSize(SectorSize);
        Sec.DataSize := SectorSize;
        Sec.AdvertisedSize := SectorSize;
      end;
    end;
  end;
end;

// A sector the controller could not read: data error in ST1, data error in
// data field in ST2, which is what an imager records for a bad sector.
procedure TFormatAnalysisTest.BreakSector(Sector: TDSKSector);
begin
  Sector.FDCStatus[1] := $20;
  Sector.FDCStatus[2] := $20;
end;

procedure TFormatAnalysisTest.TestCleanUniformDiskIsUnprotected;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    AssertEquals('nothing to report on a clean disk', '',
      DetectProtection(Img.Disk.Side[0]));
  finally
    Img.Free;
  end;
end;

// Bad sectors are damage, not protection: every track still has the shape
// every other track has, so there is nothing to say about the disk.
procedure TFormatAnalysisTest.TestUniformDiskWithBadSectorIsUnprotected;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    BreakSector(Img.Disk.Side[0].Track[10].Sector[3]);
    BreakSector(Img.Disk.Side[0].Track[11].Sector[0]);
    AssertEquals('bad sectors alone are not protection', '',
      DetectProtection(Img.Disk.Side[0]));
  finally
    Img.Free;
  end;
end;

// The tracks a disk never formatted are not part of its shape. A 40 track
// disk imaged as 42 is still uniform, and its bad sectors are still damage.
procedure TFormatAnalysisTest.TestUniformDiskWithUnformattedTailIsUnprotected;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    Img.Disk.Side[0].Tracks := 42; // the two added tracks are unformatted
    BreakSector(Img.Disk.Side[0].Track[10].Sector[3]);
    AssertEquals('an unformatted tail does not make a disk non-uniform', '',
      DetectProtection(Img.Disk.Side[0]));
  finally
    Img.Free;
  end;
end;

// A formatted track that really is a different shape is another matter, and
// with errors alongside it there is still something worth saying.
procedure TFormatAnalysisTest.TestGenuinelyNonUniformDiskWithErrorsIsReported;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    Img.Disk.Side[0].Track[20].Sectors := 4; // a real change of shape
    BreakSector(Img.Disk.Side[0].Track[10].Sector[3]);
    AssertTrue('a disk that is really not uniform still reports',
      DetectProtection(Img.Disk.Side[0]) <> '');
  finally
    Img.Free;
  end;
end;

// An unformatted track with formatted tracks still after it is a hole, not a
// tail, and an empty track 1 is how the P.M.S. and Paul Owens loaders show up.
// Ignoring the tail must not go so far as to ignore those.
procedure TFormatAnalysisTest.TestEmptyTrack1IsStillProtection;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    Img.Disk.Side[0].Track[1].Sectors := 0;
    AssertTrue('an empty track 1 is not just a gap',
      DetectProtection(Img.Disk.Side[0]) <> '');
  finally
    Img.Free;
  end;
end;

// The worn-out end of a disk: the last tracks damaged, and read badly enough
// that sectors were lost off them as well. The shape still says nothing a
// formatter would not produce, so there is nothing to report.
procedure TFormatAnalysisTest.TestBadHighTracksAreNotProtection;
var
  Img: TDSKImage;
begin
  Img := MakeFormatted(0);
  try
    BreakSector(Img.Disk.Side[0].Track[38].Sector[0]);
    BreakSector(Img.Disk.Side[0].Track[39].Sector[0]);
    AssertEquals('damaged high tracks are not protection', '',
      DetectProtection(Img.Disk.Side[0]));
  finally
    Img.Free;
  end;
end;

// The original XCF2 variant: three directory blocks, format gap 23.
procedure TFormatAnalysisTest.TestSupermat192XCF2StillDetected;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := BuildUniform(1, 40, 10, 512, 1);
  try
    Sec := Img.Disk.Side[0].Track[0].GetFirstLogicalSector;
    Sec.Data[2] := 40;
    Sec.Data[7] := 3;
    Sec.Data[9] := 23;
    AssertEquals('Supermat 192/XCF2', 'Supermat 192/XCF2', Img.Disk.DetectFormat);
  finally
    Img.Free;
  end;
end;

// The other variant Ian Cull's 192K Format program writes: two directory
// blocks and the standard +3 format gap. Same program, same boot banner, but
// the XDPB differs, so it was falling through to nothing.
procedure TFormatAnalysisTest.TestSupermat192TwoEightyTwoVariantDetected;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := BuildUniform(1, 40, 10, 512, 1);
  try
    Sec := Img.Disk.Side[0].Track[0].GetFirstLogicalSector;
    Sec.Data[2] := 40;
    Sec.Data[7] := 2;
    Sec.Data[9] := 82;
    AssertEquals('Supermat 192 2/82', 'Supermat 192 2/82', Img.Disk.DetectFormat);
  finally
    Img.Free;
  end;
end;

// An unrecognised disk whose boot sector is nonetheless a valid disk
// specification is described by its usable capacity rather than left blank.
// (40 - 1 reserved) x 9 x 256 = 89856 bytes = 87KB, and 9 x 256 names nothing.
procedure TFormatAnalysisTest.TestUnknownXDPBReportsCapacity;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := BuildUniform(1, 40, 9, 256, 1);
  try
    Sec := Img.Disk.Side[0].Track[0].GetFirstLogicalSector;
    Sec.Data[0] := 0;   // PCW single-sided spec id
    Sec.Data[2] := 40;  // tracks per side
    Sec.Data[3] := 9;   // sectors per track
    Sec.Data[4] := 1;   // sector size code: 128 shl 1 = 256
    Sec.Data[5] := 1;   // reserved tracks
    AssertEquals('usable capacity named from the spec block', 'Unknown 87KB XDPB format',
      Img.Disk.DetectFormat);
  finally
    Img.Free;
  end;
end;

// The capacity fallback speaks only for a real spec block. A disk whose boot
// sector is not one is still reported as nothing rather than guessed at.
procedure TFormatAnalysisTest.TestUnknownNonXDPBStaysBlank;
var
  Img: TDSKImage;
  Sec: TDSKSector;
begin
  Img := BuildUniform(1, 40, 9, 256, 1);
  try
    Sec := Img.Disk.Side[0].Track[0].GetFirstLogicalSector;
    Sec.Data[0] := 200;  // not a spec id, so not an XDPB
    AssertEquals('no spec block, no guess', '', Img.Disk.DetectFormat);
  finally
    Img.Free;
  end;
end;

initialization
  RegisterTest(TFormatAnalysisTest);
end.
