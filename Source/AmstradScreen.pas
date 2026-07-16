unit AmstradScreen;

{$MODE Delphi}

{
  Disk Image Manager - Amstrad CPC screen (raw SCREEN RAM) decoder

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Graphics, Classes, SysUtils, Utils;

const
  CPCScreenSize = 16384;       // Standard CPC screen RAM dump
  CPCLines = 200;              // Visible scanlines
  CPCBytesPerLine = 80;        // Bytes per scanline for a standard screen
  CPCVisibleBytes = 16000;     // Bytes actually displayed (200 * 80)
  CPCScreenMaxBytes = 17408;   // Allow a header/trailer (up to 17 x 1K blocks)
  CPCDisplayWidth = 640;       // Normalised display width (all modes)
  CPCDisplayHeight = 400;      // Normalised display height (200 lines doubled)

type
  TAmstradMode = (amMode0, amMode1, amMode2);

  // A decoded Amstrad picture: a full (interleaved) screen, or a linear
  // Advanced OCP Art Studio window clip.
  TAmstradImage = record
    Data: TDiskByteArray;   // raw pixel bytes (MJH already expanded)
    Mode: TAmstradMode;     // guessed display mode (the user can override it)
    BytesPerRow: integer;   // bytes of pixel data per row
    Rows: integer;          // number of pixel rows
    Interleaved: boolean;   // True for full screens (CPC scanline interleave)
    IsWindow: boolean;      // True for .WIN window clips
  end;

  TAmstradScreen = class
  public
    class function IsValidScreenSize(Size: integer): boolean;
    // True if Data begins with an "MJH" Advanced OCP Art Studio compressed block.
    class function IsMJHCompressed(const Data: array of byte): boolean;
    // Decompress concatenated "MJH" RLE blocks into raw bytes. Returns an empty
    // array if Data is not a valid MJH stream.
    class function DecompressMJH(const Data: array of byte): TDiskByteArray;
    // Decode a file's raw data (expanding MJH compression) into a full screen or
    // a window image, guessing the display mode. Returns False if it is neither.
    class function LoadImage(const Raw: array of byte; out Image: TAmstradImage): boolean;
    // Cheap routing check: True if Raw is a CPC screen or an OCP window.
    class function CanDisplay(const Raw: array of byte): boolean;
    // Render a decoded image to Bitmap at the given zoom.
    class procedure RenderImage(const Image: TAmstradImage; Bitmap: TBitmap; Zoom: integer);
  end;

implementation

type
  TCPCColor = TRGB;

const
  // The 27 CPC hardware colours indexed by firmware colour number.
  // Each RGB gun has three levels: $00 (off), $80 (half), $FF (full).
  HardwarePalette: array[0..26] of TCPCColor = (
    (R: $00; G: $00; B: $00),  //  0 Black
    (R: $00; G: $00; B: $80),  //  1 Blue
    (R: $00; G: $00; B: $FF),  //  2 Bright Blue
    (R: $80; G: $00; B: $00),  //  3 Red
    (R: $80; G: $00; B: $80),  //  4 Magenta
    (R: $80; G: $00; B: $FF),  //  5 Mauve
    (R: $FF; G: $00; B: $00),  //  6 Bright Red
    (R: $FF; G: $00; B: $80),  //  7 Purple
    (R: $FF; G: $00; B: $FF),  //  8 Bright Magenta
    (R: $00; G: $80; B: $00),  //  9 Green
    (R: $00; G: $80; B: $80),  // 10 Cyan
    (R: $00; G: $80; B: $FF),  // 11 Sky Blue
    (R: $80; G: $80; B: $00),  // 12 Yellow
    (R: $80; G: $80; B: $80),  // 13 White
    (R: $80; G: $80; B: $FF),  // 14 Pastel Blue
    (R: $FF; G: $80; B: $00),  // 15 Orange
    (R: $FF; G: $80; B: $80),  // 16 Pink
    (R: $FF; G: $80; B: $FF),  // 17 Pastel Magenta
    (R: $00; G: $FF; B: $00),  // 18 Bright Green
    (R: $00; G: $FF; B: $80),  // 19 Sea Green
    (R: $00; G: $FF; B: $FF),  // 20 Bright Cyan
    (R: $80; G: $FF; B: $00),  // 21 Lime
    (R: $80; G: $FF; B: $80),  // 22 Pastel Green
    (R: $80; G: $FF; B: $FF),  // 23 Pastel Cyan
    (R: $FF; G: $FF; B: $00),  // 24 Bright Yellow
    (R: $FF; G: $FF; B: $80),  // 25 Pastel Yellow
    (R: $FF; G: $FF; B: $FF)   // 26 Bright White
  );

  // Firmware default ink table: pen 0-15 -> hardware colour number.
  // (Pens 14/15 flash on real hardware; the first colour is shown here.)
  DefaultInk: array[0..15] of byte = (
    1, 24, 20, 6, 26, 0, 2, 8, 10, 12, 14, 16, 18, 22, 1, 11
  );

// Pixels across a line and pixels packed per byte for each mode.
procedure ModeMetrics(Mode: TAmstradMode; out PixelsPerLine, PixelsPerByte: integer);
begin
  case Mode of
    amMode0: begin PixelsPerLine := 160; PixelsPerByte := 2; end;
    amMode1: begin PixelsPerLine := 320; PixelsPerByte := 4; end;
  else
    begin PixelsPerLine := 640; PixelsPerByte := 8; end;
  end;
end;

// Byte offset of the first byte of scanline Y, accounting for the CPC screen
// interleave: 8 scanlines per character row, the rows 2048 bytes apart.
function ScreenLineBase(Y: integer): integer;
begin
  Result := (Y mod 8) * 2048 + (Y div 8) * CPCBytesPerLine;
end;

// Decode the logical pen (0..15) of pixel Pixel within byte AByte for the mode.
function DecodePen(AByte: byte; Pixel: integer; Mode: TAmstradMode): integer;
begin
  case Mode of
    amMode0:
      if Pixel = 0 then
        Result := ((AByte shr 7) and 1) or (((AByte shr 3) and 1) shl 1) or
                  (((AByte shr 5) and 1) shl 2) or (((AByte shr 1) and 1) shl 3)
      else
        Result := ((AByte shr 6) and 1) or (((AByte shr 2) and 1) shl 1) or
                  (((AByte shr 4) and 1) shl 2) or ((AByte and 1) shl 3);
    amMode1:
      Result := ((AByte shr (7 - Pixel)) and 1) or
                (((AByte shr (3 - Pixel)) and 1) shl 1);
  else // amMode2
    Result := (AByte shr (7 - Pixel)) and 1;
  end;
end;

// Decode one row into Row for the given mode. Interleaved uses the CPC screen
// scanline layout; otherwise rows are linear, BytesPerRow apart.
procedure DecodeRow(const Data: array of byte; Mode: TAmstradMode;
  Offset, Y, PixelsPerByte, BytesPerRow: integer; Interleaved: boolean;
  var Row: array of integer);
var
  Col, P, Idx, DataLen, LineBase: integer;
  B: byte;
begin
  DataLen := Length(Data);
  if Interleaved then
    LineBase := ScreenLineBase(Y)
  else
    LineBase := Y * BytesPerRow;
  for Col := 0 to BytesPerRow - 1 do
  begin
    Idx := Offset + LineBase + Col;
    if (Idx >= 0) and (Idx < DataLen) then
      B := Data[Idx]
    else
      B := 0;
    for P := 0 to PixelsPerByte - 1 do
      Row[Col * PixelsPerByte + P] := DecodePen(B, P, Mode);
  end;
end;

class function TAmstradScreen.IsValidScreenSize(Size: integer): boolean;
begin
  // Accept anything from a bare visible image up to a screen with a small
  // header/trailer (some .SCR files carry a few extra bytes and span 17 blocks)
  Result := (Size >= CPCVisibleBytes) and (Size <= CPCScreenMaxBytes);
end;

class function TAmstradScreen.IsMJHCompressed(const Data: array of byte): boolean;
begin
  Result := (Length(Data) >= 5) and (Data[0] = Ord('M')) and
            (Data[1] = Ord('J')) and (Data[2] = Ord('H'));
end;

class function TAmstradScreen.DecompressMJH(const Data: array of byte): TDiskByteArray;
const
  MJHMarker = $01;
var
  Pos, Len, OutLen, Produced, Count, BlockLen, I: integer;
  Value: byte;
begin
  Result := nil;
  Len := Length(Data);
  Pos := 0;
  OutLen := 0;

  // The file is one or more concatenated "MJH" blocks (each a quarter screen).
  while (Pos + 5 <= Len) and (Data[Pos] = Ord('M')) and
        (Data[Pos + 1] = Ord('J')) and (Data[Pos + 2] = Ord('H')) do
  begin
    BlockLen := ReadWordLE(Data, Pos + 3);  // uncompressed length
    Pos := Pos + 5;
    SetLength(Result, OutLen + BlockLen);

    Produced := 0;
    while (Produced < BlockLen) and (Pos < Len) do
    begin
      if Data[Pos] = MJHMarker then
      begin
        if Pos + 2 >= Len then
          Break;  // truncated run packet
        Count := Data[Pos + 1];
        Value := Data[Pos + 2];
        Pos := Pos + 3;
        if Count = 0 then
          Count := 256;  // a count of zero means 256 repeats
        if Count > BlockLen - Produced then
          Count := BlockLen - Produced;  // never overrun the block (surplus ignored)
        for I := 1 to Count do
        begin
          Result[OutLen + Produced] := Value;
          Inc(Produced);
        end;
      end
      else
      begin
        Result[OutLen + Produced] := Data[Pos];
        Inc(Pos);
        Inc(Produced);
      end;
    end;
    OutLen := OutLen + Produced;
  end;

  SetLength(Result, OutLen);  // trim any over-allocation from a short final block
end;

const
  // A mode is judged "banded" when its busiest within-byte edge phase exceeds
  // the average within-byte phase by these factors. Decoding data at too high a
  // resolution piles edges onto the bit-interleave-aligned boundary, so the
  // ratio towers; a coherent image spreads edges evenly and stays near 1.
  //
  // Two thresholds because the two decision points have different phase counts
  // (mode 2 has 7 within-byte boundaries, mode 1 has 3) and so different scales.
  // Calibrated against known mode-0/1 sample screens: mode-1 screens score
  // <= 1.28 at mode 1 while mode-0 screens score >= 1.41, and every non-mode-2
  // screen scores >= 1.43 at mode 2. The thresholds sit in those gaps.
  Mode2BandingThreshold = 1.38;  // below this, mode 2 looks coherent -> mode 2
  Mode1BandingThreshold = 1.35;  // at/above this, mode 1 still bands -> mode 0
  // Screens with almost no horizontal detail give no banding signal at all;
  // treat any overall edge fraction below this as "flat" and fall back to mode 1.
  FlatEdgeFloor = 0.01;

// Score how strongly a mode shows vertical-line banding. Returns the ratio of
// the busiest within-byte edge phase to the mean within-byte phase (>= 1, higher
// means more banding) and reports the overall edge fraction via OverallEdgeFrac.
function ModeBandingScore(const Data: array of byte; Mode: TAmstradMode;
  Offset, BytesPerRow, Rows: integer; Interleaved: boolean;
  out OverallEdgeFrac: Double): Double;
var
  PixelsPerLine, PixelsPerByte, RowPixels, Y, X, Phase, NumPhases: integer;
  Row: array of integer;
  PhaseEdges, PhaseBounds: array of int64;
  TotalEdges, TotalBounds: int64;
  EdgeFrac, MaxFrac, SumFrac, MeanFrac: double;
begin
  Result := 0;
  OverallEdgeFrac := 0;
  Row := nil;
  PhaseEdges := nil;
  PhaseBounds := nil;
  ModeMetrics(Mode, PixelsPerLine, PixelsPerByte);
  if PixelsPerByte < 2 then
    Exit;  // need at least one within-byte boundary to measure

  RowPixels := BytesPerRow * PixelsPerByte;
  SetLength(Row, RowPixels);
  SetLength(PhaseEdges, PixelsPerByte);
  SetLength(PhaseBounds, PixelsPerByte);
  for X := 0 to PixelsPerByte - 1 do
  begin
    PhaseEdges[X] := 0;
    PhaseBounds[X] := 0;
  end;

  for Y := 0 to Rows - 1 do
  begin
    DecodeRow(Data, Mode, Offset, Y, PixelsPerByte, BytesPerRow, Interleaved, Row);
    for X := 0 to RowPixels - 2 do
    begin
      Phase := X mod PixelsPerByte;  // 0..ppb-2 within a byte, ppb-1 crosses bytes
      Inc(PhaseBounds[Phase]);
      if Row[X] <> Row[X + 1] then
        Inc(PhaseEdges[Phase]);
    end;
  end;

  TotalEdges := 0;
  TotalBounds := 0;
  for X := 0 to PixelsPerByte - 1 do
  begin
    TotalEdges := TotalEdges + PhaseEdges[X];
    TotalBounds := TotalBounds + PhaseBounds[X];
  end;
  if TotalBounds > 0 then
    OverallEdgeFrac := TotalEdges / TotalBounds;

  // Compare only the within-byte boundaries (phases 0..ppb-2); the cross-byte
  // boundary reflects genuine adjacent content and is excluded.
  MaxFrac := 0;
  SumFrac := 0;
  NumPhases := 0;
  for Phase := 0 to PixelsPerByte - 2 do
    if PhaseBounds[Phase] > 0 then
    begin
      EdgeFrac := PhaseEdges[Phase] / PhaseBounds[Phase];
      SumFrac := SumFrac + EdgeFrac;
      Inc(NumPhases);
      if EdgeFrac > MaxFrac then
        MaxFrac := EdgeFrac;
    end;
  if NumPhases = 0 then
    Exit;
  MeanFrac := SumFrac / NumPhases;
  if MeanFrac > 0 then
    Result := MaxFrac / MeanFrac;
end;

// Guess the display mode of an image (screen or window) by looking for the
// vertical-line banding that appears when data is decoded too high a resolution.
function GuessModeFor(const Data: array of byte; Offset, BytesPerRow, Rows: integer;
  Interleaved: boolean): TAmstradMode;
var
  Score2, Score1, Overall2, Overall1: double;
begin
  // Start at the highest resolution and step down: a coherent image stays put,
  // banding means the data was authored for a lower-resolution mode.
  Score2 := ModeBandingScore(Data, amMode2, Offset, BytesPerRow, Rows, Interleaved, Overall2);

  // No horizontal detail at all - nothing to analyse, keep the historical default.
  if Overall2 < FlatEdgeFloor then
  begin
    Result := amMode1;
    Exit;
  end;

  // Mode 2 looks coherent -> the screen was meant for mode 2.
  if Score2 < Mode2BandingThreshold then
  begin
    Result := amMode2;
    Exit;
  end;

  // Mode 2 banded; retry at mode 1. Coherent -> mode 1, still banded -> mode 0.
  Score1 := ModeBandingScore(Data, amMode1, Offset, BytesPerRow, Rows, Interleaved, Overall1);
  if Score1 < Mode1BandingThreshold then
    Result := amMode1
  else
    Result := amMode0;
end;

// Detect an Advanced OCP Art Studio window clip. The (uncompressed) window ends
// with a 4-byte block (width in mode-2 pixels, height in lines, spare) preceded
// by one further byte, so 5 bytes of trailer follow the linear pixel data.
function ParseWindow(const Data: array of byte; out BytesPerRow, Rows: integer): boolean;
var
  Len, PixLen, Width: integer;
begin
  Result := False;
  BytesPerRow := 0;
  Rows := 0;
  Len := Length(Data);
  if Len < 6 then
    Exit;

  Rows := Data[Len - 2];
  if (Rows < 1) or (Rows > CPCLines) then
    Exit;

  PixLen := Len - 5;
  if (PixLen < 1) or (PixLen mod Rows <> 0) then
    Exit;

  BytesPerRow := PixLen div Rows;
  if (BytesPerRow < 1) or (BytesPerRow > CPCBytesPerLine) then
    Exit;

  // Sanity-check the stored width against the row length so we don't mistake an
  // arbitrary file for a window: width is in mode-2 pixels, ~8 per stored byte.
  Width := ReadWordLE(Data, Len - 4);
  if (Width > BytesPerRow * 8) or (Width <= (BytesPerRow - 2) * 8) then
    Exit;

  Result := True;
end;

class function TAmstradScreen.LoadImage(const Raw: array of byte;
  out Image: TAmstradImage): boolean;
var
  BytesPerRow, Rows: integer;
begin
  Result := False;

  if IsMJHCompressed(Raw) then
    Image.Data := DecompressMJH(Raw)
  else
  begin
    SetLength(Image.Data, Length(Raw));
    if Length(Raw) > 0 then
      Move(Raw[0], Image.Data[0], Length(Raw));
  end;

  if IsValidScreenSize(Length(Image.Data)) then
  begin
    Image.BytesPerRow := CPCBytesPerLine;
    Image.Rows := CPCLines;
    Image.Interleaved := True;
    Image.IsWindow := False;
    Image.Mode := GuessModeFor(Image.Data, 0, CPCBytesPerLine, CPCLines, True);
    Result := True;
  end
  else if ParseWindow(Image.Data, BytesPerRow, Rows) then
  begin
    Image.BytesPerRow := BytesPerRow;
    Image.Rows := Rows;
    Image.Interleaved := False;
    Image.IsWindow := True;
    Image.Mode := GuessModeFor(Image.Data, 0, BytesPerRow, Rows, False);
    Result := True;
  end;
end;

class function TAmstradScreen.CanDisplay(const Raw: array of byte): boolean;
var
  Decoded: TDiskByteArray;
  BytesPerRow, Rows: integer;
begin
  if IsMJHCompressed(Raw) then
  begin
    Decoded := DecompressMJH(Raw);
    Result := IsValidScreenSize(Length(Decoded)) or
              ParseWindow(Decoded, BytesPerRow, Rows);
  end
  else
    Result := IsValidScreenSize(Length(Raw)) or
              ParseWindow(Raw, BytesPerRow, Rows);
end;

class procedure TAmstradScreen.RenderImage(const Image: TAmstradImage;
  Bitmap: TBitmap; Zoom: integer);
var
  PenColor: array[0..15] of TColor;
  PixelsPerLine, PixelsPerByte, PixelWidth: integer;
  Y, Col, LineBase, P, LX, Left, Top, BlockW, BlockH: integer;
  B: byte;
  DataLen: integer;

begin
  if Zoom < 1 then
    Zoom := 1;

  ModeMetrics(Image.Mode, PixelsPerLine, PixelsPerByte);
  PixelWidth := 8 div PixelsPerByte;  // display units per pixel: 4, 2 or 1

  for P := 0 to 15 do
    PenColor[P] := RGBToColor(HardwarePalette[DefaultInk[P]].R,
      HardwarePalette[DefaultInk[P]].G, HardwarePalette[DefaultInk[P]].B);

  BlockW := PixelWidth * Zoom;
  BlockH := 2 * Zoom;  // scanlines are doubled to keep a sensible aspect ratio

  Bitmap.PixelFormat := pf24bit;
  Bitmap.Width := Image.BytesPerRow * PixelsPerByte * BlockW;
  Bitmap.Height := Image.Rows * BlockH;

  DataLen := Length(Image.Data);

  for Y := 0 to Image.Rows - 1 do
  begin
    if Image.Interleaved then
      LineBase := ScreenLineBase(Y)
    else
      LineBase := Y * Image.BytesPerRow;
    Top := Y * BlockH;

    for Col := 0 to Image.BytesPerRow - 1 do
    begin
      if (LineBase + Col >= 0) and (LineBase + Col < DataLen) then
        B := Image.Data[LineBase + Col]
      else
        B := 0;

      for P := 0 to PixelsPerByte - 1 do
      begin
        LX := Col * PixelsPerByte + P;
        Left := LX * BlockW;
        Bitmap.Canvas.Brush.Color := PenColor[DecodePen(B, P, Image.Mode)];
        Bitmap.Canvas.FillRect(Left, Top, Left + BlockW, Top + BlockH);
      end;
    end;
  end;
end;

end.
