unit SpectrumScreen;

{$MODE Delphi}

{
  Disk Image Manager - ZX Spectrum SCREEN$ decoder

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

  Based on https://github.com/damieng/retro-render Screen.ts
}

interface

uses
  Graphics, Classes, SysUtils;

const
  ScreenWidth = 256;
  ScreenHeight = 192;
  AttributeWidth = 32;
  AttributeHeight = 24;
  AttributeOffset = 6144;
  ScreenSizeWithColor = 6912;
  ScreenSizeNoColor = 6144;

type
  TSpectrumColor = record
    R, G, B: byte;
  end;

  TSpectrumColorPair = array[0..1] of TSpectrumColor;

  TSpectrumScreen = class
  private
    class var FLookupY: array[0..191] of integer;
    class var FInitialized: boolean;
    class procedure Initialize;
    class function GetAttributeColors(Attribute: byte; FlashPhase: boolean): TSpectrumColorPair;
  public
    class function IsValidScreenSize(Size: integer): boolean;
    class function HasColor(Size: integer): boolean;
    class function HasFlashAttribute(const Data: array of byte): boolean;
    class procedure RenderToCanvas(const Data: array of byte; Canvas: TCanvas;
      OffsetX: integer = 0; OffsetY: integer = 0; Scale: integer = 1;
      FlashPhase: boolean = False);
    class procedure RenderToBitmap(const Data: array of byte; Bitmap: TBitmap;
      Scale: integer = 1; FlashPhase: boolean = False);
  end;

implementation

const
  // Spectrum palette - normal brightness
  PaletteNormal: array[0..7] of TSpectrumColor = (
    (R: $00; G: $00; B: $00),  // Black
    (R: $00; G: $00; B: $CD),  // Blue
    (R: $CD; G: $00; B: $00),  // Red
    (R: $CD; G: $00; B: $CD),  // Magenta
    (R: $00; G: $CD; B: $00),  // Green
    (R: $00; G: $CD; B: $CD),  // Cyan
    (R: $CD; G: $CD; B: $00),  // Yellow
    (R: $CD; G: $CD; B: $CD)   // White
  );

  // Spectrum palette - bright
  PaletteBright: array[0..7] of TSpectrumColor = (
    (R: $00; G: $00; B: $00),  // Black (same as normal)
    (R: $00; G: $00; B: $FF),  // Bright Blue
    (R: $FF; G: $00; B: $00),  // Bright Red
    (R: $FF; G: $00; B: $FF),  // Bright Magenta
    (R: $00; G: $FF; B: $00),  // Bright Green
    (R: $00; G: $FF; B: $FF),  // Bright Cyan
    (R: $FF; G: $FF; B: $00),  // Bright Yellow
    (R: $FF; G: $FF; B: $FF)   // Bright White
  );

class procedure TSpectrumScreen.Initialize;
var
  Y, Third, ThirdRow, CharRow, ScanLine: integer;
begin
  if FInitialized then Exit;

  // Build the Y lookup table for Spectrum's unusual screen layout
  // The screen is divided into 3 thirds of 64 lines each
  // Within each third, lines are interleaved in groups of 8
  for Y := 0 to 191 do
  begin
    Third := Y div 64;           // Which third (0-2)
    ThirdRow := Y mod 64;        // Row within third (0-63)
    CharRow := ThirdRow div 8;   // Character row within third (0-7)
    ScanLine := ThirdRow mod 8;  // Scan line within character (0-7)

    // Memory offset = (third * 2048) + (scanline * 256) + (charrow * 32)
    FLookupY[Y] := (Third * 2048) + (ScanLine * 256) + (CharRow * 32);
  end;

  FInitialized := True;
end;

class function TSpectrumScreen.IsValidScreenSize(Size: integer): boolean;
begin
  Result := (Size = ScreenSizeWithColor) or (Size = ScreenSizeNoColor);
end;

class function TSpectrumScreen.HasColor(Size: integer): boolean;
begin
  Result := Size = ScreenSizeWithColor;
end;

class function TSpectrumScreen.HasFlashAttribute(const Data: array of byte): boolean;
var
  I: integer;
begin
  Result := False;

  // Only check if we have color attributes
  if Length(Data) <> ScreenSizeWithColor then
    Exit;

  // Check each attribute byte for FLASH bit (bit 7)
  for I := 0 to (AttributeWidth * AttributeHeight) - 1 do
  begin
    if (Data[AttributeOffset + I] and $80) <> 0 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

class function TSpectrumScreen.GetAttributeColors(Attribute: byte; FlashPhase: boolean): TSpectrumColorPair;
var
  Ink, Paper: byte;
  Bright, Flash: boolean;
begin
  Ink := Attribute and $07;
  Paper := (Attribute shr 3) and $07;
  Bright := (Attribute and $40) <> 0;
  Flash := (Attribute and $80) <> 0;

  // When flash is active and we're in the alternate phase, swap ink and paper
  if Flash and FlashPhase then
  begin
    // Swap ink and paper
    Ink := Ink xor Paper;
    Paper := Ink xor Paper;
    Ink := Ink xor Paper;
  end;

  if Bright then
  begin
    Result[0] := PaletteBright[Paper];
    Result[1] := PaletteBright[Ink];
  end
  else
  begin
    Result[0] := PaletteNormal[Paper];
    Result[1] := PaletteNormal[Ink];
  end;
end;

class procedure TSpectrumScreen.RenderToCanvas(const Data: array of byte;
  Canvas: TCanvas; OffsetX: integer; OffsetY: integer; Scale: integer;
  FlashPhase: boolean);
var
  CellX, CellY, PixelX, PixelY: integer;
  X, Y: integer;
  Attribute, Pixels: byte;
  Colors: TSpectrumColorPair;
  Color: TSpectrumColor;
  Bit: byte;
  HasAttr: boolean;
begin
  Initialize;

  HasAttr := Length(Data) = ScreenSizeWithColor;

  // Default colours for mono screens: black ink on non-bright white paper,
  // matching the Spectrum's default screen attribute (paper 7, ink 0)
  Colors[0].R := 205; Colors[0].G := 205; Colors[0].B := 205;  // Paper (white)
  Colors[1].R := 0; Colors[1].G := 0; Colors[1].B := 0;        // Ink (black)

  for CellY := 0 to AttributeHeight - 1 do
  begin
    for CellX := 0 to AttributeWidth - 1 do
    begin
      // Get attribute colors for this cell
      if HasAttr then
      begin
        Attribute := Data[CellY * AttributeWidth + AttributeOffset + CellX];
        Colors := GetAttributeColors(Attribute, FlashPhase);
      end;

      // Process each pixel row in the 8x8 cell
      for PixelY := 0 to 7 do
      begin
        Y := (CellY * 8) + PixelY;
        Pixels := Data[FLookupY[Y] + CellX];

        for PixelX := 0 to 7 do
        begin
          Bit := 128 shr PixelX;
          X := (CellX * 8) + PixelX;

          if (Pixels and Bit) = Bit then
            Color := Colors[1]  // Ink
          else
            Color := Colors[0]; // Paper

          // Draw pixel with scaling
          Canvas.Brush.Color := TColor(Color.R or (Color.G shl 8) or (Color.B shl 16));
          Canvas.Pen.Color := Canvas.Brush.Color;

          if Scale = 1 then
            Canvas.Pixels[OffsetX + X, OffsetY + Y] := Canvas.Brush.Color
          else
            Canvas.FillRect(
              OffsetX + X * Scale,
              OffsetY + Y * Scale,
              OffsetX + X * Scale + Scale,
              OffsetY + Y * Scale + Scale
            );
        end;
      end;
    end;
  end;
end;

class procedure TSpectrumScreen.RenderToBitmap(const Data: array of byte;
  Bitmap: TBitmap; Scale: integer; FlashPhase: boolean);
begin
  Initialize;

  Bitmap.Width := ScreenWidth * Scale;
  Bitmap.Height := ScreenHeight * Scale;
  Bitmap.PixelFormat := pf24bit;

  RenderToCanvas(Data, Bitmap.Canvas, 0, 0, Scale, FlashPhase);
end;

end.
