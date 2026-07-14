unit SinclairBasic;

{$MODE Delphi}

{
  Disk Image Manager - Sinclair BASIC tokenized file decoder

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DskImage, FileSystem, Utils, SysUtils, Math;

type
  TSinclairBasicMode = (sbMode48K, sbMode128K);

  TSinclairBasicParser = class
  private
    FMode: TSinclairBasicMode;
    function GetTokenText(Token: byte): string;
    function DecodeSpectrumIntegral(const Bytes: array of byte): string;
    function DecodeSpectrumFloat(const Bytes: array of byte): string;
    function DecodeLine(const Data: array of byte; StartPos, Length: integer): string;
    function DecodeLineRTF(const Data: array of byte; StartPos, Length: integer): string;
    function GetSpecialChar(B: byte): string;
    function EscapeRTF(const S: string): string;
    function DecodeArrayChar(B: byte): string;
    function ParseStringArrayHeader(const Data: array of byte;
      out StartPos, StringLen, NumStrings: integer): boolean;
  public
    constructor Create(Mode: TSinclairBasicMode = sbMode128K);
    function Decode(const Data: array of byte): string;
    function DecodeFile(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
    function DecodeRTF(const Data: array of byte): string;
    function DecodeFileRTF(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
    function DecodeStringArray(const Data: array of byte): string;
    function DecodeStringArrayRTF(const Data: array of byte): string;
    function DecodeStringArrayFileRTF(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
    property Mode: TSinclairBasicMode read FMode write FMode;
  end;

implementation

const
  Tokens: array[$A5..$FF] of string = (
    'RND', 'INKEY$', 'PI', 'FN', 'POINT', 'SCREEN$', 'ATTR', 'AT', 'TAB',
    'VAL$', 'CODE', 'VAL', 'LEN', 'SIN', 'COS', 'TAN', 'ASN', 'ACS', 'ATN',
    'LN', 'EXP', 'INT', 'SQR', 'SGN', 'ABS', 'PEEK', 'IN', 'USR', 'STR$',
    'CHR$', 'NOT', 'BIN', 'OR', 'AND', '<=', '>=', '<>', 'LINE', 'THEN',
    'TO', 'STEP', 'DEF FN', 'CAT', 'FORMAT', 'MOVE', 'ERASE', 'OPEN #',
    'CLOSE #', 'MERGE', 'VERIFY', 'BEEP', 'CIRCLE', 'INK', 'PAPER', 'FLASH',
    'BRIGHT', 'INVERSE', 'OVER', 'OUT', 'LPRINT', 'LLIST', 'STOP', 'READ',
    'DATA', 'RESTORE', 'NEW', 'BORDER', 'CONTINUE', 'DIM', 'REM', 'FOR',
    'GO TO', 'GO SUB', 'INPUT', 'LOAD', 'LIST', 'LET', 'PAUSE', 'NEXT',
    'POKE', 'PRINT', 'PLOT', 'RUN', 'SAVE', 'RANDOMIZE', 'IF', 'CLS',
    'DRAW', 'CLEAR', 'RETURN', 'COPY'
  );

constructor TSinclairBasicParser.Create(Mode: TSinclairBasicMode);
begin
  inherited Create;
  FMode := Mode;
end;

function TSinclairBasicParser.GetTokenText(Token: byte): string;
begin
  case Token of
    $A3:
      if FMode = sbMode128K then
        Result := 'SPECTRUM'
      else
        Result := 'UDG-A';
    $A4:
      if FMode = sbMode128K then
        Result := 'PLAY'
      else
        Result := 'UDG-B';
    $A5..$FF:
      Result := Tokens[Token];
  else
    Result := Format('?%02X?', [Token]);
  end;
end;

function TSinclairBasicParser.DecodeSpectrumIntegral(const Bytes: array of byte): string;
var
  SignByte: byte;
  Low, High: word;
  UnsignedValue: word;
  Value: integer;
begin
  if Length(Bytes) < 5 then
  begin
    Result := '';
    Exit;
  end;

  // Format: [0, sign_byte, low, high, 0]
  // Skip display - the ASCII representation precedes this
  SignByte := Bytes[1];
  Low := Bytes[2];
  High := Bytes[3];
  UnsignedValue := Low or (High shl 8);

  if SignByte = $FF then
    Value := integer(UnsignedValue) - 65536
  else
    Value := UnsignedValue;

  Result := '';  // Don't output - the number is already in ASCII form before this marker
end;

function TSinclairBasicParser.DecodeSpectrumFloat(const Bytes: array of byte): string;
var
  ExponentBiased: byte;
  Exponent: integer;
  IsNegative: boolean;
  Byte1WithoutSign: byte;
  MantissaLower31: cardinal;
  Mantissa: cardinal;
  MantissaF, ExpF, Value: double;
begin
  if Length(Bytes) < 5 then
  begin
    Result := '';
    Exit;
  end;

  ExponentBiased := Bytes[0];
  Exponent := integer(ExponentBiased) - 128;

  // Extract sign from bit 7 of byte 1
  IsNegative := (Bytes[1] and $80) <> 0;

  // Clear sign bit and reconstruct mantissa (big-endian in bytes 1-4)
  Byte1WithoutSign := Bytes[1] and $7F;
  MantissaLower31 := (cardinal(Byte1WithoutSign) shl 24) or
                     (cardinal(Bytes[2]) shl 16) or
                     (cardinal(Bytes[3]) shl 8) or
                     cardinal(Bytes[4]);
  MantissaLower31 := MantissaLower31 and $7FFFFFFF;

  // Reconstruct full mantissa with implicit bit 31 set
  Mantissa := $80000000 or MantissaLower31;

  // Calculate value: (mantissa / 2^31) * 2^exponent
  MantissaF := Mantissa / 2147483648.0;  // 2^31
  ExpF := Power(2.0, Exponent);
  Value := MantissaF * ExpF;

  if IsNegative then
    Value := -Value;

  Result := '';  // Don't output - the number is already in ASCII form before this marker
end;

function TSinclairBasicParser.GetSpecialChar(B: byte): string;
begin
  case B of
    $7F: Result := #$C2#$A9;  // Copyright symbol (UTF-8)
    $80..$8F: Result := '[UDG]';
    $90..$9F: Result := '[GRAPH]';
    $A0: Result := ' ';
    $A1: Result := #$C2#$A3;  // Pound sign (UTF-8)
    $A2: Result := '$';
  else
    Result := '?';
  end;
end;

function TSinclairBasicParser.DecodeLine(const Data: array of byte; StartPos, Length: integer): string;
var
  Pos, EndPos: integer;
  B: byte;
  LastWasSpace: boolean;
begin
  Result := '';
  Pos := StartPos;
  EndPos := StartPos + Length;
  LastWasSpace := True;  // Start of line counts as "after space"

  while Pos < EndPos do
  begin
    if Pos >= System.Length(Data) then
      Break;

    B := Data[Pos];
    Inc(Pos);

    case B of
      // End of line marker
      $0D:
        Break;

      // Number marker (integral format) - skip 5 bytes
      // The ASCII representation precedes this, so we just skip the binary
      $0E:
        begin
          if Pos + 5 <= EndPos then
            Inc(Pos, 5)  // Skip the 5-byte number representation
          else
            Pos := EndPos;  // Not enough data, skip to end
        end;

      // Number marker (floating point format) - skip 5 bytes
      // Same as above - ASCII already displayed
      $7E:
        begin
          if Pos + 5 <= EndPos then
            Inc(Pos, 5)  // Skip the 5-byte number representation
          else
            Pos := EndPos;  // Not enough data, skip to end
        end;

      // Tokens $A3 and $A4 (mode-dependent)
      $A3, $A4:
        begin
          if not LastWasSpace then
            Result := Result + ' ';
          Result := Result + GetTokenText(B) + ' ';
          LastWasSpace := True;
        end;

      // Tokens $A5-$FF are BASIC keywords
      $A5..$FF:
        begin
          if not LastWasSpace then
            Result := Result + ' ';
          Result := Result + GetTokenText(B) + ' ';
          LastWasSpace := True;
        end;

      // Regular printable ASCII (excluding 0x7E which is the float marker)
      $20..$7D, $7F:
        begin
          if B = $7F then
            Result := Result + GetSpecialChar(B)  // Copyright symbol
          else
            Result := Result + Chr(B);
          LastWasSpace := (B = $20);
        end;

      // Extended characters (0x80-0xA2, note: 0x7F is handled above with ASCII)
      $80..$A2:
        begin
          Result := Result + GetSpecialChar(B);
          LastWasSpace := False;
        end;

      // Control characters and others - skip
    else
      // Unknown - skip
    end;
  end;
end;

function TSinclairBasicParser.Decode(const Data: array of byte): string;
var
  Pos, DataLen: integer;
  LineNum: word;
  LineLen: word;
  LineText: string;
begin
  Result := '';
  Pos := 0;
  DataLen := System.Length(Data);

  while Pos < DataLen do
  begin
    // Need at least 4 bytes for line header
    if Pos + 4 > DataLen then
      Break;

    // Read line number (2 bytes, big-endian)
    LineNum := (word(Data[Pos]) shl 8) or word(Data[Pos + 1]);
    Inc(Pos, 2);

    // Valid Spectrum BASIC line numbers are 0-9999
    if LineNum > 9999 then
      Break;

    // Read line length (2 bytes, little-endian)
    LineLen := word(Data[Pos]) or (word(Data[Pos + 1]) shl 8);
    Inc(Pos, 2);

    // Validate line length
    if LineLen < 1 then
      Break;

    // Decode the line
    LineText := DecodeLine(Data, Pos, LineLen);
    Result := Result + Format('%d %s'#13#10, [LineNum, LineText]);

    // Move to next line
    Inc(Pos, LineLen);
  end;
end;

function TSinclairBasicParser.DecodeFile(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
var
  FileData: TDiskByteArray;
  BasicData: TDiskByteArray;
  ProgLength: word;
begin
  Result := '';

  // Check if this is a PLUS3DOS BASIC file
  if (DiskFile.HeaderType <> 'PLUS3DOS') or
     (not DiskFile.Meta.StartsWith('BASIC')) then
    Exit;

  // Get file data with header so we can read the variable area offset
  FileData := DiskFile.GetData(True);
  if System.Length(FileData) < 128 then
    Exit;

  // PLUS3DOS header bytes 20-21 contain the offset to the variable area
  // which is the length of just the BASIC program (excluding variables)
  ProgLength := word(FileData[20]) or (word(FileData[21]) shl 8);
  if ProgLength = 0 then
    Exit;
  if ProgLength > System.Length(FileData) - 128 then
    ProgLength := System.Length(FileData) - 128;

  BasicData := Copy(FileData, 128, ProgLength);
  Result := Decode(BasicData);
end;

function TSinclairBasicParser.EscapeRTF(const S: string): string;
var
  I: integer;
begin
  Result := '';
  for I := 1 to Length(S) do
    case S[I] of
      '\': Result := Result + '\\';
      '{': Result := Result + '\{';
      '}': Result := Result + '\}';
    else
      Result := Result + S[I];
    end;
end;

function TSinclairBasicParser.DecodeLineRTF(const Data: array of byte; StartPos, Length: integer): string;
var
  Pos, EndPos: integer;
  B: byte;
  InString, InREM, LastWasSpace: boolean;
  TokenText: string;
begin
  Result := '';
  Pos := StartPos;
  EndPos := StartPos + Length;
  InString := False;
  InREM := False;
  LastWasSpace := True;

  while Pos < EndPos do
  begin
    if Pos >= System.Length(Data) then
      Break;

    B := Data[Pos];
    Inc(Pos);

    if B = $0D then
      Break;

    // Inside a REM comment - everything is green, no token parsing
    if InREM then
    begin
      case B of
        $0E, $7E:
          begin
            if Pos + 5 <= EndPos then
              Inc(Pos, 5)
            else
              Pos := EndPos;
          end;
        $20..$7D:
          Result := Result + EscapeRTF(Chr(B));
        $7F..$A2:
          Result := Result + EscapeRTF(GetSpecialChar(B));
        $A3..$FF:
          Result := Result + EscapeRTF(GetTokenText(B));
      end;
      Continue;
    end;

    // Number markers - skip 5 bytes
    if (B = $0E) or (B = $7E) then
    begin
      if Pos + 5 <= EndPos then
        Inc(Pos, 5)
      else
        Pos := EndPos;
      Continue;
    end;

    // String toggle on quote character
    if B = $22 then
    begin
      if not InString then
      begin
        InString := True;
        Result := Result + '{\cf3 "';
      end
      else
      begin
        InString := False;
        Result := Result + '"}';
      end;
      LastWasSpace := False;
      Continue;
    end;

    // Inside a string - everything is red
    if InString then
    begin
      case B of
        $20..$7D, $7F:
          if B = $7F then
            Result := Result + EscapeRTF(GetSpecialChar(B))
          else
            Result := Result + EscapeRTF(Chr(B));
        $80..$A2:
          Result := Result + EscapeRTF(GetSpecialChar(B));
      end;
      Continue;
    end;

    // Keywords
    if B in [$A3..$FF] then
    begin
      TokenText := GetTokenText(B);
      if not LastWasSpace then
        Result := Result + ' ';

      // REM keyword - emit keyword then switch to comment mode
      if B = $EA then
      begin
        Result := Result + '{\cf2\b ' + EscapeRTF(TokenText) + ' }{\cf4 ';
        InREM := True;
      end
      else
        Result := Result + '{\cf2\b ' + EscapeRTF(TokenText) + ' }';

      LastWasSpace := True;
      Continue;
    end;

    // Regular printable ASCII
    if (B >= $20) and (B <= $7D) then
    begin
      Result := Result + EscapeRTF(Chr(B));
      LastWasSpace := (B = $20);
      Continue;
    end;

    if B = $7F then
    begin
      Result := Result + EscapeRTF(GetSpecialChar(B));
      LastWasSpace := False;
      Continue;
    end;

    // Extended characters
    if (B >= $80) and (B <= $A2) then
    begin
      Result := Result + EscapeRTF(GetSpecialChar(B));
      LastWasSpace := False;
      Continue;
    end;
  end;

  // Close any open groups
  if InString then
    Result := Result + '}';
  if InREM then
    Result := Result + '}';
end;

function TSinclairBasicParser.DecodeRTF(const Data: array of byte): string;
const
  RTFHeader = '{\rtf1\ansi\deff0' +
    '{\fonttbl{\f0\fmodern Consolas;}}' +
    '{\colortbl;\red128\green128\blue128;\red0\green0\blue170;\red170\green0\blue0;\red0\green128\blue0;\red0\green0\blue0;}' +
    '\f0\fs26 ';
var
  Pos, DataLen: integer;
  LineNum: word;
  LineLen: word;
  LineRTF: string;
  FirstLine: boolean;
begin
  Result := RTFHeader;
  Pos := 0;
  DataLen := System.Length(Data);
  FirstLine := True;

  while Pos < DataLen do
  begin
    if Pos + 4 > DataLen then
      Break;

    LineNum := (word(Data[Pos]) shl 8) or word(Data[Pos + 1]);
    Inc(Pos, 2);

    if LineNum > 9999 then
      Break;

    LineLen := word(Data[Pos]) or (word(Data[Pos + 1]) shl 8);
    Inc(Pos, 2);

    if LineLen < 1 then
      Break;

    if not FirstLine then
      Result := Result + '\par ';
    FirstLine := False;

    LineRTF := DecodeLineRTF(Data, Pos, LineLen);
    Result := Result + '{\cf1 ' + IntToStr(LineNum) + '} ' + LineRTF;

    Inc(Pos, LineLen);
  end;

  Result := Result + '}';
end;

function TSinclairBasicParser.DecodeFileRTF(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
var
  FileData: TDiskByteArray;
  BasicData: TDiskByteArray;
  ProgLength: word;
begin
  Result := '';

  if (DiskFile.HeaderType <> 'PLUS3DOS') or
     (not DiskFile.Meta.StartsWith('BASIC')) then
    Exit;

  FileData := DiskFile.GetData(True);
  if System.Length(FileData) < 128 then
    Exit;

  ProgLength := word(FileData[20]) or (word(FileData[21]) shl 8);
  if ProgLength = 0 then
    Exit;
  if ProgLength > System.Length(FileData) - 128 then
    ProgLength := System.Length(FileData) - 128;

  BasicData := Copy(FileData, 128, ProgLength);
  Result := DecodeRTF(BasicData);
end;

// Decode a single byte of a saved character (string) array element. Unlike a
// tokenised BASIC line there are no number markers, so every byte is a literal
// character: printable ASCII, a Spectrum special/extended character, or a
// keyword token.
function TSinclairBasicParser.DecodeArrayChar(B: byte): string;
begin
  case B of
    $20..$7E: Result := Chr(B);
    $7F..$A2: Result := GetSpecialChar(B);
    $A3..$FF: Result := GetTokenText(B);
  else
    Result := '';  // control characters
  end;
end;

// Parse the dimension table at the start of a saved character array. The data
// is [dimension count][dim 1 lo/hi]..[dim K lo/hi][elements]. The final
// dimension is the length of each string; the product of the earlier
// dimensions is the number of strings. Returns False if the header is invalid.
function TSinclairBasicParser.ParseStringArrayHeader(const Data: array of byte;
  out StartPos, StringLen, NumStrings: integer): boolean;
var
  DataLen, Pos, DimCount, I: integer;
  DimSize, TotalElems: int64;
begin
  Result := False;
  StartPos := 0;
  StringLen := 0;
  NumStrings := 0;

  DataLen := System.Length(Data);
  if DataLen < 1 then
    Exit;

  DimCount := Data[0];
  if DimCount < 1 then
    Exit;

  // Need one byte per count plus two bytes per dimension size
  if 1 + (DimCount * 2) > DataLen then
    Exit;

  Pos := 1;
  TotalElems := 1;
  for I := 0 to DimCount - 1 do
  begin
    DimSize := Data[Pos] or (word(Data[Pos + 1]) shl 8);
    Inc(Pos, 2);
    TotalElems := TotalElems * DimSize;
    StringLen := DimSize;  // last dimension wins = string length
  end;

  if StringLen < 1 then
    Exit;

  StartPos := Pos;
  NumStrings := TotalElems div StringLen;
  Result := True;
end;

// Decode a saved character array to plain text, one array item (string) per
// line with trailing space padding removed. Data is the file contents with the
// 128-byte PLUS3DOS header already stripped.
function TSinclairBasicParser.DecodeStringArray(const Data: array of byte): string;
var
  StartPos, StringLen, NumStrings, ItemIdx, I, Pos: integer;
  Item: string;
begin
  Result := '';
  if not ParseStringArrayHeader(Data, StartPos, StringLen, NumStrings) then
    Exit;

  Pos := StartPos;
  for ItemIdx := 0 to NumStrings - 1 do
  begin
    Item := '';
    for I := 0 to StringLen - 1 do
    begin
      if Pos >= System.Length(Data) then
        Break;
      Item := Item + DecodeArrayChar(Data[Pos]);
      Inc(Pos);
    end;
    Result := Result + TrimRight(Item) + #13#10;
  end;
end;

// Decode a saved character array to RTF for the file viewer, one array item
// (string) per line.
function TSinclairBasicParser.DecodeStringArrayRTF(const Data: array of byte): string;
const
  RTFHeader = '{\rtf1\ansi\deff0' +
    '{\fonttbl{\f0\fmodern Consolas;}}' +
    '\f0\fs26 ';
var
  StartPos, StringLen, NumStrings, ItemIdx, I, Pos: integer;
  Item: string;
begin
  Result := '';
  if not ParseStringArrayHeader(Data, StartPos, StringLen, NumStrings) then
    Exit;

  Result := RTFHeader;
  Pos := StartPos;
  for ItemIdx := 0 to NumStrings - 1 do
  begin
    if ItemIdx > 0 then
      Result := Result + '\par ';
    Item := '';
    for I := 0 to StringLen - 1 do
    begin
      if Pos >= System.Length(Data) then
        Break;
      Item := Item + DecodeArrayChar(Data[Pos]);
      Inc(Pos);
    end;
    Result := Result + EscapeRTF(TrimRight(Item));
  end;
  Result := Result + '}';
end;

function TSinclairBasicParser.DecodeStringArrayFileRTF(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
var
  FileData, ArrayData: TDiskByteArray;
begin
  Result := '';

  if DiskFile.HeaderType <> 'PLUS3DOS' then
    Exit;

  FileData := DiskFile.GetData(True);
  if System.Length(FileData) < 128 then
    Exit;

  ArrayData := Copy(FileData, 128, System.Length(FileData) - 128);
  Result := DecodeStringArrayRTF(ArrayData);
end;

end.
