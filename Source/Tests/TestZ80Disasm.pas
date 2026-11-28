unit TestZ80Disasm;

{$mode objfpc}{$H+}

{
  Disk Image Manager - Unit tests for the Z80 disassembler, following those of
  the zx84 disassembler it was ported from.
}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Z80Disasm;

type
  TZ80DisasmTest = class(TTestCase)
  private
    function Decode(const Hex: string; Address: word = 0): TZ80Instruction;
    procedure Check(const Cases: array of string);
  published
    procedure TestLoadsAndArithmetic;
    procedure TestJumpsAndCalls;
    procedure TestStackAndMisc;
    procedure TestBitOperations;
    procedure TestExtended;
    procedure TestIndexRegisters;
    procedure TestIndexedBitOperations;
    procedure TestSizes;
    procedure TestWhatEndsExecution;
    procedure TestAddressesWrap;
    procedure TestRunningPastTheEnd;
    procedure TestEveryOpcodeDecodes;
    procedure TestOperandsAreMarked;
  end;

implementation

// The bytes written in hex with spaces between, as a byte array
function Bytes(const Hex: string): TBytes;
var
  Parts: TStringArray;
  Idx: integer;
begin
  Result := nil;
  Parts := Hex.Split([' ']);
  SetLength(Result, Length(Parts));
  for Idx := 0 to High(Parts) do
    Result[Idx] := StrToInt('$' + Parts[Idx]);
end;

function TZ80DisasmTest.Decode(const Hex: string; Address: word): TZ80Instruction;
begin
  Result := DisassembleZ80(Bytes(Hex), 0, Address);
end;

// Each case is the bytes, then a colon, then the instruction they make
procedure TZ80DisasmTest.Check(const Cases: array of string);
var
  Idx, Colon: integer;
  Hex, Expected: string;
begin
  for Idx := 0 to High(Cases) do
  begin
    Colon := Pos(':', Cases[Idx]);
    Hex := Copy(Cases[Idx], 1, Colon - 1);
    Expected := Copy(Cases[Idx], Colon + 1, MaxInt);
    AssertEquals(Hex, Expected, StripZ80Marks(Decode(Hex).Text));
  end;
end;

procedure TZ80DisasmTest.TestLoadsAndArithmetic;
const
  Ops: array[0..7] of string =
    ('ADD A,', 'ADC A,', 'SUB ', 'SBC A,', 'AND ', 'XOR ', 'OR ', 'CP ');
var
  Idx: integer;
begin
  Check(['00:NOP', '01 34 12:LD BC,1234', '03:INC BC', '04:INC B', '05:DEC B',
    '06 42:LD B,42', '08:EX AF,AF''', '22 00 80:LD (8000),HL',
    '2A 00 40:LD HL,(4000)', '32 00 C0:LD (C000),A', '3A 00 40:LD A,(4000)',
    '0A:LD A,(BC)', '1A:LD A,(DE)', '02:LD (BC),A', '12:LD (DE),A',
    '76:HALT', '78:LD A,B', '41:LD B,C', '65:LD H,L', '77:LD (HL),A',
    '80:ADD A,B', 'AF:XOR A', 'BE:CP (HL)', '09:ADD HL,BC', '19:ADD HL,DE',
    '29:ADD HL,HL', '39:ADD HL,SP', '07:RLCA', '0F:RRCA', '17:RLA', '1F:RRA',
    '27:DAA', '2F:CPL', '37:SCF', '3F:CCF']);
  for Idx := 0 to 7 do
    AssertEquals(Ops[Idx], Ops[Idx] + '55',
      StripZ80Marks(Decode(IntToHex($C6 + Idx * 8, 2) + ' 55').Text));
end;

procedure TZ80DisasmTest.TestJumpsAndCalls;
const
  Conditions: array[0..7] of string = ('NZ', 'Z', 'NC', 'C', 'PO', 'PE', 'P', 'M');
var
  Idx: integer;
begin
  Check(['C3 00 10:JP 1000', '18 05:JR 0007', '20 05:JR NZ,0007',
    '28 05:JR Z,0007', '30 05:JR NC,0007', '38 05:JR C,0007',
    '10 10:DJNZ 0012', 'CD 34 12:CALL 1234', 'C9:RET', 'CF:RST 0008',
    'FF:RST 0038', 'E9:JP (HL)']);
  for Idx := 0 to 7 do
  begin
    AssertEquals('RET ' + Conditions[Idx],
      StripZ80Marks(Decode(IntToHex($C0 + Idx * 8, 2)).Text));
    AssertEquals('JP ' + Conditions[Idx] + ',1234',
      StripZ80Marks(Decode(IntToHex($C2 + Idx * 8, 2) + ' 34 12').Text));
    AssertEquals('CALL ' + Conditions[Idx] + ',1234',
      StripZ80Marks(Decode(IntToHex($C4 + Idx * 8, 2) + ' 34 12').Text));
  end;
  AssertEquals('backwards', 'JR 0100',
    StripZ80Marks(Decode('18 FE', $100).Text));
end;

procedure TZ80DisasmTest.TestStackAndMisc;
begin
  Check(['C1:POP BC', 'D1:POP DE', 'E1:POP HL', 'F1:POP AF', 'C5:PUSH BC',
    'D5:PUSH DE', 'E5:PUSH HL', 'F5:PUSH AF', 'D9:EXX', 'EB:EX DE,HL',
    'E3:EX (SP),HL', 'F9:LD SP,HL', 'DB FE:IN A,(FE)', 'D3 7F:OUT (7F),A',
    'F3:DI', 'FB:EI']);
end;

procedure TZ80DisasmTest.TestBitOperations;
const
  Rotates: array[0..7] of string =
    ('RLC', 'RRC', 'RL', 'RR', 'SLA', 'SRA', 'SLL', 'SRL');
  Registers: array[0..7] of string = ('B', 'C', 'D', 'E', 'H', 'L', '(HL)', 'A');
var
  Y, Z: integer;
  Last: string;

  function CB(Op: integer): string;
  begin
    Result := StripZ80Marks(Decode('CB ' + IntToHex(Op, 2)).Text);
  end;

begin
  for Y := 0 to 7 do
    for Z := 0 to 7 do
    begin
      Last := ',' + Registers[Z];
      AssertEquals(Rotates[Y] + ' ' + Registers[Z], CB(Y * 8 + Z));
      AssertEquals('BIT ' + IntToStr(Y) + Last, CB($40 + Y * 8 + Z));
      AssertEquals('RES ' + IntToStr(Y) + Last, CB($80 + Y * 8 + Z));
      AssertEquals('SET ' + IntToStr(Y) + Last, CB($C0 + Y * 8 + Z));
    end;
end;

procedure TZ80DisasmTest.TestExtended;
begin
  Check(['ED A0:LDI', 'ED A1:CPI', 'ED A2:INI', 'ED A3:OUTI', 'ED A8:LDD',
    'ED A9:CPD', 'ED AA:IND', 'ED AB:OUTD', 'ED B0:LDIR', 'ED B1:CPIR',
    'ED B2:INIR', 'ED B3:OTIR', 'ED B8:LDDR', 'ED B9:CPDR', 'ED BA:INDR',
    'ED BB:OTDR', 'ED 47:LD I,A', 'ED 4F:LD R,A', 'ED 57:LD A,I',
    'ED 5F:LD A,R', 'ED 67:RRD', 'ED 6F:RLD', 'ED 77:NOP*', 'ED 7F:NOP*',
    'ED 46:IM 0', 'ED 4E:IM 0', 'ED 56:IM 1', 'ED 5E:IM 2', 'ED 66:IM 0',
    'ED 6E:IM 0', 'ED 76:IM 1', 'ED 7E:IM 2', 'ED 44:NEG', 'ED 45:RETN',
    'ED 4D:RETI', 'ED 40:IN B,(C)', 'ED 48:IN C,(C)', 'ED 50:IN D,(C)',
    'ED 58:IN E,(C)', 'ED 60:IN H,(C)', 'ED 68:IN L,(C)', 'ED 70:IN (C)',
    'ED 78:IN A,(C)', 'ED 41:OUT (C),B', 'ED 49:OUT (C),C',
    'ED 51:OUT (C),D', 'ED 59:OUT (C),E', 'ED 61:OUT (C),H',
    'ED 69:OUT (C),L', 'ED 71:OUT (C),00', 'ED 79:OUT (C),A',
    'ED 42:SBC HL,BC', 'ED 52:SBC HL,DE', 'ED 62:SBC HL,HL',
    'ED 72:SBC HL,SP', 'ED 4A:ADC HL,BC', 'ED 5A:ADC HL,DE',
    'ED 6A:ADC HL,HL', 'ED 7A:ADC HL,SP', 'ED 43 00 40:LD (4000),BC',
    'ED 53 00 40:LD (4000),DE', 'ED 63 00 40:LD (4000),HL',
    'ED 73 00 40:LD (4000),SP', 'ED 4B 00 40:LD BC,(4000)',
    'ED 5B 00 40:LD DE,(4000)', 'ED 6B 00 40:LD HL,(4000)',
    'ED 7B 00 40:LD SP,(4000)', 'ED 00:NOP*']);
end;

procedure TZ80DisasmTest.TestIndexRegisters;
begin
  Check(['DD 21 00 40:LD IX,4000', 'FD 21 00 80:LD IY,8000',
    'DD 36 05 42:LD (IX+05),42', 'DD 09:ADD IX,BC', 'DD 29:ADD IX,IX',
    'FD 09:ADD IY,BC', 'FD 29:ADD IY,IY', 'FD 39:ADD IY,SP',
    'DD E1:POP IX', 'FD E5:PUSH IY', 'DD E3:EX (SP),IX', 'FD E3:EX (SP),IY',
    'FD F9:LD SP,IY', 'DD E9:JP (IX)', 'FD E9:JP (IY)',
    'DD 22 00 40:LD (4000),IX', 'DD 2A 00 60:LD IX,(6000)',
    'FD 22 00 80:LD (8000),IY', 'FD 2A 34 12:LD IY,(1234)',
    'DD 23:INC IX', 'DD 2B:DEC IX', 'FD 23:INC IY', 'FD 2B:DEC IY',
    'DD 34 02:INC (IX+02)', 'DD 35 FF:DEC (IX-01)', 'FD 34 10:INC (IY+10)',
    'FD 35 00:DEC (IY+00)', 'DD 7C:LD A,IXH', 'DD 7D:LD A,IXL',
    'FD 7C:LD A,IYH', 'DD 24:INC IXH', 'DD 85:ADD A,IXL',
    'DD 26 AB:LD IXH,AB', 'DD 2E 55:LD IXL,55', 'FD 26 01:LD IYH,01',
    'FD 2E FF:LD IYL,FF',
    // With a memory operand H and L are the real ones
    'DD 74 05:LD (IX+05),H', 'DD 66 05:LD H,(IX+05)',
    'DD 46 05:LD B,(IX+05)', 'FD 4E 01:LD C,(IY+01)',
    'FD 7E FF:LD A,(IY-01)', 'DD 86 00:ADD A,(IX+00)',
    'DD 86 80:ADD A,(IX-80)', 'DD 86 7F:ADD A,(IX+7F)',
    // One prefix straight after another does nothing
    'DD DD:NOP*', 'DD ED:NOP*', 'DD FD:NOP*', 'FD FD:NOP*', 'FD ED:NOP*',
    'FD DD:NOP*']);
end;

procedure TZ80DisasmTest.TestIndexedBitOperations;
begin
  Check(['DD CB 05 06:RLC (IX+05)', 'FD CB FF 59:BIT 3,(IY-01)',
    'DD CB 00 80:RES 0,(IX+00),B', 'FD CB 0A FE:SET 7,(IY+0A)',
    'DD CB FF 01:RLC (IX-01),C']);
end;

procedure TZ80DisasmTest.TestSizes;

  procedure Sized(const Hex: string; Expected: integer);
  begin
    AssertEquals(Hex, Expected, Decode(Hex).Size);
  end;

begin
  Sized('00', 1);
  Sized('3E 55', 2);
  Sized('01 34 12', 3);
  Sized('CD 00 10', 3);
  Sized('18 05', 2);
  Sized('CB 00', 2);
  Sized('ED A0', 2);
  Sized('ED 00', 2);
  Sized('ED 43 00 40', 4);
  Sized('DD 21 00 40', 4);
  Sized('DD 36 05 42', 4);
  Sized('DD CB 05 06', 4);
  Sized('DD DD', 1);
end;

procedure TZ80DisasmTest.TestWhatEndsExecution;

  procedure Ends(const Hex: string; Expected: boolean = True);
  begin
    AssertEquals(Hex, Expected, Decode(Hex).IsTerminal);
  end;

begin
  Ends('76');
  Ends('C3 00 00');
  Ends('18 00');
  Ends('C9');
  Ends('E9');
  Ends('DD E9');
  Ends('ED 45');
  Ends('ED 4D');
  Ends('C0', False);
  Ends('C2 00 00', False);
  Ends('CD 00 00', False);
  Ends('C7', False);
  Ends('D9', False);
  Ends('20 00', False);
end;

procedure TZ80DisasmTest.TestAddressesWrap;
begin
  AssertEquals('forward past the top', 'JR 0001',
    StripZ80Marks(Decode('18 01', $FFFE).Text));
  AssertEquals('back past the bottom', 'JR FFF2',
    StripZ80Marks(Decode('18 F0', $0000).Text));
end;

procedure TZ80DisasmTest.TestRunningPastTheEnd;
var
  Instruction: TZ80Instruction;
begin
  Instruction := Decode('01 34');
  AssertEquals('still the size it would be', 3, Instruction.Size);
  AssertEquals('missing bytes read as zero', 'LD BC,0034',
    StripZ80Marks(Instruction.Text));
end;

procedure TZ80DisasmTest.TestEveryOpcodeDecodes;
const
  Prefixes: array[0..6] of string =
    ('', 'CB ', 'ED ', 'DD ', 'FD ', 'DD CB 05 ', 'FD CB 05 ');
var
  Prefix, Op: integer;
  Hex, Text: string;
  Instruction: TZ80Instruction;
begin
  for Prefix := 0 to High(Prefixes) do
    for Op := 0 to 255 do
    begin
      // The prefixes themselves are covered by the longer runs
      if (Prefix = 0) and (Op in [$CB, $DD, $ED, $FD]) then continue;
      Hex := Prefixes[Prefix] + IntToHex(Op, 2) + ' 12 34';
      Instruction := Decode(Hex);
      Text := StripZ80Marks(Instruction.Text);
      AssertTrue(Hex + ' has text', Text <> '');
      AssertTrue(Hex + ' size', (Instruction.Size >= 1) and (Instruction.Size <= 4));
    end;
end;

procedure TZ80DisasmTest.TestOperandsAreMarked;
begin
  AssertEquals('a value', 'LD A,'#1'42'#1, Decode('3E 42').Text);
  AssertEquals('an address', 'JP '#2'1000'#2, Decode('C3 00 10').Text);
  AssertEquals('a port', 'OUT ('#3'FE'#3'),A', Decode('D3 FE').Text);
end;

initialization
  RegisterTest(TZ80DisasmTest);
end.
