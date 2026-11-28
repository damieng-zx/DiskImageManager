unit TapeImage;

{$MODE Delphi}

{
  Disk Image Manager - Spectrum tape images (.tap)

  A tape image is a run of blocks, each its length (two bytes, little endian),
  a flag byte, the block's bytes and a checksum: the exclusive or of the flag
  and the bytes. A file is two blocks. The first, flagged 0, is a 17-byte
  header: type, ten character name, data length and two parameters. The second,
  flagged $FF, is the data.

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DskImage, Classes;

const
  TapeHeaderSize = 17;
  // A block's length is sixteen bits and counts its flag and checksum
  MaxTapeData = $FFFF - 2;

// The file as a tape holds it, or False for one that a tape cannot hold
function CanSaveToTape(DiskFile: TDiskFile; out Tape: TTapeFile): boolean;

// Write a file's header block and data block
procedure WriteTapeFile(Stream: TStream; const Tape: TTapeFile);

implementation

const
  HeaderFlag = $00;
  DataFlag = $FF;

function CanSaveToTape(DiskFile: TDiskFile; out Tape: TTapeFile): boolean;
begin
  Result := DiskFile.GetTapeFile(Tape) and (Length(Tape.Data) <= MaxTapeData);
end;

procedure WriteBlock(Stream: TStream; Flag: byte; const Data: array of byte);
var
  Idx: integer;
  Checksum: byte;
begin
  Checksum := Flag;
  for Idx := 0 to High(Data) do
    Checksum := Checksum xor Data[Idx];

  Stream.WriteWord(NtoLE(word(Length(Data) + 2)));
  Stream.WriteByte(Flag);
  if Length(Data) > 0 then
    Stream.WriteBuffer(Data[0], Length(Data));
  Stream.WriteByte(Checksum);
end;

procedure WriteTapeFile(Stream: TStream; const Tape: TTapeFile);
var
  Header: array[0..TapeHeaderSize - 1] of byte;

  procedure PutWord(Offset: integer; Value: word);
  begin
    Header[Offset] := Lo(Value);
    Header[Offset + 1] := Hi(Value);
  end;

begin
  Header[0] := Ord(Tape.FileType);
  Move(Tape.Name, Header[1], SizeOf(Tape.Name));
  PutWord(11, Length(Tape.Data));
  PutWord(13, Tape.Param1);
  PutWord(15, Tape.Param2);

  WriteBlock(Stream, HeaderFlag, Header);
  WriteBlock(Stream, DataFlag, Tape.Data);
end;

end.
