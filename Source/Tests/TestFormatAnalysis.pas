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
    procedure BreakSector(Sector: TDSKSector);
  published
    procedure TestCleanUniformDiskIsUnprotected;
    procedure TestUniformDiskWithBadSectorIsUnprotected;
    procedure TestUniformDiskWithUnformattedTailIsUnprotected;
    procedure TestGenuinelyNonUniformDiskWithErrorsIsReported;
    procedure TestEmptyTrack1IsStillProtection;
    procedure TestBadHighTracksAreNotProtection;
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

initialization
  RegisterTest(TFormatAnalysisTest);
end.
