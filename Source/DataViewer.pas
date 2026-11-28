unit DataViewer;

{$MODE Delphi}

{
  Disk Image Manager - A file's contents as hex, text or Z80 code

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Menus, Dialogs,
  DskImage, FileSystem, MGTFileSystem, OpusFileSystem, DIMUtils, ByteViews,
  RTFView, SinclairBasic, Utils;

type
  TViewerMode = (vmHex, vmText, vmZ80);

  TfrmDataViewer = class(TForm)
    pnlOptions: TPanel;
    radHex: TRadioButton;
    radText: TRadioButton;
    radZ80: TRadioButton;
    chkHeader: TCheckBox;
    lblAddress: TLabel;
    edtAddress: TEdit;
    btnExecute: TButton;
    popView: TPopupMenu;
    itmFromHere: TMenuItem;
    itmSeparator: TMenuItem;
    itmCopy: TMenuItem;
    itmSelectAll: TMenuItem;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure ModeChange(Sender: TObject);
    procedure chkHeaderChange(Sender: TObject);
    procedure edtAddressEditingDone(Sender: TObject);
    procedure btnExecuteClick(Sender: TObject);
    procedure itmFromHereClick(Sender: TObject);
    procedure itmCopyClick(Sender: TObject);
    procedure itmSelectAllClick(Sender: TObject);
  private
    // The file's data without and with its header
    FData: TDiskByteArray;
    FStored: TDiskByteArray;
    FSpectrum: boolean;
    // The address the first byte of the data is shown at
    FOrigin: integer;
    FExecute: integer;
    // Offsets into the data where an instruction is to start
    FSyncPoints: array of integer;
    // The offset into the data the menu was asked for at, or -1
    FClicked: integer;
    FViewer: TRTFViewer;
    // Which bytes the lines show, or nil for text
    FView: TByteView;
    // Bytes of header before the data in what FView shows
    FHeaderShown: integer;
    // Set while the controls are changed from code
    FChanging: boolean;
    function Mode: TViewerMode;
    procedure ShowContent;
    function TextContent(const Data: TDiskByteArray): AnsiString;
    // The data offset at the top of the view, or -1
    function TopOffset: integer;
    // Scroll to the line showing a data offset, selecting it if asked
    procedure GoToOffset(Offset: integer; Select: boolean);
    procedure ViewerMenu(Position: integer; const Where: TPoint);
  public
    procedure LoadFile(DiskFile: TDiskFile; const DiskName: string);
    // Switch to code with an instruction starting at an offset into the data
    procedure DisassembleFrom(Offset: integer);
    property Viewer: TRTFViewer read FViewer;
    property View: TByteView read FView;
  end;

// Show a file in its own window
procedure ShowDataViewer(DiskFile: TDiskFile; const DiskName: string);

// An address typed as hex, with or without &, $, # or 0x before it
function TryParseAddress(const Text: string; out Address: integer): boolean;

implementation

{$R *.lfm}

procedure ShowDataViewer(DiskFile: TDiskFile; const DiskName: string);
var
  Viewer: TfrmDataViewer;
begin
  Viewer := TfrmDataViewer.Create(Application);
  // Nothing but this holds the form until it is shown
  try
    Viewer.LoadFile(DiskFile, DiskName);
  except
    Viewer.Free;
    raise;
  end;
  Viewer.Show;
end;

function TryParseAddress(const Text: string; out Address: integer): boolean;
var
  Digits: string;
  C: char;
begin
  Address := 0;
  Digits := Trim(Text);
  if (Length(Digits) > 0) and (Digits[1] in ['&', '$', '#']) then
    Delete(Digits, 1, 1)
  else if SameText(System.Copy(Digits, 1, 2), '0x') then
    Delete(Digits, 1, 2);
  if (Digits = '') or (Length(Digits) > 4) then
    exit(False);
  for C in Digits do
    if not (C in ['0'..'9', 'A'..'F', 'a'..'f']) then
      exit(False);
  Address := StrToInt('$' + Digits);
  Result := True;
end;

procedure TfrmDataViewer.FormCreate(Sender: TObject);
begin
  FExecute := -1;
  FClicked := -1;
end;

procedure TfrmDataViewer.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Each viewed file opens a fresh modeless instance, so release it on close
  CloseAction := caFree;
end;

procedure TfrmDataViewer.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FViewer);
  FreeAndNil(FView);
end;

procedure TfrmDataViewer.FormResize(Sender: TObject);
begin
  if FViewer <> nil then
    FViewer.SetBounds(0, pnlOptions.Height, ClientWidth,
      ClientHeight - pnlOptions.Height);
end;

// The file is read now, so the window carries on if the disk is closed
procedure TfrmDataViewer.LoadFile(DiskFile: TDiskFile; const DiskName: string);
var
  Load: integer;
begin
  Caption := Format('%s - %s', [DiskFile.FileName, DiskName]);
  FData := DiskFile.GetData(False);
  FStored := DiskFile.GetData(True);
  FSpectrum := (DiskFile is TMGTFile) or (DiskFile is TOpusFile) or
    ((DiskFile is TCPMFile) and (TCPMFile(DiskFile).HeaderType = 'PLUS3DOS'));
  DiskFile.GetAddresses(Load, FExecute);
  FOrigin := 0;
  if Load >= 0 then
    FOrigin := Load;
  FSyncPoints := nil;

  FChanging := True;
  try
    chkHeader.Checked := False;
    chkHeader.Visible := DiskFile.HasHeader and (Length(FStored) > Length(FData));
    radHex.Checked := True;
    edtAddress.Text := IntToHex(FOrigin, 4);
    btnExecute.Visible := FExecute >= 0;
    if FExecute >= 0 then
      btnExecute.Caption := '&Go to execute address ' + IntToHex(FExecute, 4);
  finally
    FChanging := False;
  end;

  if FViewer = nil then
  begin
    HandleNeeded;
    FViewer := TRTFViewer.Create(Handle);
    if FViewer.Handle = 0 then
      raise Exception.Create(
        'Could not create the text viewer. riched20.dll may be missing.');
    FViewer.OnMenu := ViewerMenu;
  end;
  FormResize(Self);
  ShowContent;
end;

function TfrmDataViewer.Mode: TViewerMode;
begin
  if radText.Checked then
    Result := vmText
  else if radZ80.Checked then
    Result := vmZ80
  else
    Result := vmHex;
end;

function TfrmDataViewer.TextContent(const Data: TDiskByteArray): AnsiString;
var
  Parser: TSinclairBasicParser;
begin
  if not FSpectrum then
    exit(BuildASCIITextRTF(Data, MonoFontName));
  Parser := TSinclairBasicParser.Create(sbMode128K);
  try
    Parser.FontName := MonoFontName;
    Result := Parser.DecodeTextRTF(Data);
  finally
    Parser.Free;
  end;
end;

procedure TfrmDataViewer.ShowContent;
const
  Charsets: array[boolean] of TByteCharset = (csASCII, csSpectrum);
var
  RTF: AnsiString;
  WithHeader: boolean;
begin
  // The header is data to look at, but is no part of the code
  WithHeader := chkHeader.Visible and chkHeader.Checked and (Mode <> vmZ80);
  chkHeader.Enabled := Mode <> vmZ80;
  lblAddress.Enabled := (Mode <> vmText) and not WithHeader;
  edtAddress.Enabled := lblAddress.Enabled;

  Screen.Cursor := crHourGlass;
  try
    FreeAndNil(FView);
    FHeaderShown := 0;
    if WithHeader then
      FHeaderShown := Length(FStored) - Length(FData);

    case Mode of
      // With the header the addresses are places in the stored file
      vmHex:
        if WithHeader then
          FView := BuildHexView(FStored, 0, Charsets[FSpectrum], MonoFontName)
        else
          FView := BuildHexView(FData, FOrigin, Charsets[FSpectrum],
            MonoFontName);
      vmText:
        if WithHeader then
          RTF := TextContent(FStored)
        else
          RTF := TextContent(FData);
      vmZ80: FView := BuildZ80View(FData, FOrigin, FSyncPoints, MonoFontName);
    end;
    if FView <> nil then
      RTF := FView.RTF;
    FViewer.LoadRTF(RTF);
    FViewer.SelectText(0, 0);
    FViewer.ScrollTo(0);
  finally
    Screen.Cursor := crDefault;
  end;
end;

function TfrmDataViewer.TopOffset: integer;
begin
  Result := -1;
  if (FView = nil) or (FView.LineCount = 0) then
    exit;
  Result := FView.Lines[FView.LineAt(FViewer.FirstVisiblePosition)].Offset -
    FHeaderShown;
  if Result < 0 then
    Result := 0;
end;

procedure TfrmDataViewer.GoToOffset(Offset: integer; Select: boolean);
var
  Line, Position, Count: integer;
begin
  if (FView = nil) or (FView.LineCount = 0) or (Offset < 0) then
    exit;
  Line := FView.LineOf(Offset + FHeaderShown);
  Position := FView.Lines[Line].Position;
  if Select then
  begin
    Count := 0;
    if Line + 1 < FView.LineCount then
      Count := FView.Lines[Line + 1].Position - Position - 1;
    FViewer.SelectText(Position, Count);
  end;
  FViewer.ScrollTo(Position);
end;

procedure TfrmDataViewer.ModeChange(Sender: TObject);
var
  Top: integer;
begin
  // Both the button losing the choice and the one gaining it report a change
  if FChanging or (FViewer = nil) or not TRadioButton(Sender).Checked then
    exit;
  Top := TopOffset;
  ShowContent;
  GoToOffset(Top, False);
end;

procedure TfrmDataViewer.chkHeaderChange(Sender: TObject);
var
  Top: integer;
begin
  if FChanging or (FViewer = nil) then
    exit;
  Top := TopOffset;
  ShowContent;
  GoToOffset(Top, False);
end;

procedure TfrmDataViewer.edtAddressEditingDone(Sender: TObject);
var
  Address, Top: integer;
begin
  if FChanging or (FViewer = nil) then
    exit;
  if TryParseAddress(edtAddress.Text, Address) and (Address <> FOrigin) then
  begin
    Top := TopOffset;
    FOrigin := Address;
    ShowContent;
    GoToOffset(Top, False);
  end;
  edtAddress.Text := IntToHex(FOrigin, 4);
end;

procedure TfrmDataViewer.DisassembleFrom(Offset: integer);
var
  Idx: integer;
  Known: boolean;
begin
  if (Offset < 0) or (Offset >= Length(FData)) then
    exit;
  Known := False;
  for Idx := 0 to High(FSyncPoints) do
    if FSyncPoints[Idx] = Offset then
      Known := True;
  if not Known then
  begin
    SetLength(FSyncPoints, Length(FSyncPoints) + 1);
    FSyncPoints[High(FSyncPoints)] := Offset;
  end;

  FChanging := True;
  try
    radZ80.Checked := True;
  finally
    FChanging := False;
  end;
  ShowContent;
  GoToOffset(Offset, True);
end;

procedure TfrmDataViewer.btnExecuteClick(Sender: TObject);
var
  Offset: integer;
begin
  Offset := (FExecute - FOrigin) and $FFFF;
  if Offset < Length(FData) then
    DisassembleFrom(Offset)
  else
    MessageDlg(Format('The execute address %.4x is outside the file.',
      [FExecute]), mtInformation, [mbOK], 0);
end;

procedure TfrmDataViewer.ViewerMenu(Position: integer; const Where: TPoint);
begin
  FClicked := -1;
  if FView <> nil then
    FClicked := FView.OffsetAt(Position) - FHeaderShown;
  itmFromHere.Enabled := (FClicked >= 0) and (FClicked < Length(FData));
  popView.PopUp(Where.X, Where.Y);
end;

procedure TfrmDataViewer.itmFromHereClick(Sender: TObject);
begin
  DisassembleFrom(FClicked);
end;

procedure TfrmDataViewer.itmCopyClick(Sender: TObject);
begin
  FViewer.CopyToClipboard;
end;

procedure TfrmDataViewer.itmSelectAllClick(Sender: TObject);
begin
  FViewer.SelectAll;
end;

end.
