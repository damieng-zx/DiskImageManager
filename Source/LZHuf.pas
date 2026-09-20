unit LZHuf;

{$MODE Delphi}

{
  Disk Image Manager -  LZHUF compression

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

  Haruyasu Yoshizaki's LZHUF as Teledisk uses it for "advanced compression":
  LZSS over a 4K ring buffer, with literals and match lengths coded by an
  adaptive Huffman tree and the top six bits of each match position by a fixed
  prefix code. Teledisk drops LZHUF's own length header, so there is nothing to
  say where the output ends: decoding runs until the input does.
}

interface

uses
  Classes, SysUtils;

procedure LZHufDecompress(Src, Dest: TStream);
procedure LZHufCompress(Src, Dest: TStream);

implementation

const
  N = 4096;                              // ring buffer size
  F = 60;                                // longest match
  Threshold = 2;                         // matches this short are sent as literals
  NChar = 256 - Threshold + F;           // leaf symbols: literals then lengths
  T = NChar * 2 - 1;                     // nodes in the tree
  R = T - 1;                             // the root
  MaxFreq = $8000;                       // halve the counts when the root gets here
  Nil_ = N;                              // no node, in the match finder's tree

  // A corrupt stream can describe any amount of output, so stop well past
  // anything a disk could hold
  MaxDecompressed = 16 * 1024 * 1024;

  // Prefix code for the top six bits of a match position, left-aligned in a byte
  PLen: array[0..63] of byte = (
    3, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6,
    6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7,
    7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
    8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8);
  PCode: array[0..63] of byte = (
    $00, $20, $30, $40, $50, $58, $60, $68, $70, $78, $80, $88, $90, $94, $98, $9C,
    $A0, $A4, $A8, $AC, $B0, $B4, $B8, $BC, $C0, $C2, $C4, $C6, $C8, $CA, $CC, $CE,
    $D0, $D2, $D4, $D6, $D8, $DA, $DC, $DE, $E0, $E2, $E4, $E6, $E8, $EA, $EC, $EE,
    $F0, $F1, $F2, $F3, $F4, $F5, $F6, $F7, $F8, $F9, $FA, $FB, $FC, $FD, $FE, $FF);

type
  // The adaptive Huffman tree. Encoder and decoder have to reshape it in exactly
  // the same way after every symbol, so both use this one.
  THuffTree = class
  public
    Freq: array[0..T] of integer;
    Prnt: array[0..T + NChar - 1] of integer;
    Son: array[0..T - 1] of integer;
    constructor Create;
    procedure Reconst;
    procedure Update(C: integer);
  end;

constructor THuffTree.Create;
var
  I, J: integer;
begin
  inherited;
  for I := 0 to NChar - 1 do
  begin
    Freq[I] := 1;
    Son[I] := I + T;
    Prnt[I + T] := I;
  end;
  I := 0;
  J := NChar;
  while J <= R do
  begin
    Freq[J] := Freq[I] + Freq[I + 1];
    Son[J] := I;
    Prnt[I] := J;
    Prnt[I + 1] := J;
    Inc(I, 2);
    Inc(J);
  end;
  Freq[T] := $FFFF; // sentinel that stops Update's search
  Prnt[R] := 0;
end;

// Halve every leaf count and rebuild the tree, keeping it in frequency order
procedure THuffTree.Reconst;
var
  I, J, K, L, Fr: integer;
begin
  J := 0;
  for I := 0 to T - 1 do
    if Son[I] >= T then
    begin
      Freq[J] := (Freq[I] + 1) div 2;
      Son[J] := Son[I];
      Inc(J);
    end;

  I := 0;
  J := NChar;
  while J < T do
  begin
    Fr := Freq[I] + Freq[I + 1];
    Freq[J] := Fr;
    K := J - 1;
    while Fr < Freq[K] do
      Dec(K);
    Inc(K);
    for L := J downto K + 1 do
    begin
      Freq[L] := Freq[L - 1];
      Son[L] := Son[L - 1];
    end;
    Freq[K] := Fr;
    Son[K] := I;
    Inc(I, 2);
    Inc(J);
  end;

  for I := 0 to T - 1 do
  begin
    K := Son[I];
    Prnt[K] := I;
    if K < T then
      Prnt[K + 1] := I;
  end;
end;

// Count one more of symbol C, moving its node up past any it now outweighs
procedure THuffTree.Update(C: integer);
var
  I, J, K, L: integer;
begin
  if Freq[R] = MaxFreq then
    Reconst;
  C := Prnt[C + T];
  repeat
    Inc(Freq[C]);
    K := Freq[C];
    L := C + 1;
    if K > Freq[L] then
    begin
      repeat
        Inc(L);
      until K <= Freq[L];
      Dec(L);
      Freq[C] := Freq[L];
      Freq[L] := K;

      I := Son[C];
      Prnt[I] := L;
      if I < T then Prnt[I + 1] := L;

      J := Son[L];
      Son[L] := I;
      Prnt[J] := C;
      if J < T then Prnt[J + 1] := C;

      Son[C] := J;
      C := L;
    end;
    C := Prnt[C];
  until C = 0;
end;

procedure LZHufDecompress(Src, Dest: TStream);
var
  Input: array of byte;
  InputBits, BitPos: int64;
  Tree: THuffTree;
  Text: array[0..N - 1] of byte;
  DCode, DLen: array[0..255] of byte;
  Output: TMemoryStream;
  RPos, I, J, K, C, Start, Span, Position: integer;
  B: byte;

  // Bits past the end of the input read as zero. Whether that happened is
  // checked once the symbol is complete, as the last byte is padded out.
  function GetBit: integer;
  begin
    if BitPos < InputBits then
      Result := (Input[BitPos shr 3] shr (7 - (BitPos and 7))) and 1
    else
      Result := 0;
    Inc(BitPos);
  end;

  function GetByte: integer;
  var
    Idx: integer;
  begin
    Result := 0;
    for Idx := 1 to 8 do
      Result := (Result shl 1) or GetBit;
  end;

  function DecodeChar: integer;
  begin
    Result := Tree.Son[R];
    while Result < T do
      Result := Tree.Son[Result + GetBit];
    Dec(Result, T);
    Tree.Update(Result);
  end;

  function DecodePosition: integer;
  var
    Idx, Bits: integer;
  begin
    Idx := GetByte;
    Result := DCode[Idx] shl 6;
    for Bits := 1 to DLen[Idx] - 2 do
      Idx := (Idx shl 1) + GetBit;
    Result := Result or (Idx and $3F);
  end;

  procedure Emit(Value: byte);
  begin
    Output.WriteByte(Value);
    Text[RPos] := Value;
    RPos := (RPos + 1) and (N - 1);
  end;

begin
  SetLength(Input, Src.Size - Src.Position);
  if Length(Input) > 0 then
    Src.ReadBuffer(Input[0], Length(Input));
  InputBits := int64(Length(Input)) * 8;
  BitPos := 0;

  // Every byte whose leading bits match a position code maps to that code,
  // which is what LZHUF.C's hand-written d_code and d_len tables hold
  for I := 0 to 63 do
  begin
    Span := 1 shl (8 - PLen[I]);
    for J := PCode[I] to PCode[I] + Span - 1 do
    begin
      DCode[J] := I;
      DLen[J] := PLen[I];
    end;
  end;

  FillChar(Text, SizeOf(Text), $20);
  RPos := N - F;
  Tree := THuffTree.Create;
  Output := TMemoryStream.Create;
  try
    while BitPos < InputBits do
    begin
      C := DecodeChar;
      if C < 256 then
      begin
        // A symbol finished only by the padding is not one the encoder sent
        if BitPos > InputBits then break;
        Emit(C);
      end
      else
      begin
        Position := DecodePosition;
        if BitPos > InputBits then break;
        Start := (RPos - Position - 1) and (N - 1);
        for K := 0 to C - 255 + Threshold - 1 do
        begin
          B := Text[(Start + K) and (N - 1)];
          Emit(B);
        end;
      end;

      if Output.Size > MaxDecompressed then
        raise Exception.Create('Compressed data expands past any disk size.');
    end;

    Output.Position := 0;
    Dest.CopyFrom(Output, Output.Size);
  finally
    Output.Free;
    Tree.Free;
  end;
end;

type
  // Finds the longest earlier match for the text at a position, keeping every
  // position in the window in a binary tree per first byte (LZHUF.C's scheme)
  TMatchFinder = class
  public
    TextBuf: array[0..N + F - 2] of byte;
    LSon: array[0..N] of integer;
    RSon: array[0..N + 256] of integer;
    Dad: array[0..N] of integer;
    MatchPosition, MatchLength: integer;
    constructor Create;
    procedure InsertNode(Pos: integer);
    procedure DeleteNode(P: integer);
  end;

constructor TMatchFinder.Create;
var
  I: integer;
begin
  inherited;
  for I := N + 1 to N + 256 do
    RSon[I] := Nil_;
  for I := 0 to N - 1 do
    Dad[I] := Nil_;
end;

procedure TMatchFinder.InsertNode(Pos: integer);
var
  I, P, Cmp, C: integer;
begin
  Cmp := 1;
  P := N + 1 + TextBuf[Pos];
  RSon[Pos] := Nil_;
  LSon[Pos] := Nil_;
  MatchLength := 0;
  while True do
  begin
    if Cmp >= 0 then
    begin
      if RSon[P] <> Nil_ then
        P := RSon[P]
      else
      begin
        RSon[P] := Pos;
        Dad[Pos] := P;
        exit;
      end;
    end
    else
    begin
      if LSon[P] <> Nil_ then
        P := LSon[P]
      else
      begin
        LSon[P] := Pos;
        Dad[Pos] := P;
        exit;
      end;
    end;

    I := 1;
    Cmp := 0;
    while I < F do
    begin
      Cmp := TextBuf[Pos + I] - TextBuf[P + I];
      if Cmp <> 0 then break;
      Inc(I);
    end;

    if I > Threshold then
    begin
      if I > MatchLength then
      begin
        MatchPosition := ((Pos - P) and (N - 1)) - 1;
        MatchLength := I;
        if MatchLength >= F then break;
      end;
      if I = MatchLength then
      begin
        C := ((Pos - P) and (N - 1)) - 1;
        if C < MatchPosition then
          MatchPosition := C;
      end;
    end;
  end;

  // A full-length match: the new position replaces the old one in the tree
  Dad[Pos] := Dad[P];
  LSon[Pos] := LSon[P];
  RSon[Pos] := RSon[P];
  Dad[LSon[P]] := Pos;
  Dad[RSon[P]] := Pos;
  if RSon[Dad[P]] = P then
    RSon[Dad[P]] := Pos
  else
    LSon[Dad[P]] := Pos;
  Dad[P] := Nil_;
end;

procedure TMatchFinder.DeleteNode(P: integer);
var
  Q: integer;
begin
  if Dad[P] = Nil_ then exit;
  if RSon[P] = Nil_ then
    Q := LSon[P]
  else if LSon[P] = Nil_ then
    Q := RSon[P]
  else
  begin
    Q := LSon[P];
    if RSon[Q] <> Nil_ then
    begin
      repeat
        Q := RSon[Q];
      until RSon[Q] = Nil_;
      RSon[Dad[Q]] := LSon[Q];
      Dad[LSon[Q]] := Dad[Q];
      LSon[Q] := LSon[P];
      Dad[LSon[P]] := Q;
    end;
    RSon[Q] := RSon[P];
    Dad[RSon[P]] := Q;
  end;
  Dad[Q] := Dad[P];
  if RSon[Dad[P]] = P then
    RSon[Dad[P]] := Q
  else
    LSon[Dad[P]] := Q;
  Dad[P] := Nil_;
end;

procedure LZHufCompress(Src, Dest: TStream);
var
  Input: array of byte;
  InPos: integer;
  Tree: THuffTree;
  Finder: TMatchFinder;
  Output: TMemoryStream;
  OutByte, OutBits: integer;
  S, RPos, Len, I, LastMatchLength, C: integer;

  procedure PutBit(Bit: integer);
  begin
    OutByte := (OutByte shl 1) or Bit;
    Inc(OutBits);
    if OutBits = 8 then
    begin
      Output.WriteByte(OutByte);
      OutByte := 0;
      OutBits := 0;
    end;
  end;

  procedure PutBits(Count, Value: integer);
  var
    Idx: integer;
  begin
    for Idx := Count - 1 downto 0 do
      PutBit((Value shr Idx) and 1);
  end;

  // The path from the root to the symbol's leaf. LZHUF.C gathers it in a
  // 16-bit word, which a deep enough tree would overflow, so it is gathered
  // here a bit at a time instead: the same bits whenever that word was enough.
  procedure EncodeChar(Symbol: integer);
  var
    Path: array[0..T] of byte;
    Depth, K: integer;
  begin
    Depth := 0;
    K := Tree.Prnt[Symbol + T];
    repeat
      Path[Depth] := K and 1;
      Inc(Depth);
      K := Tree.Prnt[K];
    until K = R;
    for K := Depth - 1 downto 0 do
      PutBit(Path[K]);
    Tree.Update(Symbol);
  end;

  procedure EncodePosition(Position: integer);
  var
    Idx: integer;
  begin
    Idx := Position shr 6;
    PutBits(PLen[Idx], PCode[Idx] shr (8 - PLen[Idx]));
    PutBits(6, Position and $3F);
  end;

  procedure PadToByte;
  var
    Path: array[0..T] of byte;
    Depth, Deepest, DeepestSymbol, Symbol, K: integer;
  begin
    Deepest := 0;
    DeepestSymbol := 0;
    for Symbol := 0 to NChar - 1 do
    begin
      Depth := 0;
      K := Tree.Prnt[Symbol + T];
      repeat
        Inc(Depth);
        K := Tree.Prnt[K];
      until K = R;
      if Depth > Deepest then
      begin
        Deepest := Depth;
        DeepestSymbol := Symbol;
      end;
    end;

    Depth := 0;
    K := Tree.Prnt[DeepestSymbol + T];
    repeat
      Path[Depth] := K and 1;
      Inc(Depth);
      K := Tree.Prnt[K];
    until K = R;
    K := Depth - 1;
    while OutBits > 0 do
    begin
      PutBit(Path[K]);
      Dec(K);
    end;
  end;

  function NextByte(out Value: integer): boolean;
  begin
    Result := InPos < Length(Input);
    if Result then
    begin
      Value := Input[InPos];
      Inc(InPos);
    end;
  end;

begin
  SetLength(Input, Src.Size - Src.Position);
  if Length(Input) = 0 then exit; // LZHUF.C would send a stray space for nothing
  Src.ReadBuffer(Input[0], Length(Input));
  InPos := 0;
  OutByte := 0;
  OutBits := 0;

  Tree := THuffTree.Create;
  Finder := TMatchFinder.Create;
  Output := TMemoryStream.Create;
  try
    with Finder do
    begin
      S := 0;
      RPos := N - F;
      FillChar(TextBuf, RPos, $20);
      Len := 0;
      while (Len < F) and NextByte(C) do
      begin
        TextBuf[RPos + Len] := C;
        Inc(Len);
      end;
      for I := 1 to F do
        InsertNode(RPos - I);
      InsertNode(RPos);

      repeat
        if MatchLength > Len then
          MatchLength := Len;
        if MatchLength <= Threshold then
        begin
          MatchLength := 1;
          EncodeChar(TextBuf[RPos]);
        end
        else
        begin
          EncodeChar(255 - Threshold + MatchLength);
          EncodePosition(MatchPosition);
        end;

        LastMatchLength := MatchLength;
        I := 0;
        while (I < LastMatchLength) and NextByte(C) do
        begin
          DeleteNode(S);
          TextBuf[S] := C;
          if S < F - 1 then
            TextBuf[S + N] := C;
          S := (S + 1) and (N - 1);
          RPos := (RPos + 1) and (N - 1);
          InsertNode(RPos);
          Inc(I);
        end;
        while I < LastMatchLength do
        begin
          Inc(I);
          DeleteNode(S);
          S := (S + 1) and (N - 1);
          RPos := (RPos + 1) and (N - 1);
          Dec(Len);
          if Len > 0 then
            InsertNode(RPos);
        end;
      until Len <= 0;
    end;

    // Nothing says where the stream ends, so padding that happened to spell a
    // symbol would decode as one more byte. Pad along the way to the deepest
    // leaf instead: 314 leaves put that at least nine bits down, more than the
    // seven padding can need, so the decoder runs out of input first.
    if OutBits > 0 then
      PadToByte;

    Output.Position := 0;
    Dest.CopyFrom(Output, Output.Size);
  finally
    Output.Free;
    Finder.Free;
    Tree.Free;
  end;
end;

end.
