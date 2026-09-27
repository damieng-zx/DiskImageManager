unit DIMUtils;

{$MODE Delphi}

{
  Disk Image Manager - portable string and byte helpers

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Classes, SysUtils;

const
  MaxBlockShift = 8;

type
  TDiskByteArray = array of byte;
  TRGB = record
    R, G, B: byte;
  end;

function StrInt(I: integer): string;
function StrHex(I: integer): string;
function IntStr(S: string): integer;
function StrBlockClean(S: array of byte; Start, Len: integer): string;
function StrYesNo(IsEmpty: boolean): string;
function StrInByteArray(ByteArray: array of byte; SubString: string; Start: integer): boolean;
function StrBufPos(ByteArray: array of byte; SubString: string; MaxLen: integer = MaxInt): integer;
function ReadWordLE(const Data: array of byte; Offset: integer): word;
function ReadWordBE(const Data: array of byte; Offset: integer): word;
function Read24LE(const Data: array of byte; Offset: integer): longword;
function Read32LE(const Data: array of byte; Offset: integer): longword;
function CompareBlock(A: array of char; B: string): boolean;
function CompareBlockStart(A: array of char; B: string; Start: integer): boolean;
function CompareBlockInsensitive(A: array of char; B: string): boolean;
function BlockShiftToBlockSize(BlockShift: byte): integer;
function StrFileSize(Size: integer): string;
function SafeFileName(const Name: string; const Fallback: string = 'unnamed'): string;
function CompareByLength(List: TStringList; Index1, Index2: integer): integer;

implementation

function StrInt(I: integer): string;
begin
  Str(I, Result);
end;

function StrHex(I: integer): string;
begin
  Result := Format('%.2x', [I]);
end;

function IntStr(S: string): integer;
var
  Code: integer;
begin
  Val(S, Result, Code);
  if Code <> 0 then Result := 0;
end;

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

function StrYesNo(IsEmpty: boolean): string;
begin
  if IsEmpty then Result := 'Yes' else Result := 'No';
end;

function StrBufPos(ByteArray: array of byte; SubString: string; MaxLen: integer): integer;
var
  BIdx, SIdx, Last: integer;
begin
  Result := -1;
  if MaxLen < 0 then exit;
  Last := Length(ByteArray);
  if MaxLen < Last then Last := MaxLen;
  Last := Last - Length(SubString);

  for BIdx := 0 to Last do
  begin
    Result := BIdx;
    for SIdx := 1 to Length(SubString) do
      if ByteArray[BIdx + SIdx - 1] <> byte(SubString[SIdx]) then
      begin
        Result := -1;
        break;
      end;
    if Result <> -1 then break;
  end;
end;

function StrInByteArray(ByteArray: array of byte; SubString: string; Start: integer): boolean;
var
  Idx: integer;
begin
  if Length(SubString) = 0 then Exit(True);
  if (Start < 0) or (Start + Length(SubString) > Length(ByteArray)) then Exit(False);
  Result := True;
  for Idx := 0 to Length(SubString) - 1 do
    if ByteArray[Start + Idx] <> byte(SubString[Idx + 1]) then Exit(False);
end;

function ReadWordLE(const Data: array of byte; Offset: integer): word;
begin
  Result := Data[Offset] or (Data[Offset + 1] shl 8);
end;

function ReadWordBE(const Data: array of byte; Offset: integer): word;
begin
  Result := (Data[Offset] shl 8) or Data[Offset + 1];
end;

function Read24LE(const Data: array of byte; Offset: integer): longword;
begin
  Result := longword(Data[Offset]) or (longword(Data[Offset + 1]) shl 8) or
    (longword(Data[Offset + 2]) shl 16);
end;

function Read32LE(const Data: array of byte; Offset: integer): longword;
begin
  Result := longword(Data[Offset]) or (longword(Data[Offset + 1]) shl 8) or
    (longword(Data[Offset + 2]) shl 16) or (longword(Data[Offset + 3]) shl 24);
end;

function CompareBlock(A: array of char; B: string): boolean;
var
  Idx: integer;
begin
  Result := Length(B) <= Length(A);
  Idx := 0;
  while Result and (Idx < Length(B)) do
  begin
    if A[Idx] <> B[Idx + 1] then Result := False;
    Inc(Idx);
  end;
end;

function CompareBlockStart(A: array of char; B: string; Start: integer): boolean;
var
  Idx: integer;
begin
  Result := (Start >= 0) and (Start + Length(B) <= Length(A));
  Idx := 0;
  while Result and (Idx < Length(B)) do
  begin
    if A[Idx + Start] <> B[Idx + 1] then Result := False;
    Inc(Idx);
  end;
end;

function CompareBlockInsensitive(A: array of char; B: string): boolean;
var
  Idx: integer;
begin
  Result := Length(B) <= Length(A);
  Idx := 0;
  while Result and (Idx < Length(B)) do
  begin
    if UpCase(A[Idx]) <> UpCase(B[Idx + 1]) then Result := False;
    Inc(Idx);
  end;
end;

function BlockShiftToBlockSize(BlockShift: byte): integer;
begin
  if BlockShift > MaxBlockShift then BlockShift := MaxBlockShift;
  Result := 2 << (BlockShift + 6);
end;

function StrFileSize(Size: integer): string;
const
  Megabyte: integer = 1024 * 1024;
begin
  if Size < 1024 then
    Result := Format('%d bytes', [Size])
  else if Size < Megabyte then
    Result := Format('%d KB', [Size div 1024])
  else
    Result := Format('%d MB', [Size div Megabyte]);
end;

function SafeFileName(const Name: string; const Fallback: string): string;
const
  Illegal = '\/:*?"<>|';
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
    if (Ch < ' ') or (Pos(Ch, Illegal) > 0) then Ch := '_';
    Result := Result + Ch;
  end;
  while (Result <> '') and ((Result[Length(Result)] = '.') or (Result[Length(Result)] = ' ')) do
    SetLength(Result, Length(Result) - 1);
  while (Result <> '') and ((Result[1] = '.') or (Result[1] = ' ')) do
    Result := Copy(Result, 2, Length(Result) - 1);
  if Result = '' then
  begin
    Result := Fallback;
    exit;
  end;
  Stem := UpperCase(Result);
  Idx := Pos('.', Stem);
  if Idx > 0 then Stem := Copy(Stem, 1, Idx - 1);
  for Idx := Low(Devices) to High(Devices) do
    if Stem = Devices[Idx] then
    begin
      Result := '_' + Result;
      exit;
    end;
end;

function CompareByLength(List: TStringList; Index1, Index2: integer): integer;
begin
  Result := Length(List[Index2]) - Length(List[Index1]);
  if Result = 0 then Result := CompareText(List[Index1], List[Index2]);
end;

end.
