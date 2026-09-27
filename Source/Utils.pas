unit Utils;

{$MODE Delphi}

{
  Disk Image Manager - UI utility functions

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Classes, Graphics, SysUtils, ComCtrls;

const
  BytesPerKB: integer = 1024;
  Power2: array[1..17] of integer =
    (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536);
  LVSCW_AUTOSIZE_BESTFIT = -3;

type
  TSpinBorderStyle = (bsRaised, bsLowered, bsNone);

function FontToDescription(ThisFont: TFont): string;
function FontFromDescription(Description: string): TFont;
function FontHumanReadable(ThisFont: TFont): string;
function FontCopy(ThisFont: TFont): TFont;

procedure DrawBorder(Canvas: TCanvas; var Rect: TRect; BorderStyle: TSpinBorderStyle);
procedure AutoResizeListView(const ListView: TListView;
  const Mode: integer = LVSCW_AUTOSIZE_BESTFIT);

// Save Bitmap to FileName as PNG or BMP, chosen by the file extension. TBitmap
// is natively a Windows bitmap and writes one whatever the name says, so a .png
// has to go through TPortableNetworkGraphic to actually be a PNG. Returns False
// when there is nothing to save.
function SaveBitmapAs(Bitmap: TBitmap; const FileName: string): boolean;

// Prompt for a filename and save Bitmap as PNG or BMP (chosen by the file
// extension, defaulting to PNG). SuggestedName seeds the dialog's filename.
procedure SaveBitmapWithDialog(AOwner: TComponent; Bitmap: TBitmap;
  const SuggestedName: string);

implementation

uses
  DIMUtils, LCLIntf, CommCtrl, Dialogs;

procedure DrawBorder(Canvas: TCanvas; var Rect: TRect; BorderStyle: TSpinBorderStyle);
var
  OTL, ITL, OBR, IBR: TColor;
begin
  case BorderStyle of
    bsLowered:
    begin
      OTL := clBtnShadow;
      ITL := cl3DDkShadow;
      IBR := cl3DLight;
      OBR := clBtnHighlight;
    end;
    bsRaised:
    begin
      OBR := clBtnShadow;
      IBR := cl3DDkShadow;
      OTL := clBtnHighlight;
      ITL := cl3DLight;
    end;
    else
      exit;
  end;

  with Canvas do
  begin
    Dec(Rect.Bottom);
    Dec(Rect.Right);
    Pen.Color := OTL;
    MoveTo(Rect.Left, Rect.Bottom);
    LineTo(Rect.Left, Rect.Top);
    LineTo(Rect.Right, Rect.Top);
    Pen.Color := OBR;
    LineTo(Rect.Right, Rect.Bottom);
    LineTo(Rect.Left, Rect.Bottom);
    InflateRect(Rect, -1, -1);
    Pen.Color := ITL;
    MoveTo(Rect.Left, Rect.Bottom);
    LineTo(Rect.Left, Rect.Top);
    LineTo(Rect.Right, Rect.Top);
    Pen.Color := IBR;
    LineTo(Rect.Right, Rect.Bottom);
    LineTo(Rect.Left, Rect.Bottom);
    Inc(Rect.Top);
    Inc(Rect.Left);
  end;
end;

function FontToDescription(ThisFont: TFont): string;
begin
  Result := ThisFont.Name + ',' + StrInt(ThisFont.Size) + 'pt,';
  if fsBold in ThisFont.Style then Result := Result + 'Bold';
  Result := Result + ',';
  if fsItalic in ThisFont.Style then Result := Result + 'Italic';
end;

function FontFromDescription(Description: string): TFont;
var
  Parts: TStringList;
begin
  Result := TFont.Create;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.DelimitedText := StringReplace(Description, ' ', '_', [rfReplaceAll]);
    if Parts.Count > 0 then
      Result.Name := StringReplace(Parts[0], '_', ' ', [rfReplaceAll]);
    if Parts.Count > 1 then
      Result.Size := IntStr(StringReplace(Parts[1], 'pt', '', [rfReplaceAll]));
    if (Parts.Count > 2) and (Parts[2] = 'Bold') then
      Result.Style := Result.Style + [fsBold];
    if (Parts.Count > 3) and (Parts[3] = 'Italic') then
      Result.Style := Result.Style + [fsItalic];
  finally
    Parts.Free;
  end;
end;

function FontCopy(ThisFont: TFont): TFont;
begin
  Result := TFont.Create;
  Result.Name := ThisFont.Name;
  Result.Style := ThisFont.Style;
  Result.Size := ThisFont.Size;
  Result.Color := ThisFont.Color;
end;

function FontHumanReadable(ThisFont: TFont): string;
begin
  Result := Trim(StringReplace(FontToDescription(ThisFont), ',', ' ', [rfReplaceAll]));
end;

procedure AutoResizeColumn(const Column: TListColumn; Mode: integer);
var
  Width: integer;
begin
  case Mode of
    LVSCW_AUTOSIZE_BESTFIT:
    begin
      Column.Width := LVSCW_AUTOSIZE;
      Width := Column.Width;
      Column.Width := LVSCW_AUTOSIZE_USEHEADER;
      if Width > Column.Width then Column.Width := LVSCW_AUTOSIZE;
    end;
    LVSCW_AUTOSIZE: Column.Width := LVSCW_AUTOSIZE;
    LVSCW_AUTOSIZE_USEHEADER: Column.Width := LVSCW_AUTOSIZE_USEHEADER;
  end;
end;

procedure AutoResizeListView(const ListView: TListView; const Mode: integer);
var
  I: integer;
begin
  for I := 0 to ListView.Columns.Count - 1 do
    AutoResizeColumn(ListView.Columns[I], Mode);
end;

function SaveBitmapAs(Bitmap: TBitmap; const FileName: string): boolean;
var
  Png: TPortableNetworkGraphic;
begin
  Result := False;
  if (Bitmap = nil) or (FileName = '') then Exit;
  if LowerCase(ExtractFileExt(FileName)) = '.bmp' then
    Bitmap.SaveToFile(FileName)
  else
  begin
    Png := TPortableNetworkGraphic.Create;
    try
      Png.Assign(Bitmap);
      Png.SaveToFile(FileName);
    finally
      Png.Free;
    end;
  end;
  Result := True;
end;

procedure SaveBitmapWithDialog(AOwner: TComponent; Bitmap: TBitmap;
  const SuggestedName: string);
var
  Dialog: TSaveDialog;
  FileName, Ext: string;
begin
  if Bitmap = nil then Exit;
  Dialog := TSaveDialog.Create(AOwner);
  try
    Dialog.Title := 'Save image';
    Dialog.Filter := 'PNG image|*.png|Windows bitmap|*.bmp';
    Dialog.FilterIndex := 1;
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    Dialog.FileName := SuggestedName;
    if not Dialog.Execute then Exit;

    FileName := Dialog.FileName;
    Ext := LowerCase(ExtractFileExt(FileName));
    if (Ext <> '.png') and (Ext <> '.bmp') then
    begin
      if Dialog.FilterIndex = 2 then Ext := '.bmp' else Ext := '.png';
      FileName := FileName + Ext;
    end;
    SaveBitmapAs(Bitmap, FileName);
  finally
    Dialog.Free;
  end;
end;

end.
