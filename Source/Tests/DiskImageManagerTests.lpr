program DiskImageManagerTests;

{$mode objfpc}{$H+}

{
  Disk Image Manager - console test runner.

  This is a console-subsystem program that links the LCL widgetset (via the
  Interfaces unit). The LCL-dependent logic units (Utils, Comparers, DskImage,
  ...) need a real widgetset to link, but the runner never creates a window, so
  the suite still runs headless. (The "nogui" widgetset can't be used because
  these units drag in ComCtrls/StdCtrls, whose widgetset classes nogui omits.)

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
  TestFormatAnalysis;

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
