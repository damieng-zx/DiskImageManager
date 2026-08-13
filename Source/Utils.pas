unit Utils;

{$MODE Delphi}

{
  Disk Image Manager -  Utility functions

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Classes, Graphics, LCLIntf, SysUtils, ComCtrls, CommCtrl, Dialogs;

const
  BytesPerKB: integer = 1024;
  Power2: array[1..17] of integer =
    (1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536);
  LVSCW_AUTOSIZE_BESTFIT = -3;
  // Largest XDPB block shift that describes a real disk (2 << (8 + 6) = 128KB)
  MaxBlockShift = 8;

type
  TSpinBorderStyle = (bsRaised, bsLowered, bsNone);
  TDiskByteArray = array of byte;
  // An 8-bit-per-channel colour, shared by the screen decoders' palettes
  TRGB = record
    R, G, B: byte;
  end;

function StrInt(I: integer): string;
function StrHex(I: integer): string;
function IntStr(S: string): integer;
function StrBlockClean(S: array of byte; Start, Len: integer): string;
function StrYesNo(IsEmpty: boolean): string;
function StrInByteArray(ByteArray: array of byte; SubString: string;
  Start: integer): boolean;
function StrBufPos(ByteArray: array of byte; SubString: string): integer;

function ReadWordLE(const Data: array of byte; Offset: integer): word;
function ReadWordBE(const Data: array of byte; Offset: integer): word;
function Read24LE(const Data: array of byte; Offset: integer): longword;
function Read32LE(const Data: array of byte; Offset: integer): longword;

function CompareBlock(A: array of char; B: string): boolean;
function CompareBlockStart(A: array of char; B: string; Start: integer): boolean;
function CompareBlockInsensitive(A: array of char; B: string): boolean;

function FontToDescription(ThisFont: TFont): string;
function FontFromDescription(Description: string): TFont;
function FontHumanReadable(ThisFont: TFont): string;
function FontCopy(ThisFont: TFont): TFont;

function BlockShiftToBlockSize(BlockShift: byte): integer;
function StrFileSize(Size: integer): string;

// A file name from inside a disk image, made safe to join onto a folder path.
// Names on a CP/M or MGT disk are eleven bytes of anything printable, which
// includes the path separators and the characters Windows will not take, so one
// can name a place outside the folder the user chose or a device rather than a
// file. Everything troublesome becomes an underscore; a name left with nothing
// in it comes back as Fallback.
function SafeFileName(const Name: string; const Fallback: string = 'unnamed'): string;
function CompareByLength(List: TStringList; Index1, Index2: integer): integer;

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

// Get integer as a decimal string
function StrInt(I: integer): string;
begin
  Str(I, Result);
end;

// Get integer as a hex string
function StrHex(I: integer): string;
begin
  Result := Format('%.2x', [I]);
end;

// Get string as an integer
function IntStr(S: string): integer;
var
  Code: integer;
begin
  Val(S, Result, Code);
  if Code <> 0 then Result := 0;
end;

// Extract ASCII string from a char array
function StrBlockClean(S: array of byte; Start, Len: integer): string;
var
  Idx: integer;
begin
  Result := '';
  for Idx := Start to Start + Len - 1 do
    if S[Idx] > 31 then
      if S[Idx] < 128 then
        Result := Result + Chr(S[Idx])
      else
        Result := Result + Chr(S[Idx] - 128);
end;

// Does A start with the whole of B? B is 1-based and A is 0-based, so the last
// character of B sits at Idx = Length(B) - 1: stopping short of it, as these
// used to, matched 'MV - CP' against 'MV - CPC'. B has to fit in A to match at
// all, which also keeps the comparison inside A.
function CompareBlock(A: array of char; B: string): boolean;
var
  Idx: integer;
begin
  Result := Length(B) <= Length(A);
  Idx := 0;
  while Result and (Idx < Length(B)) do
  begin
    if A[Idx] <> B[Idx + 1] then
      Result := False;
    Inc(Idx);
  end;
end;

// Does A contain the whole of B at Start?
function CompareBlockStart(A: array of char; B: string; Start: integer): boolean;
var
  Idx: integer;
begin
  Result := (Start >= 0) and (Start + Length(B) <= Length(A));
  Idx := 0;
  while Result and (Idx < Length(B)) do
  begin
    if A[Idx + Start] <> B[Idx + 1] then
      Result := False;
    Inc(Idx);
  end;
end;

// Does A start with the whole of B, ignoring case?
function CompareBlockInsensitive(A: array of char; B: string): boolean;
var
  Idx: integer;
  AChar, BChar: char;
begin
  Result := Length(B) <= Length(A);
  Idx := 0;
  while Result and (Idx < Length(B)) do
  begin
    AChar := UpCase(A[Idx]);
    BChar := UpCase(B[Idx + 1]);
    if AChar <> BChar then
      Result := False;
    Inc(Idx);
  end;
end;

// Read a little-endian 16-bit word from two consecutive bytes (low byte first)
function ReadWordLE(const Data: array of byte; Offset: integer): word;
begin
  Result := Data[Offset] or (Data[Offset + 1] shl 8);
end;

// Read a big-endian 16-bit word from two consecutive bytes (high byte first)
function ReadWordBE(const Data: array of byte; Offset: integer): word;
begin
  Result := (Data[Offset] shl 8) or Data[Offset + 1];
end;

// Read a little-endian 24-bit value from three consecutive bytes (low byte first)
function Read24LE(const Data: array of byte; Offset: integer): longword;
begin
  Result := longword(Data[Offset]) or (longword(Data[Offset + 1]) shl 8) or
    (longword(Data[Offset + 2]) shl 16);
end;

// Read a little-endian 32-bit value from four consecutive bytes (low byte first)
function Read32LE(const Data: array of byte; Offset: integer): longword;
begin
  Result := longword(Data[Offset]) or (longword(Data[Offset + 1]) shl 8) or
    (longword(Data[Offset + 2]) shl 16) or (longword(Data[Offset + 3]) shl 24);
end;

// Draw a windows style 3D border
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

// Convert a font into a textual description
function FontToDescription(ThisFont: TFont): string;
begin
  Result := ThisFont.Name + ',' + StrInt(ThisFont.Size) + 'pt,';
  if (fsBold in ThisFont.Style) then
    Result := Result + 'Bold';
  Result := Result + ',';
  if (fsItalic in ThisFont.Style) then
    Result := Result + 'Italic';
end;

// Create a font from a textual description
function FontFromDescription(Description: string): TFont;
var
  Break: TStringList;
begin
  Break := TStringList.Create;
  Break.Delimiter := ',';
  Break.DelimitedText := StringReplace(Description, ' ', '_', [rfReplaceAll]);
  Result := TFont.Create;
  Result.Name := StringReplace(Break[0], '_', ' ', [rfReplaceAll]);
  if Break.Count > 1 then
    Result.Size := IntStr(StringReplace(Break[1], 'pt', '', [rfReplaceAll]));
  if (Break.Count > 2) and (Break[2] = 'Bold') then
    Result.Style := Result.Style + [fsBold];
  if (Break.Count > 3) and (Break[3] = 'Italic') then
    Result.Style := Result.Style + [fsItalic];
  Break.Free;
end;

// Copy a font
function FontCopy(ThisFont: TFont): TFont;
begin
  Result := TFont.Create;
  with Result do
  begin
    Name := ThisFont.Name;
    Style := ThisFont.Style;
    Size := ThisFont.Size;
    Color := ThisFont.Color;
  end;
end;

// Font as human readable description
function FontHumanReadable(ThisFont: TFont): string;
begin
  Result := Trim(StringReplace(FontToDescription(ThisFont), ',', ' ', [rfReplaceAll]));
end;

function StrYesNo(IsEmpty: boolean): string;
begin
  if IsEmpty then
    Result := 'Yes'
  else
    Result := 'No';
end;

function StrBufPos(ByteArray: array of byte; SubString: string): integer;
var
  BIdx, SIdx, Last: integer;
begin
  Last := Length(ByteArray) - Length(SubString);
  Result := -1;

  for BIdx := 0 to Last do
  begin
    Result := BIdx;
    for SIdx := 1 to Length(SubString) do
    begin
      if ByteArray[BIdx + SIdx - 1] <> byte(SubString[SIdx]) then
      begin
        Result := -1;
        break;
      end;
    end;
    if Result <> -1 then break;
  end;
end;

function StrInByteArray(ByteArray: array of byte; SubString: string;
  Start: integer): boolean;
var
  Idx: integer;
begin
  // Does SubString occur in ByteArray beginning at offset Start?
  if Length(SubString) = 0 then
    Exit(True);
  if (Start < 0) or (Start + Length(SubString) > Length(ByteArray)) then
    Exit(False);

  Result := True;
  for Idx := 0 to Length(SubString) - 1 do
    if ByteArray[Start + Idx] <> byte(SubString[Idx + 1]) then
      Exit(False);
end;

// CP/M block size from the XDPB block shift. The shift is a raw byte off the
// boot sector, and shifting a 32-bit value by more than 31 is not defined: at a
// shift of 25 the 2 fell off the top and the answer was 0, which every caller
// then divided by. Nothing beyond MaxBlockShift (128KB) describes a real disk,
// so anything larger is reported as the largest that does.
function BlockShiftToBlockSize(BlockShift: byte): integer;
begin
  if BlockShift > MaxBlockShift then
    BlockShift := MaxBlockShift;
  Result := 2 << (BlockShift + 6);
end;

function SafeFileName(const Name: string; const Fallback: string): string;
const
  // Everything Windows refuses in a file name, plus both path separators so a
  // name cannot climb out of the folder it is being written into
  Illegal = '\/:*?"<>|';
  // Names that are devices however they are spelled, and whatever follows a dot
  Devices: array[0..21] of string = (
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9');
var
  Idx: integer;
  Ch: char;
  Stem: string;
begin
  Result := '';
  for Idx := 1 to Length(Name) do
  begin
    Ch := Name[Idx];
    if (Ch < ' ') or (Pos(Ch, Illegal) > 0) then
      Ch := '_';
    Result := Result + Ch;
  end;

  // Windows drops trailing dots and spaces, which would turn 'a. ' into 'a' and
  // '..' into nothing at all, and a leading dot hides the file on other systems
  while (Result <> '') and ((Result[Length(Result)] = '.') or (Result[Length(Result)] = ' ')) do
    SetLength(Result, Length(Result) - 1);
  while (Result <> '') and ((Result[1] = '.') or (Result[1] = ' ')) do
    Result := Copy(Result, 2, Length(Result) - 1);

  if Result = '' then
  begin
    Result := Fallback;
    exit;
  end;

  // A device name is a device whatever extension it is given, so push it out of
  // the way rather than opening the console in place of a file
  Stem := UpperCase(Result);
  Idx := Pos('.', Stem);
  if Idx > 0 then
    Stem := Copy(Stem, 1, Idx - 1);
  for Idx := Low(Devices) to High(Devices) do
    if Stem = Devices[Idx] then
    begin
      Result := '_' + Result;
      exit;
    end;
end;

function StrFileSize(Size: integer): string;
const
  Megabyte: integer = 1024 * 1024;
begin
  if Size < 1024 then
    Result := Format('%d bytes', [Size])
  else
  if Size < Megabyte then
    Result := Format('%d KB', [Size div 1024])
  else
    Result := Format('%d MB', [Size div Megabyte]);
end;

function CompareByLength(List: TStringList; Index1, Index2: integer): integer;
begin
  Result := Length(List[Index2]) - Length(List[Index1]);  // Longest first
  if Result = 0 then
    Result := CompareText(List[Index1], List[Index2]);  // Alphabetical if same length
end;

procedure AutoResizeColumn(const Column: TListColumn;
  const Mode: integer = LVSCW_AUTOSIZE_BESTFIT);
var
  Width: integer;
begin
  case Mode of
    LVSCW_AUTOSIZE_BESTFIT:
    begin // Calculate thw widest of data or header and use that
      Column.Width := LVSCW_AUTOSIZE;
      Width := Column.Width;
      Column.Width := LVSCW_AUTOSIZE_USEHEADER;
      if Width > Column.Width then
        Column.Width := LVSCW_AUTOSIZE;
    end;

    LVSCW_AUTOSIZE: Column.Width := LVSCW_AUTOSIZE;
    LVSCW_AUTOSIZE_USEHEADER: Column.Width := LVSCW_AUTOSIZE_USEHEADER;
  end;
end;

procedure AutoResizeListView(const ListView: TListView;
  const Mode: integer = LVSCW_AUTOSIZE_BESTFIT);
var
  i: integer;
begin
  for i := 0 to ListView.Columns.Count - 1 do
    AutoResizeColumn(ListView.Columns[i], Mode);
end;

function SaveBitmapAs(Bitmap: TBitmap; const FileName: string): boolean;
var
  Png: TPortableNetworkGraphic;
begin
  Result := False;
  if (Bitmap = nil) or (FileName = '') then
    Exit;

  if LowerCase(ExtractFileExt(FileName)) = '.bmp' then
    Bitmap.SaveToFile(FileName)  // TBitmap is natively a Windows bitmap
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
  if Bitmap = nil then
    Exit;

  Dialog := TSaveDialog.Create(AOwner);
  try
    Dialog.Title := 'Save image';
    Dialog.Filter := 'PNG image|*.png|Windows bitmap|*.bmp';
    Dialog.FilterIndex := 1;
    Dialog.Options := Dialog.Options + [ofOverwritePrompt];
    Dialog.FileName := SuggestedName;
    if not Dialog.Execute then
      Exit;

    // Pick the format from the typed extension, falling back to the selected
    // filter (PNG by default) when none was given.
    FileName := Dialog.FileName;
    Ext := LowerCase(ExtractFileExt(FileName));
    if (Ext <> '.png') and (Ext <> '.bmp') then
    begin
      if Dialog.FilterIndex = 2 then
        Ext := '.bmp'
      else
        Ext := '.png';
      FileName := FileName + Ext;
    end;

    SaveBitmapAs(Bitmap, FileName);
  finally
    Dialog.Free;
  end;
end;

end.
