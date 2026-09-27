program DiskImageManagerTests;

{$mode objfpc}{$H+}

{
  Disk Image Manager - console test runner.

  This is a console-subsystem program that links the LCL widgetset (via the
  Interfaces unit). Comparers, Utils, and DskImage still depend on LCL classes,
  so a real widgetset is needed to link; the runner never creates a window. (The
  "nogui" widgetset omits classes these units use.)

  Run with no arguments to execute every registered test in plain-text form.
  Pass --format=xml for a JUnit-style report, or --help for all options.
}

uses
  Interfaces,  // links the LCL widgetset so the LCL-dependent units resolve
  Classes, consoletestrunner,
  TestDIMUtils,
  TestComparers,
  TestSinclairBasic,
  TestAmstradBasic,
  TestDskImage,
  TestCPMFileSystem,
  TestFormatAnalysis,
  TestLZHuf,
  TestTeleDisk,
  TestUIUtils,
  TestNavigationHistory;

type
  TDIMTestRunner = class(TTestRunner)
  end;

var
  App: TDIMTestRunner;
begin
  DefaultRunAllTests := True;  // run everything when invoked with no args
  App := TDIMTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'Disk Image Manager Tests';
    App.Run;
  finally
    App.Free;
  end;
end.
