unit TeleDisk;

{$MODE Delphi}

{
  Disk Image Manager -  Teledisk (.td0) file structures

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

  A Teledisk image is a 12-byte header, then (LZHUF-compressed when the
  signature is 'td') an optional comment block and one record per track, each a
  header followed by its sectors, until a track header whose sector count is
  $FF. Every part carries a CRC-16 (polynomial $A097, MSB first, seed 0): all of
  it for the header and comment, the low byte for a track header and for the
  decoded data of a sector.
}

interface

uses
  Classes, SysUtils;

const
  TD0SignatureNormal = 'TD';
  TD0SignatureAdvanced = 'td';

  // Teledisk stores its version as major * 10 + minor. Advanced compression
  // before 2.0 was a different scheme, which is not supported.
  TD0VersionWritten = 21;
  TD0VersionLZHuf = 20;

  // Header data rate
  TD0Rate250 = 0;
  TD0Rate300 = 1;
  TD0Rate500 = 2;
  TD0RateMask = $03;
  TD0RateFM = $80;          // the whole disk is FM

  TD0StepMask = $03;        // 0 single, 1 double, 2 even-only
  TD0StepHasComment = $80;

  TD0HeadFM = $80;          // in a track header: this track is FM
  TD0EndOfImage = $FF;      // a track header sector count

  // Sector header flags
  TD0FlagDuplicate = $01;
  TD0FlagCRCError = $02;
  TD0FlagDeleted = $04;
  TD0FlagSkipped = $10;     // not dumped, as DOS had not allocated it
  TD0FlagNoData = $20;      // an ID with no data field
  TD0FlagNoID = $40;        // a data field with no ID
  TD0FlagsWithoutData = TD0FlagSkipped or TD0FlagNoData;

  // Sector data encodings
  TD0EncodingRaw = 0;
  TD0EncodingRepeat = 1;    // a count of words and the word to repeat
  TD0EncodingRLE = 2;       // literal runs and repeated patterns

  TD0MaxSizeCode = 8;       // the largest sector size DIM holds

type
  TTD0Header = packed record
    Signature: array[0..1] of char;
    Sequence: byte;         // volume within a multi-volume set
    CheckSig: byte;
    Version: byte;
    DataRate: byte;
    DriveType: byte;
    Stepping: byte;
    DOSAlloc: byte;
    Sides: byte;
    CRC: word;              // of the ten bytes before it
  end;

  TTD0CommentHeader = packed record
    CRC: word;              // of the rest of this and the text after it
    Length: word;
    Year: byte;             // years since 1900
    Month: byte;            // 0 = January
    Day: byte;
    Hour: byte;
    Minute: byte;
    Second: byte;
  end;

  TTD0TrackHeader = packed record
    Sectors: byte;
    Cylinder: byte;
    Head: byte;
    CRC: byte;              // low byte of the CRC of the three before it
  end;

  TTD0SectorHeader = packed record
    Cylinder: byte;
    Head: byte;
    ID: byte;
    Size: byte;
    Flags: byte;
    CRC: byte;              // low byte of the CRC of the decoded data
  end;

function TD0Crc(const Buf; Len: integer; Seed: word = 0): word;

// True when Header opens with a Teledisk signature and its CRC is right. Two
// letters alone are too little to go on for a file with no extension check.
function IsTD0Header(const Header: TTD0Header): boolean;

// Expand a sector's stored data field (the bytes after its encoding byte) into
// Dest, which holds Size bytes. Anything the encoding leaves short is filled
// with Filler. False when the field is malformed or the encoding unknown.
function DecodeTD0SectorData(const Src: array of byte; Encoding: byte;
  var Dest: array of byte; Size: integer; Filler: byte): boolean;

// Store Size bytes of Data as a sector data field: the length word, the
// encoding byte and the encoded bytes, written to Stream.
procedure EncodeTD0SectorData(Stream: TStream; const Data: array of byte; Size: integer);

implementation

function TD0Crc(const Buf; Len: integer; Seed: word): word;
var
  P: PByte;
  I, Bit: integer;
begin
  Result := Seed;
  P := @Buf;
  for I := 0 to Len - 1 do
  begin
    Result := Result xor (word(P[I]) shl 8);
    for Bit := 0 to 7 do
      if (Result and $8000) <> 0 then
        Result := word((Result shl 1) xor $A097)
      else
        Result := word(Result shl 1);
  end;
end;

function IsTD0Header(const Header: TTD0Header): boolean;
begin
  Result := ((Header.Signature = TD0SignatureNormal) or (Header.Signature = TD0SignatureAdvanced)) and
    (TD0Crc(Header, 10) = Header.CRC);
end;

function DecodeTD0SectorData(const Src: array of byte; Encoding: byte;
  var Dest: array of byte; Size: integer; Filler: byte): boolean;
var
  SIdx, DIdx, Count, Width, Rep, Idx: integer;
  Kind: byte;
begin
  Result := False;
  FillChar(Dest[0], Size, Filler);
  DIdx := 0;

  case Encoding of
    TD0EncodingRaw:
    begin
      Count := Length(Src);
      if Count > Size then Count := Size;
      if Count > 0 then
        Move(Src[0], Dest[0], Count);
    end;

    TD0EncodingRepeat:
    begin
      if Length(Src) < 4 then exit;
      Count := Src[0] or (Src[1] shl 8);
      for Rep := 1 to Count do
      begin
        if DIdx < Size then Dest[DIdx] := Src[2];
        if DIdx + 1 < Size then Dest[DIdx + 1] := Src[3];
        Inc(DIdx, 2);
      end;
    end;

    TD0EncodingRLE:
    begin
      SIdx := 0;
      while (SIdx < Length(Src)) and (DIdx < Size) do
      begin
        if SIdx + 1 >= Length(Src) then exit;
        Kind := Src[SIdx];
        Count := Src[SIdx + 1];
        Inc(SIdx, 2);
        if Kind = 0 then
        begin
          // A literal run
          if SIdx + Count > Length(Src) then exit;
          for Idx := 0 to Count - 1 do
          begin
            if DIdx < Size then Dest[DIdx] := Src[SIdx + Idx];
            Inc(DIdx);
          end;
          Inc(SIdx, Count);
        end
        else
        begin
          // A pattern of Kind words, repeated Count times
          Width := Kind * 2;
          if SIdx + Width > Length(Src) then exit;
          for Rep := 1 to Count do
            for Idx := 0 to Width - 1 do
            begin
              if DIdx < Size then Dest[DIdx] := Src[SIdx + Idx];
              Inc(DIdx);
            end;
          Inc(SIdx, Width);
        end;
      end;
    end;

    else
      exit;
  end;

  Result := True;
end;

procedure EncodeTD0SectorData(Stream: TStream; const Data: array of byte; Size: integer);
var
  Idx: integer;
  Uniform: boolean;
begin
  // A sector of one repeated word is four bytes whatever its size, which is
  // most of a freshly formatted disk. Anything else goes as it is and is left
  // to the compression to squeeze.
  Uniform := (Size >= 2) and (Size mod 2 = 0);
  if Uniform then
    for Idx := 2 to Size - 1 do
      if Data[Idx] <> Data[Idx - 2] then
      begin
        Uniform := False;
        break;
      end;

  if Uniform then
  begin
    Stream.WriteWord(NtoLE(word(5)));
    Stream.WriteByte(TD0EncodingRepeat);
    Stream.WriteWord(NtoLE(word(Size div 2)));
    Stream.WriteByte(Data[0]);
    Stream.WriteByte(Data[1]);
  end
  else
  begin
    Stream.WriteWord(NtoLE(word(Size + 1)));
    Stream.WriteByte(TD0EncodingRaw);
    if Size > 0 then
      Stream.WriteBuffer(Data[0], Size);
  end;
end;

end.
