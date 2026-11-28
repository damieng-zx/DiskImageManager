unit Z80Disasm;

{$MODE Delphi}

{
  Disk Image Manager - Z80 disassembler

  The whole instruction set including the undocumented opcodes: the halves of
  IX and IY, SLL, the ED mirrors and the results DD CB and FD CB store in a
  register. Ported from the disassembler in zx84.

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

const
  // Marks put either side of a number in an instruction's text, saying what it
  // is, so that a viewer can colour it
  MarkValue = #1;
  MarkAddress = #2;
  MarkPort = #3;

type
  TZ80Instruction = record
    // Bytes the instruction takes, which can reach past the end of the data
    Size: integer;
    // Mnemonic and operands, numbers in hex between their marks
    Text: string;
    // Execution does not carry on to the instruction that follows
    IsTerminal: boolean;
  end;

// Decode the instruction at Offset in Data as it would run at Address. Bytes past
// the end of the data read as zero.
function DisassembleZ80(const Data: array of byte; Offset: integer;
  Address: word): TZ80Instruction;

// An instruction's text without the marks
function StripZ80Marks(const Text: string): string;

implementation

uses
  SysUtils;

const
  Registers: array[0..7] of string = ('B', 'C', 'D', 'E', 'H', 'L', '(HL)', 'A');
  Pairs: array[0..3] of string = ('BC', 'DE', 'HL', 'SP');
  StackPairs: array[0..3] of string = ('BC', 'DE', 'HL', 'AF');
  Conditions: array[0..7] of string = ('NZ', 'Z', 'NC', 'C', 'PO', 'PE', 'P', 'M');
  Arithmetic: array[0..7] of string =
    ('ADD A,', 'ADC A,', 'SUB ', 'SBC A,', 'AND ', 'XOR ', 'OR ', 'CP ');
  Rotates: array[0..7] of string =
    ('RLC', 'RRC', 'RL', 'RR', 'SLA', 'SRA', 'SLL', 'SRL');
  Accumulator: array[0..7] of string =
    ('RLCA', 'RRCA', 'RLA', 'RRA', 'DAA', 'CPL', 'SCF', 'CCF');
  Blocks: array[4..7, 0..3] of string = (
    ('LDI', 'CPI', 'INI', 'OUTI'), ('LDD', 'CPD', 'IND', 'OUTD'),
    ('LDIR', 'CPIR', 'INIR', 'OTIR'), ('LDDR', 'CPDR', 'INDR', 'OTDR'));
  Miscellaneous: array[0..7] of string =
    ('LD I,A', 'LD R,A', 'LD A,I', 'LD A,R', 'RRD', 'RLD', 'NOP*', 'NOP*');
  InterruptModes: array[0..7] of char =
    ('0', '0', '1', '2', '0', '0', '1', '2');

function Value(const Number: string): string;
begin
  Result := MarkValue + Number + MarkValue;
end;

function Location(Number: word): string;
begin
  Result := MarkAddress + IntToHex(Number, 4) + MarkAddress;
end;

function Port(const Name: string): string;
begin
  Result := MarkPort + Name + MarkPort;
end;

// An index register displacement, which is signed
function Displacement(B: byte): string;
begin
  if B < 128 then
    Result := Value('+' + IntToHex(B, 2))
  else
    Result := Value('-' + IntToHex(256 - B, 2));
end;

// The operation of a byte following CB, on whatever operand is named
function BitOperation(Op: byte; const Operand: string): string;
var
  Y: integer;
begin
  Y := (Op shr 3) and 7;
  case Op shr 6 of
    0: Result := Rotates[Y] + ' ' + Operand;
    1: Result := 'BIT ' + Value(IntToStr(Y)) + ',' + Operand;
    2: Result := 'RES ' + Value(IntToStr(Y)) + ',' + Operand;
    else Result := 'SET ' + Value(IntToStr(Y)) + ',' + Operand;
  end;
end;

function DisassembleZ80(const Data: array of byte; Offset: integer;
  Address: word): TZ80Instruction;
var
  Used: integer;
  Index: string;        // 'IX' or 'IY' after a DD or FD prefix, else empty
  Indexed: string;      // the (IX+d) operand once its byte has been read
  Op, X, Y, Z, P, Q: integer;

  // Every byte is read into a variable before text is built from it: the order
  // the parts of an expression are worked out in is not the order written
  function Next: byte;
  begin
    if (Offset + Used >= 0) and (Offset + Used < Length(Data)) then
      Result := Data[Offset + Used]
    else
      Result := 0;
    Inc(Used);
  end;

  function NextWord: word;
  var
    Low, High: byte;
  begin
    Low := Next;
    High := Next;
    Result := Low or (High shl 8);
  end;

  function ByteValue: string;
  begin
    Result := Value(IntToHex(Next, 2));
  end;

  function WordValue: string;
  begin
    Result := Value(IntToHex(NextWord, 4));
  end;

  function Absolute: string;
  begin
    Result := Location(NextWord);
  end;

  // Where a relative jump goes, from the instruction after it
  function Relative: string;
  var
    B: byte;
    Distance: integer;
  begin
    B := Next;
    Distance := B;
    if Distance > 127 then
      Dec(Distance, 256);
    Result := Location(word((Address + Used + Distance) and $FFFF));
  end;

  // The memory operand (HL), or (IX+d) after a prefix
  function Memory: string;
  begin
    if Index = '' then
      exit('(HL)');
    if Indexed = '' then
      Indexed := '(' + Index + Displacement(Next) + ')';
    Result := Indexed;
  end;

  // A register, where H and L are halves of the index register after a prefix
  // unless the instruction also uses memory
  function Register(Number: integer; WithMemory: boolean): string;
  begin
    if Number = 6 then
      Result := Memory
    else if (Index <> '') and not WithMemory and (Number = 4) then
      Result := Index + 'H'
    else if (Index <> '') and not WithMemory and (Number = 5) then
      Result := Index + 'L'
    else
      Result := Registers[Number];
  end;

  // HL, or the index register that takes its place
  function HL: string;
  begin
    if Index = '' then
      Result := 'HL'
    else
      Result := Index;
  end;

  function Pair(Number: integer): string;
  begin
    if Number = 2 then
      Result := HL
    else
      Result := Pairs[Number];
  end;

  function StackPair(Number: integer): string;
  begin
    if Number = 2 then
      Result := HL
    else
      Result := StackPairs[Number];
  end;

  function Extended: string;
  var
    Op, Y, Z, P: integer;
    Where: string;
  begin
    Op := Next;
    Y := (Op shr 3) and 7;
    Z := Op and 7;
    P := Y shr 1;
    Result := 'NOP*';
    if Op shr 6 = 1 then
      case Z of
        0:
          if Y = 6 then
            Result := 'IN (' + Port('C') + ')'
          else
            Result := 'IN ' + Registers[Y] + ',(' + Port('C') + ')';
        1:
          if Y = 6 then
            Result := 'OUT (' + Port('C') + '),' + Value('00')
          else
            Result := 'OUT (' + Port('C') + '),' + Registers[Y];
        2:
          if Odd(Y) then
            Result := 'ADC HL,' + Pairs[P]
          else
            Result := 'SBC HL,' + Pairs[P];
        3:
          begin
            Where := Absolute;
            if Odd(Y) then
              Result := 'LD ' + Pairs[P] + ',(' + Where + ')'
            else
              Result := 'LD (' + Where + '),' + Pairs[P];
          end;
        4: Result := 'NEG';
        5:
          begin
            if Y = 1 then
              Result := 'RETI'
            else
              Result := 'RETN';
          end;
        6: Result := 'IM ' + Value(InterruptModes[Y]);
        7: Result := Miscellaneous[Y];
      end
    else if (Op shr 6 = 2) and (Y >= 4) and (Z < 4) then
      Result := Blocks[Y, Z];
  end;

var
  First, Second: string;
  Shift: byte;
  Operand: string;
begin
  Used := 0;
  Index := '';
  Indexed := '';
  Result.IsTerminal := False;
  Result.Text := '';

  Op := Next;
  if (Op = $DD) or (Op = $FD) then
  begin
    if Op = $DD then
      Index := 'IX'
    else
      Index := 'IY';
    Op := Next;
    // A prefix followed by another does nothing of its own
    if (Op = $DD) or (Op = $FD) or (Op = $ED) then
    begin
      Result.Size := 1;
      Result.Text := 'NOP*';
      exit;
    end;
    // DD CB and FD CB have the displacement before the operation
    if Op = $CB then
    begin
      Operand := Memory;
      Shift := Next;
      Result.Text := BitOperation(Shift, Operand);
      // Other than BIT, the undocumented forms also copy the result to a register
      if (Shift shr 6 <> 1) and (Shift and 7 <> 6) then
        Result.Text := Result.Text + ',' + Registers[Shift and 7];
      Result.Size := Used;
      exit;
    end;
  end;

  if Op = $CB then
  begin
    Shift := Next;
    Result.Text := BitOperation(Shift, Registers[Shift and 7]);
    Result.Size := Used;
    exit;
  end;

  if Op = $ED then
  begin
    Result.Text := Extended;
    Result.IsTerminal := (Result.Text = 'RETI') or (Result.Text = 'RETN');
    Result.Size := Used;
    exit;
  end;

  X := Op shr 6;
  Y := (Op shr 3) and 7;
  Z := Op and 7;
  P := Y shr 1;
  Q := Y and 1;

  case X of
    0:
      case Z of
        0:
          case Y of
            0: Result.Text := 'NOP';
            1: Result.Text := 'EX AF,AF''';
            2: Result.Text := 'DJNZ ' + Relative;
            3:
              begin
                Result.Text := 'JR ' + Relative;
                Result.IsTerminal := True;
              end;
            else
              Result.Text := 'JR ' + Conditions[Y - 4] + ',' + Relative;
          end;
        1:
          if Q = 0 then
          begin
            First := Pair(P);
            Result.Text := 'LD ' + First + ',' + WordValue;
          end
          else
            Result.Text := 'ADD ' + HL + ',' + Pair(P);
        2:
          begin
            case P of
              0: First := '(BC)';
              1: First := '(DE)';
              else First := '(' + Absolute + ')';
            end;
            if P = 2 then
              Second := HL
            else
              Second := 'A';
            if Q = 0 then
              Result.Text := 'LD ' + First + ',' + Second
            else
              Result.Text := 'LD ' + Second + ',' + First;
          end;
        3:
          if Q = 0 then
            Result.Text := 'INC ' + Pair(P)
          else
            Result.Text := 'DEC ' + Pair(P);
        4: Result.Text := 'INC ' + Register(Y, False);
        5: Result.Text := 'DEC ' + Register(Y, False);
        6:
          begin
            First := Register(Y, False);
            Result.Text := 'LD ' + First + ',' + ByteValue;
          end;
        7: Result.Text := Accumulator[Y];
      end;

    1:
      if (Y = 6) and (Z = 6) then
      begin
        Result.Text := 'HALT';
        Result.IsTerminal := True;
      end
      else
      begin
        First := Register(Y, (Y = 6) or (Z = 6));
        Second := Register(Z, (Y = 6) or (Z = 6));
        Result.Text := 'LD ' + First + ',' + Second;
      end;

    2: Result.Text := Arithmetic[Y] + Register(Z, False);

    else
      case Z of
        0: Result.Text := 'RET ' + Conditions[Y];
        1:
          if Q = 0 then
            Result.Text := 'POP ' + StackPair(P)
          else
          begin
            case P of
              0: Result.Text := 'RET';
              1: Result.Text := 'EXX';
              2: Result.Text := 'JP (' + HL + ')';
              3: Result.Text := 'LD SP,' + HL;
            end;
            Result.IsTerminal := (P = 0) or (P = 2);
          end;
        2: Result.Text := 'JP ' + Conditions[Y] + ',' + Absolute;
        3:
          case Y of
            0:
              begin
                Result.Text := 'JP ' + Absolute;
                Result.IsTerminal := True;
              end;
            2: Result.Text := 'OUT (' + Port(IntToHex(Next, 2)) + '),A';
            3: Result.Text := 'IN A,(' + Port(IntToHex(Next, 2)) + ')';
            4: Result.Text := 'EX (SP),' + HL;
            5: Result.Text := 'EX DE,HL';
            6: Result.Text := 'DI';
            7: Result.Text := 'EI';
          end;
        4: Result.Text := 'CALL ' + Conditions[Y] + ',' + Absolute;
        5:
          // The other odd values are the prefixes, dealt with above
          if Q = 0 then
            Result.Text := 'PUSH ' + StackPair(P)
          else
            Result.Text := 'CALL ' + Absolute;
        6: Result.Text := Arithmetic[Y] + ByteValue;
        7: Result.Text := 'RST ' + Location(Y * 8);
      end;
  end;

  Result.Size := Used;
end;

function StripZ80Marks(const Text: string): string;
var
  C: char;
begin
  Result := '';
  for C in Text do
    if not (C in [MarkValue, MarkAddress, MarkPort]) then
      Result := Result + C;
end;

end.
