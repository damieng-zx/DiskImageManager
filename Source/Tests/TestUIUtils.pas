unit TestUIUtils;

{$mode objfpc}{$H+}

interface

uses
  fpcunit, testregistry, Graphics, Utils;

type
  TUIUtilsTest = class(TTestCase)
  published
    procedure TestFontFromDescriptionSurvivesRubbish;
  end;

implementation

procedure TUIUtilsTest.TestFontFromDescriptionSurvivesRubbish;
var
  AFont: TFont;
begin
  AFont := FontFromDescription('');
  try
    AssertNotNull('an empty description still gives a font', AFont);
  finally
    AFont.Free;
  end;

  AFont := FontFromDescription('Tahoma,8pt,,');
  try
    AssertEquals('a normal description is read back', 'Tahoma', AFont.Name);
    AssertEquals('with its size', 8, AFont.Size);
  finally
    AFont.Free;
  end;
end;

initialization
  RegisterTest(TUIUtilsTest);
end.
