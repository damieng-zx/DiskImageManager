unit AmstradBasic;

{$MODE Delphi}

{
  Disk Image Manager - Amstrad (Locomotive) BASIC tokenized file decoder

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DskImage, FileSystem, Utils, SysUtils, Math;

type
  TAmstradBasicParser = class
  private
    FFormat: TFormatSettings;
    function GetTokenText(Token: byte): string;
    function GetFunctionText(Token: byte): string;
    function ReadVarName(const Data: array of byte; var Pos: integer; EndPos: integer): string;
    function VarSuffix(Token: byte): string;
    function FormatFloat(const Data: array of byte; Pos: integer): string;
    function FormatBinary(Value: word): string;
    function DecodeLine(const Data: array of byte; StartPos, EndPos: integer): string;
    function DecodeLineRTF(const Data: array of byte; StartPos, EndPos: integer): string;
    function EscapeRTF(const S: string): string;
    function DeprotectData(const Data: array of byte): TDiskByteArray;
  public
    constructor Create;
    function Decode(const Data: array of byte; IsProtected: boolean = False): string;
    function DecodeFile(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
    function DecodeRTF(const Data: array of byte; IsProtected: boolean = False): string;
    function DecodeFileRTF(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
  end;

implementation

const
  // Single-byte keyword tokens. Empty entries are unused codes.
  Tokens: array[$80..$FF] of string = (
    'AFTER', 'AUTO', 'BORDER', 'CALL', 'CAT', 'CHAIN', 'CLEAR', 'CLG',         // 80-87
    'CLOSEIN', 'CLOSEOUT', 'CLS', 'CONT', 'DATA', 'DEF', 'DEFINT', 'DEFREAL',  // 88-8F
    'DEFSTR', 'DEG', 'DELETE', 'DIM', 'DRAW', 'DRAWR', 'EDIT', 'ELSE',         // 90-97
    'END', 'ENT', 'ENV', 'ERASE', 'ERROR', 'EVERY', 'FOR', 'GOSUB',           // 98-9F
    'GOTO', 'IF', 'INK', 'INPUT', 'KEY', 'LET', 'LINE', 'LIST',               // A0-A7
    'LOAD', 'LOCATE', 'MEMORY', 'MERGE', 'MID$', 'MODE', 'MOVE', 'MOVER',     // A8-AF
    'NEXT', 'NEW', 'ON', 'ON BREAK', 'ON ERROR GOTO', 'ON SQ', 'OPENIN',      // B0-B6
    'OPENOUT', 'ORIGIN', 'OUT', 'PAPER', 'PEN', 'PLOT', 'PLOTR', 'POKE',      // B7-BE
    'PRINT', '''', 'RAD', 'RANDOMIZE', 'READ', 'RELEASE', 'REM', 'RENUM',     // BF-C6
    'RESTORE', 'RESUME', 'RETURN', 'RUN', 'SAVE', 'SOUND', 'SPEED', 'STOP',   // C7-CE
    'SYMBOL', 'TAG', 'TAGOFF', 'TROFF', 'TRON', 'WAIT', 'WEND', 'WHILE',      // CF-D6
    'WIDTH', 'WINDOW', 'WRITE', 'ZONE', 'DI', 'EI', 'FILL', 'GRAPHICS',       // D7-DE
    'MASK', 'FRAME', 'CURSOR', '', 'ERL', 'FN', 'SPC', 'STEP',                // DF-E6
    'SWAP', '', '', 'TAB', 'THEN', 'TO', 'USING', '>',                        // E7-EE
    '=', '>=', '<', '<>', '<=', '+', '-', '*',                                // EF-F6
    '/', '^', '\', 'AND', 'MOD', 'OR', 'XOR', 'NOT',                          // F7-FE
    ''                                                                         // FF (prefix)
  );

  // AMSDOS protected BASIC uses a repeating 128-byte XOR stream.
  ProtectedBasicKey: array[0..127] of byte = (
    $AB, $2C, $ED, $EA, $6C, $37, $3F, $EC, $9B, $DF, $7A, $0C, $3B, $D4, $6D, $F5,
    $04, $44, $03, $11, $DF, $59, $8F, $21, $73, $7A, $CC, $83, $DD, $30, $6A, $30,
    $D3, $8F, $02, $F0, $60, $6B, $94, $E4, $B7, $F3, $03, $A8, $60, $88, $F0, $43,
    $E8, $8E, $43, $A0, $CA, $84, $31, $53, $F3, $1F, $C9, $E8, $AD, $C0, $BA, $6D,
    $93, $08, $D4, $6A, $2C, $B2, $07, $27, $C0, $99, $EE, $89, $AF, $C3, $53, $AB,
    $2B, $34, $5C, $2F, $13, $EE, $AA, $2C, $D9, $F4, $BC, $12, $B3, $C5, $1C, $68,
    $01, $20, $2C, $FA, $77, $A6, $B5, $A4, $FC, $9B, $F1, $32, $5B, $C3, $70, $77,
    $85, $36, $BE, $5B, $8C, $C8, $B5, $C2, $F0, $0B, $98, $0F, $36, $9D, $D8, $96
  );

constructor TAmstradBasicParser.Create;
begin
  inherited Create;
  FFormat := DefaultFormatSettings;
  FFormat.DecimalSeparator := '.';
  FFormat.ThousandSeparator := #0;
end;

function TAmstradBasicParser.DeprotectData(const Data: array of byte): TDiskByteArray;
var
  I: integer;
begin
  SetLength(Result, System.Length(Data));
  for I := 0 to High(Result) do
    Result[I] := Data[I] xor ProtectedBasicKey[I and $7F];
end;

function TAmstradBasicParser.GetTokenText(Token: byte): string;
begin
  Result := Tokens[Token];
  if Result = '' then
    Result := Format('?%02X?', [Token]);
end;

function TAmstradBasicParser.GetFunctionText(Token: byte): string;
begin
  case Token of
    $00: Result := 'ABS';
    $01: Result := 'ASC';
    $02: Result := 'ATN';
    $03: Result := 'CHR$';
    $04: Result := 'CINT';
    $05: Result := 'COS';
    $06: Result := 'CREAL';
    $07: Result := 'EXP';
    $08: Result := 'FIX';
    $09: Result := 'FRE';
    $0A: Result := 'INKEY';
    $0B: Result := 'INP';
    $0C: Result := 'INT';
    $0D: Result := 'JOY';
    $0E: Result := 'LEN';
    $0F: Result := 'LOG';
    $10: Result := 'LOG10';
    $11: Result := 'LOWER$';
    $12: Result := 'PEEK';
    $13: Result := 'REMAIN';
    $14: Result := 'SGN';
    $15: Result := 'SIN';
    $16: Result := 'SPACE$';
    $17: Result := 'SQ';
    $18: Result := 'SQR';
    $19: Result := 'STR$';
    $1A: Result := 'TAN';
    $1B: Result := 'UNT';
    $1C: Result := 'UPPER$';
    $1D: Result := 'VAL';
    $40: Result := 'EOF';
    $41: Result := 'ERR';
    $42: Result := 'HIMEM';
    $43: Result := 'INKEY$';
    $44: Result := 'PI';
    $45: Result := 'RND';
    $46: Result := 'TIME';
    $47: Result := 'XPOS';
    $48: Result := 'YPOS';
    $49: Result := 'DERR';
    $71: Result := 'BIN$';
    $72: Result := 'DEC$';
    $73: Result := 'HEX$';
    $74: Result := 'INSTR';
    $75: Result := 'LEFT$';
    $76: Result := 'MAX';
    $77: Result := 'MIN';
    $78: Result := 'POS';
    $79: Result := 'RIGHT$';
    $7A: Result := 'ROUND';
    $7B: Result := 'STRING$';
    $7C: Result := 'TEST';
    $7D: Result := 'TESTR';
    $7E: Result := 'COPYCHR$';
    $7F: Result := 'VPOS';
  else
    Result := Format('?FF%02X?', [Token]);
  end;
end;

function TAmstradBasicParser.VarSuffix(Token: byte): string;
begin
  case Token of
    $02: Result := '%';  // integer
    $03: Result := '$';  // string
    $04: Result := '!';  // real
  else
    Result := '';        // $0B/$0C/$0D - no suffix (type set by DEFINT/DEFSTR/DEFREAL)
  end;
end;

// Reads a variable reference: a 2-byte offset (ignored) followed by the
// variable name in ASCII, where bit 7 of the final character is set.
function TAmstradBasicParser.ReadVarName(const Data: array of byte; var Pos: integer; EndPos: integer): string;
var
  B: byte;
begin
  Result := '';

  // Skip the 2-byte offset to the variable's value area
  if Pos + 2 <= EndPos then
    Inc(Pos, 2)
  else
  begin
    Pos := EndPos;
    Exit;
  end;

  while Pos < EndPos do
  begin
    if Pos >= System.Length(Data) then
      Break;
    B := Data[Pos];
    Inc(Pos);
    Result := Result + Chr(B and $7F);
    if (B and $80) <> 0 then
      Break;  // bit 7 marks the last character
  end;
end;

// Decodes the 5-byte Locomotive BASIC floating point format:
//   bytes 0-2: mantissa bits 7-0, 15-8, 23-16
//   byte 3:    bit 7 = sign, bits 6-0 = mantissa bits 30-24
//   byte 4:    exponent, biased by 128 (0 = the value is zero)
// value = (mantissa / 2^32) * 2^(exponent - 128), implicit mantissa bit 31 set.
function TAmstradBasicParser.FormatFloat(const Data: array of byte; Pos: integer): string;
var
  Exponent: integer;
  IsNegative: boolean;
  Mantissa: cardinal;
  Value: double;
begin
  Exponent := Data[Pos + 4];
  if Exponent = 0 then
  begin
    Result := '0';
    Exit;
  end;

  IsNegative := (Data[Pos + 3] and $80) <> 0;
  Mantissa := $80000000 or
              (cardinal(Data[Pos + 3] and $7F) shl 24) or
              (cardinal(Data[Pos + 2]) shl 16) or
              (cardinal(Data[Pos + 1]) shl 8) or
              cardinal(Data[Pos]);

  Value := (Mantissa / 4294967296.0) * Power(2.0, Exponent - 128);  // 2^32
  if IsNegative then
    Value := -Value;

  Result := FloatToStrF(Value, ffGeneral, 9, 0, FFormat);
end;

function TAmstradBasicParser.FormatBinary(Value: word): string;
var
  I: integer;
  Started: boolean;
begin
  Result := '';
  Started := False;
  for I := 15 downto 0 do
    if (Value and (1 shl I)) <> 0 then
    begin
      Result := Result + '1';
      Started := True;
    end
    else if Started then
      Result := Result + '0';
  if Result = '' then
    Result := '0';
end;

function TAmstradBasicParser.DecodeLine(const Data: array of byte; StartPos, EndPos: integer): string;
var
  Pos: integer;
  B: byte;
  InString, InREM: boolean;
  Value: word;
begin
  Result := '';
  Pos := StartPos;
  InString := False;
  InREM := False;

  while Pos < EndPos do
  begin
    if Pos >= System.Length(Data) then
      Break;

    B := Data[Pos];
    Inc(Pos);

    if B = $00 then
      Break;  // end of line

    // Comment text after REM / ' runs to the end of the line untokenised
    if InREM then
    begin
      if (B >= $20) and (B <= $7E) then
        Result := Result + Chr(B);
      Continue;
    end;

    // Inside a quoted string everything is literal until the closing quote
    if InString then
    begin
      if B = $22 then
      begin
        InString := False;
        Result := Result + '"';
      end
      else if (B >= $20) and (B <= $7E) then
        Result := Result + Chr(B);
      Continue;
    end;

    case B of
      $01:
        // Statement separator ':' - suppressed before the hidden colon of ' and ELSE
        if (Pos < EndPos) and ((Data[Pos] = $C0) or (Data[Pos] = $97)) then
          // skip
        else
          Result := Result + ':';

      $02, $03, $04, $0B, $0C, $0D:
        Result := Result + ReadVarName(Data, Pos, EndPos) + VarSuffix(B);

      $0E..$17:
        Result := Result + IntToStr(B - $0E);  // single digit constant 0-9

      $18:
        Result := Result + '10';

      $19:  // 8-bit integer
        if Pos < EndPos then
        begin
          Result := Result + IntToStr(Data[Pos]);
          Inc(Pos);
        end;

      $1A:  // 16-bit integer
        if Pos + 1 < EndPos then
        begin
          Result := Result + IntToStr(ReadWordLE(Data, Pos));
          Inc(Pos, 2);
        end;

      $1B:  // 16-bit binary
        if Pos + 1 < EndPos then
        begin
          Value := ReadWordLE(Data, Pos);
          Result := Result + '&X' + FormatBinary(Value);
          Inc(Pos, 2);
        end;

      $1C:  // 16-bit hexadecimal
        if Pos + 1 < EndPos then
        begin
          Value := ReadWordLE(Data, Pos);
          Result := Result + '&' + Format('%X', [Value]);
          Inc(Pos, 2);
        end;

      $1D:  // line address pointer - skip
        Inc(Pos, 2);

      $1E:  // line number
        if Pos + 1 < EndPos then
        begin
          Result := Result + IntToStr(ReadWordLE(Data, Pos));
          Inc(Pos, 2);
        end;

      $1F:  // floating point constant
        if Pos + 4 < EndPos then
        begin
          Result := Result + FormatFloat(Data, Pos);
          Inc(Pos, 5);
        end;

      $22:  // open quote
        begin
          InString := True;
          Result := Result + '"';
        end;

      $20..$21, $23..$7E:  // literal printable ASCII
        Result := Result + Chr(B);

      $C0, $C5:  // ' and REM - emit keyword then switch to comment mode
        begin
          Result := Result + GetTokenText(B);
          InREM := True;
        end;

      $FF:  // function token prefix
        if Pos < EndPos then
        begin
          Result := Result + GetFunctionText(Data[Pos]);
          Inc(Pos);
        end;

      $80..$BF, $C1..$C4, $C6..$FE:  // keyword token (C0/C5 handled above)
        Result := Result + GetTokenText(B);

      // other control characters - ignore
    end;
  end;
end;

function TAmstradBasicParser.Decode(const Data: array of byte; IsProtected: boolean): string;
var
  DecodedData: TDiskByteArray;
  Pos, DataLen, LineEnd: integer;
  LineNum, LineLen: word;
begin
  if IsProtected then
  begin
    DecodedData := DeprotectData(Data);
    Exit(Decode(DecodedData));
  end;
  Result := '';
  Pos := 0;
  DataLen := System.Length(Data);

  while Pos + 4 <= DataLen do
  begin
    LineLen := ReadWordLE(Data, Pos);
    if LineLen = 0 then
      Break;  // end of program
    if LineLen < 4 then
      Break;  // malformed

    LineNum := ReadWordLE(Data, Pos + 2);
    LineEnd := Pos + LineLen;
    if LineEnd > DataLen then
      LineEnd := DataLen;

    Result := Result + Format('%d %s'#13#10,
      [LineNum, DecodeLine(Data, Pos + 4, LineEnd)]);

    Pos := Pos + LineLen;
  end;
end;

function TAmstradBasicParser.DecodeFile(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
var
  FileData, BasicData: TDiskByteArray;
  ProgLength: integer;
begin
  Result := '';

  if (DiskFile.HeaderType <> 'AMSDOS') or
     not ((DiskFile.Meta = 'BASIC') or (DiskFile.Meta = 'BASIC (protected)')) then
    Exit;

  FileData := DiskFile.GetData(True);
  if System.Length(FileData) <= 128 then
    Exit;

  ProgLength := DiskFile.Size;
  if (ProgLength <= 0) or (ProgLength > System.Length(FileData) - 128) then
    ProgLength := System.Length(FileData) - 128;

  BasicData := Copy(FileData, 128, ProgLength);
  Result := Decode(BasicData, DiskFile.Meta = 'BASIC (protected)');
end;

function TAmstradBasicParser.EscapeRTF(const S: string): string;
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

function TAmstradBasicParser.DecodeLineRTF(const Data: array of byte; StartPos, EndPos: integer): string;
var
  Pos: integer;
  B: byte;
  InString, InREM: boolean;
  TokenText: string;
  Value: word;

  procedure EmitKeyword(const Text: string);
  begin
    // Colour alphabetic keywords; leave operators in the default colour
    if (Text <> '') and (Text[1] in ['A'..'Z']) then
      Result := Result + '{\cf2\b ' + EscapeRTF(Text) + '}'
    else
      Result := Result + EscapeRTF(Text);
  end;

begin
  Result := '';
  Pos := StartPos;
  InString := False;
  InREM := False;

  while Pos < EndPos do
  begin
    if Pos >= System.Length(Data) then
      Break;

    B := Data[Pos];
    Inc(Pos);

    if B = $00 then
      Break;

    if InREM then
    begin
      if (B >= $20) and (B <= $7E) then
        Result := Result + EscapeRTF(Chr(B));
      Continue;
    end;

    if InString then
    begin
      if B = $22 then
      begin
        InString := False;
        Result := Result + '"}';
      end
      else if (B >= $20) and (B <= $7E) then
        Result := Result + EscapeRTF(Chr(B));
      Continue;
    end;

    case B of
      $01:
        if (Pos < EndPos) and ((Data[Pos] = $C0) or (Data[Pos] = $97)) then
          // suppress hidden colon
        else
          Result := Result + ':';

      $02, $03, $04, $0B, $0C, $0D:
        Result := Result + EscapeRTF(ReadVarName(Data, Pos, EndPos) + VarSuffix(B));

      $0E..$17:
        Result := Result + IntToStr(B - $0E);

      $18:
        Result := Result + '10';

      $19:
        if Pos < EndPos then
        begin
          Result := Result + IntToStr(Data[Pos]);
          Inc(Pos);
        end;

      $1A:
        if Pos + 1 < EndPos then
        begin
          Result := Result + IntToStr(ReadWordLE(Data, Pos));
          Inc(Pos, 2);
        end;

      $1B:
        if Pos + 1 < EndPos then
        begin
          Value := ReadWordLE(Data, Pos);
          Result := Result + '&X' + FormatBinary(Value);
          Inc(Pos, 2);
        end;

      $1C:
        if Pos + 1 < EndPos then
        begin
          Value := ReadWordLE(Data, Pos);
          Result := Result + '&' + Format('%X', [Value]);
          Inc(Pos, 2);
        end;

      $1D:
        Inc(Pos, 2);

      $1E:
        if Pos + 1 < EndPos then
        begin
          Result := Result + IntToStr(ReadWordLE(Data, Pos));
          Inc(Pos, 2);
        end;

      $1F:
        if Pos + 4 < EndPos then
        begin
          Result := Result + EscapeRTF(FormatFloat(Data, Pos));
          Inc(Pos, 5);
        end;

      $22:
        begin
          InString := True;
          Result := Result + '{\cf3 "';
        end;

      $20..$21, $23..$7E:
        Result := Result + EscapeRTF(Chr(B));

      $C0, $C5:
        begin
          TokenText := GetTokenText(B);
          Result := Result + '{\cf2\b ' + EscapeRTF(TokenText) + '}{\cf4 ';
          InREM := True;
        end;

      $FF:
        if Pos < EndPos then
        begin
          EmitKeyword(GetFunctionText(Data[Pos]));
          Inc(Pos);
        end;

      $80..$BF, $C1..$C4, $C6..$FE:  // C0/C5 handled above
        EmitKeyword(GetTokenText(B));
    end;
  end;

  // Close any open groups
  if InString then
    Result := Result + '"}';
  if InREM then
    Result := Result + '}';
end;

function TAmstradBasicParser.DecodeRTF(const Data: array of byte; IsProtected: boolean): string;
const
  RTFHeader = '{\rtf1\ansi\deff0' +
    '{\fonttbl{\f0\fmodern Consolas;}}' +
    '{\colortbl;\red128\green128\blue128;\red0\green0\blue170;\red170\green0\blue0;\red0\green128\blue0;\red0\green0\blue0;}' +
    '\f0\fs26 ';
var
  DecodedData: TDiskByteArray;
  Pos, DataLen, LineEnd: integer;
  LineNum, LineLen: word;
  FirstLine: boolean;
begin
  if IsProtected then
  begin
    DecodedData := DeprotectData(Data);
    Exit(DecodeRTF(DecodedData));
  end;
  Result := RTFHeader;
  Pos := 0;
  DataLen := System.Length(Data);
  FirstLine := True;

  while Pos + 4 <= DataLen do
  begin
    LineLen := ReadWordLE(Data, Pos);
    if LineLen = 0 then
      Break;
    if LineLen < 4 then
      Break;

    LineNum := ReadWordLE(Data, Pos + 2);
    LineEnd := Pos + LineLen;
    if LineEnd > DataLen then
      LineEnd := DataLen;

    if not FirstLine then
      Result := Result + '\par ';
    FirstLine := False;

    Result := Result + '{\cf1 ' + IntToStr(LineNum) + '} ' +
      DecodeLineRTF(Data, Pos + 4, LineEnd);

    Pos := Pos + LineLen;
  end;

  Result := Result + '}';
end;

function TAmstradBasicParser.DecodeFileRTF(DiskImage: TDSKDisk; DiskFile: TCPMFile): string;
var
  FileData, BasicData: TDiskByteArray;
  ProgLength: integer;
begin
  Result := '';

  if (DiskFile.HeaderType <> 'AMSDOS') or
     not ((DiskFile.Meta = 'BASIC') or (DiskFile.Meta = 'BASIC (protected)')) then
    Exit;

  FileData := DiskFile.GetData(True);
  if System.Length(FileData) <= 128 then
    Exit;

  ProgLength := DiskFile.Size;
  if (ProgLength <= 0) or (ProgLength > System.Length(FileData) - 128) then
    ProgLength := System.Length(FileData) - 128;

  BasicData := Copy(FileData, 128, ProgLength);
  Result := DecodeRTF(BasicData, DiskFile.Meta = 'BASIC (protected)');
end;

end.
