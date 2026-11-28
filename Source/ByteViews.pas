unit ByteViews;

{$MODE Delphi}

{
  Disk Image Manager - a file's bytes laid out as hex, Z80 code or plain text

  Each is an RTF document. The hex and code views also record which bytes every
  line shows, so that a place in the text can be traced back to the file.

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Classes, SysUtils, Z80Disasm;

const
  HexBytesPerLine = 16;
  // The most lines worth colouring: the text control takes far longer to load a
  // document the more changes of colour it holds
  ColouredLineLimit = 12000;

type
  // The characters the hex view shows beyond ASCII
  TByteCharset = (csASCII, csSpectrum);

  TByteViewKind = (vkHex, vkZ80);

  TByteViewLine = record
    // Characters in the text before this line, each line ending counting as one
    Position: integer;
    // The first byte the line shows, and how many
    Offset: integer;
    Count: integer;
  end;

  TByteView = class
  private
    FKind: TByteViewKind;
    FLines: array of TByteViewLine;
    FLineCount: integer;
    // Where the bytes start on a hex line, which depends on the address width
    FHexColumn: integer;
    function GetLine(Index: integer): TByteViewLine;
    procedure AddLine(Position, Offset, Count: integer);
  public
    RTF: AnsiString;
    // The line holding a character position, or -1 if there are no lines
    function LineAt(Position: integer): integer;
    // The line showing a byte, or -1 if there are no lines
    function LineOf(Offset: integer): integer;
    // The byte a character position points at, or -1 if there are no lines
    function OffsetAt(Position: integer): integer;
    property Kind: TByteViewKind read FKind;
    property LineCount: integer read FLineCount;
    property Lines[Index: integer]: TByteViewLine read GetLine;
  end;

// Address, bytes and characters, sixteen to a line. The first byte is shown at
// Origin. The caller frees the view.
function BuildHexView(const Data: array of byte; Origin: integer;
  Charset: TByteCharset; const FontName: string): TByteView;

// Address, bytes and instruction, the first byte being at Origin. An instruction
// is made to start at each of the sync points, offsets into the data, whatever
// comes before it. The caller frees the view.
function BuildZ80View(const Data: array of byte; Origin: integer;
  const SyncPoints: array of integer; const FontName: string): TByteView;

// The bytes as ASCII text, showing a dot for anything else
function BuildASCIITextRTF(const Data: array of byte; const FontName: string): AnsiString;

implementation

const
  // Grey for addresses, then the colours of numbers, jump and memory addresses,
  // ports and characters
  ColourTable = '{\colortbl;\red128\green128\blue128;\red0\green0\blue170;' +
    '\red128\green0\blue128;\red170\green0\blue0;\red0\green110\blue0;}';
  ColourAddress = '1';
  ColourValue = '2';
  ColourLocation = '3';
  ColourPort = '4';
  ColourCharacters = '5';

function RTFStart(const FontName: string): AnsiString;
begin
  Result := '{\rtf1\ansi\deff0{\fonttbl{\f0\fmodern ' + FontName + ';}}' +
    ColourTable + '\f0\fs20 ';
end;

function Coloured(const Text: string; const Colour: Char; Wanted: boolean): string;
begin
  if Wanted then
    Result := '{\cf' + Colour + ' ' + Text + '}'
  else
    Result := Text;
end;

// One byte as it appears in a column of characters
function Character(B: byte; Charset: TByteCharset): string;
begin
  // The Spectrum has a pound sign for the backtick and a copyright sign after
  // the tilde
  if (Charset = csSpectrum) and (B = 96) then
    Result := '\u163?'
  else if (Charset = csSpectrum) and (B = 127) then
    Result := '\u169?'
  else if (B < 32) or (B > 126) then
    Result := '.'
  else if Chr(B) in ['\', '{', '}'] then
    Result := '\' + Chr(B)
  else
    Result := Chr(B);
end;

// TByteView

procedure TByteView.AddLine(Position, Offset, Count: integer);
begin
  if FLineCount = Length(FLines) then
    SetLength(FLines, FLineCount * 2 + 64);
  FLines[FLineCount].Position := Position;
  FLines[FLineCount].Offset := Offset;
  FLines[FLineCount].Count := Count;
  Inc(FLineCount);
end;

function TByteView.GetLine(Index: integer): TByteViewLine;
begin
  Result := FLines[Index];
end;

function TByteView.LineAt(Position: integer): integer;
var
  Low, High, Middle: integer;
begin
  Low := 0;
  High := FLineCount - 1;
  while Low < High do
  begin
    Middle := (Low + High + 1) div 2;
    if FLines[Middle].Position <= Position then
      Low := Middle
    else
      High := Middle - 1;
  end;
  if FLineCount = 0 then
    Result := -1
  else
    Result := Low;
end;

function TByteView.LineOf(Offset: integer): integer;
var
  Low, High, Middle: integer;
begin
  Low := 0;
  High := FLineCount - 1;
  while Low < High do
  begin
    Middle := (Low + High + 1) div 2;
    if FLines[Middle].Offset <= Offset then
      Low := Middle
    else
      High := Middle - 1;
  end;
  if FLineCount = 0 then
    Result := -1
  else
    Result := Low;
end;

function TByteView.OffsetAt(Position: integer): integer;
var
  Line, Column, Idx, CharacterColumn: integer;
begin
  Line := LineAt(Position);
  if Line < 0 then
    exit(-1);
  Result := FLines[Line].Offset;
  if FKind <> vkHex then
    exit;

  // On a hex line the column picks the byte, among either the numbers or the
  // characters. The numbers have an extra space half way.
  Column := Position - FLines[Line].Position;
  CharacterColumn := FHexColumn + HexBytesPerLine * 3 + 2;
  if Column >= CharacterColumn then
    Idx := Column - CharacterColumn
  else
  begin
    Dec(Column, FHexColumn);
    if Column >= HexBytesPerLine div 2 * 3 then
      Dec(Column);
    if Column < 0 then
      Column := 0;
    Idx := Column div 3;
  end;
  if Idx >= FLines[Line].Count then
    Idx := FLines[Line].Count - 1;
  Inc(Result, Idx);
end;

function BuildHexView(const Data: array of byte; Origin: integer;
  Charset: TByteCharset; const FontName: string): TByteView;
var
  Output: TStringStream;
  Offset, Idx, Count, Position, Width: integer;
  Numbers, Characters, Address: string;
  Colour: boolean;
begin
  Result := TByteView.Create;
  Result.FKind := vkHex;
  Width := Length(IntToHex(Origin + Length(Data) - 1, 4));
  if Length(Data) = 0 then
    Width := Length(IntToHex(Origin, 4));
  Result.FHexColumn := Width + 2;
  Colour := Length(Data) div HexBytesPerLine < ColouredLineLimit;

  Output := TStringStream.Create('');
  try
    Output.WriteString(RTFStart(FontName));
    Offset := 0;
    Position := 0;
    while Offset < Length(Data) do
    begin
      Count := Length(Data) - Offset;
      if Count > HexBytesPerLine then
        Count := HexBytesPerLine;

      // A short last line is padded so that its characters line up
      Numbers := '';
      Characters := '';
      for Idx := 0 to HexBytesPerLine - 1 do
      begin
        if Idx < Count then
        begin
          Numbers := Numbers + IntToHex(Data[Offset + Idx], 2) + ' ';
          Characters := Characters + Character(Data[Offset + Idx], Charset);
        end
        else
          Numbers := Numbers + '   ';
        if Idx = HexBytesPerLine div 2 - 1 then
          Numbers := Numbers + ' ';
      end;

      Address := IntToHex(Origin + Offset, Width);
      if Offset > 0 then
        Output.WriteString('\par ');
      Output.WriteString(Coloured(Address, ColourAddress, Colour) + '  ' +
        Numbers + ' ' + Coloured(Characters, ColourCharacters, Colour));
      Result.AddLine(Position, Offset, Count);
      // The address, two spaces, the numbers, a space, a character each and the
      // line ending
      Inc(Position, Width + 2 + HexBytesPerLine * 3 + 1 + 1 + Count + 1);
      Inc(Offset, Count);
    end;
    Output.WriteString('}');
    Result.RTF := Output.DataString;
  finally
    Output.Free;
  end;
end;

function BuildZ80View(const Data: array of byte; Origin: integer;
  const SyncPoints: array of integer; const FontName: string): TByteView;
var
  Output: TStringStream;
  Sorted: array of integer;
  Offset, Idx, Other, Held, Next, Boundary, Size, Position, Visible: integer;
  Instruction: TZ80Instruction;
  Numbers, Text, Shown: string;
  Address: word;
  Colour, Open: boolean;
  C: char;
begin
  Result := TByteView.Create;
  Result.FKind := vkZ80;
  // Instructions average a little under two bytes
  Colour := Length(Data) div 2 < ColouredLineLimit;

  SetLength(Sorted, Length(SyncPoints));
  for Idx := 0 to High(SyncPoints) do
  begin
    Held := SyncPoints[Idx];
    Other := Idx - 1;
    while (Other >= 0) and (Sorted[Other] > Held) do
    begin
      Sorted[Other + 1] := Sorted[Other];
      Dec(Other);
    end;
    Sorted[Other + 1] := Held;
  end;

  Output := TStringStream.Create('');
  try
    Output.WriteString(RTFStart(FontName));
    Offset := 0;
    Position := 0;
    Next := 0;
    while Offset < Length(Data) do
    begin
      while (Next < Length(Sorted)) and (Sorted[Next] <= Offset) do
        Inc(Next);
      Boundary := Length(Data);
      if (Next < Length(Sorted)) and (Sorted[Next] < Boundary) then
        Boundary := Sorted[Next];

      Address := word((Origin + Offset) and $FFFF);
      Instruction := DisassembleZ80(Data, Offset, Address);
      Size := Instruction.Size;
      Text := Instruction.Text;
      // One that would run into the next sync point, or off the end, is only
      // bytes
      if Offset + Size > Boundary then
      begin
        Size := Boundary - Offset;
        Text := 'DB ';
        for Idx := 0 to Size - 1 do
        begin
          if Idx > 0 then
            Text := Text + ',';
          Text := Text + MarkValue + IntToHex(Data[Offset + Idx], 2) + MarkValue;
        end;
      end;

      Numbers := '';
      for Idx := 0 to Size - 1 do
        Numbers := Numbers + IntToHex(Data[Offset + Idx], 2) + ' ';

      Shown := '';
      Visible := 0;
      Open := False;
      for C in Text do
        if C in [MarkValue, MarkAddress, MarkPort] then
        begin
          if Colour then
          begin
            if Open then
              Shown := Shown + '}'
            else if C = MarkValue then
              Shown := Shown + '{\cf' + ColourValue + ' '
            else if C = MarkAddress then
              Shown := Shown + '{\cf' + ColourLocation + ' '
            else
              Shown := Shown + '{\cf' + ColourPort + ' ';
            Open := not Open;
          end;
        end
        else
        begin
          Shown := Shown + C;
          Inc(Visible);
        end;

      if Offset > 0 then
        Output.WriteString('\par ');
      Output.WriteString(Coloured(IntToHex(Address, 4), ColourAddress, Colour) +
        '  ' + Format('%-13s', [Numbers]) + Shown);
      Result.AddLine(Position, Offset, Size);
      // The address, two spaces, the bytes, the instruction and the line ending
      Inc(Position, 4 + 2 + 13 + Visible + 1);
      Inc(Offset, Size);
    end;
    Output.WriteString('}');
    Result.RTF := Output.DataString;
  finally
    Output.Free;
  end;
end;

function BuildASCIITextRTF(const Data: array of byte; const FontName: string): AnsiString;
var
  Output: TStringStream;
  Idx: integer;
begin
  Output := TStringStream.Create('');
  try
    Output.WriteString(RTFStart(FontName));
    Idx := 0;
    while Idx < Length(Data) do
    begin
      case Data[Idx] of
        9: Output.WriteString('\tab ');
        10: Output.WriteString('\par ');
        13:
          begin
            Output.WriteString('\par ');
            if (Idx < High(Data)) and (Data[Idx + 1] = 10) then
              Inc(Idx);
          end;
        else
          Output.WriteString(Character(Data[Idx], csASCII));
      end;
      Inc(Idx);
    end;
    Output.WriteString('}');
    Result := Output.DataString;
  finally
    Output.Free;
  end;
end;

end.
