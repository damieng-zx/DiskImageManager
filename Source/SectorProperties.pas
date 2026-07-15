unit SectorProperties;

{$MODE Delphi}

{
  Disk Image Manager -  Sector properties window

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DskImage, Utils,
  SysUtils, Classes, Forms, StdCtrls, ComCtrls, ExtCtrls, CheckLst, Dialogs, Graphics;

type

  { TfrmSectorProperties }

  TfrmSectorProperties = class(TForm)
    bevIdentity: TBevel;
    edtIndexPos: TEdit;
    lblIndexPos: TLabel;
    pnlTab: TPanel;
    pnlButtons: TPanel;
    pagTabs: TPageControl;
    tabSector: TTabSheet;
    btnOK: TButton;
    btnCancel: TButton;
    btnApply: TButton;
    lblStatus: TLabel;
    lblSize: TLabel;
    lblImage: TLabel;
    cklFDC2: TCheckListBox;
    cklFDC1: TCheckListBox;
    lblFDC1: TLabel;
    lblFDC2: TLabel;
    lblSectorID: TLabel;
    edtSectorID: TEdit;
    udSectorID: TUpDown;
    cboStatus: TComboBox;
    edtSize: TEdit;
    udSize: TUpDown;
    lblPhysical: TLabel;
    edtImage: TEdit;
    edtPhysical: TEdit;
    bevDetails: TBevel;
    bevFDC: TBevel;
    lblFDC: TLabel;
    lblDetails: TLabel;
    lblIdentity: TLabel;
    lblFill: TLabel;
    edtFill: TEdit;
    udFill: TUpDown;
    lblPad: TLabel;
    edtPad: TEdit;
    udPad: TUpDown;
    lblFDCSize: TLabel;
    edtFDCSize: TEdit;
    udFDCSize: TUpDown;
    procedure btnCancelClick(Sender: TObject);
    procedure btnApplyClick(Sender: TObject);
    procedure btnOKClick(Sender: TObject);
    procedure cboStatusChange(Sender: TObject);
    procedure edtSizeChange(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  private
    FSector: TDSKSector;
    SecStat: TDSKSectorStatus;
    procedure MakeChanges;
    procedure UpdateFill;
    procedure UpdatePad;
  public
    constructor Create(AOwner: TComponent; Sector: TDSKSector); reintroduce;
    procedure Refresh;
    function ParentImage: TDSKImage;
    procedure Detach;
  end;

var
  frmSectorProperties: TfrmSectorProperties;

implementation

uses Main;

{$R *.lfm}

constructor TfrmSectorProperties.Create(AOwner: TComponent; Sector: TDSKSector);
var
  SIdx: TDSKSectorStatus;
begin
  inherited Create(AOwner);
  FSector := Sector;

  cboStatus.Items.Clear;
  for SIdx := ssUnformatted to ssFormattedInUse do
    cboStatus.Items.Add(DSKSectorStatus[SIdx]);

  Refresh;
  Show;
end;

procedure TfrmSectorProperties.Refresh;
var
  FIdx: integer;
begin
  if FSector = nil then exit;

  // Identity
  edtImage.Text := ExtractFileName(FSector.ParentTrack.ParentSide.ParentDisk.ParentImage.FileName);
  edtPhysical.Text := 'Side ' + IntToStr(FSector.Side + 1) + ' > Track ' + IntToStr(FSector.Track) +
    ' > Sector ' + IntToStr(FSector.Sector);
  Caption := edtImage.Text + ' > ' + edtPhysical.Text;

  // Details
  udSectorID.Position := FSector.ID;
  edtIndexPos.Text := StrInt(FSector.IndexPointOffset);
  udFDCSize.Position := FSector.FDCSize;
  udSize.Position := FSector.DataSize;
  if (FSector.GetFillByte >= 0) then
    udFill.Position := FSector.ParentTrack.Filler
  else
    udFill.Position := FSector.GetFillByte;
  udPad.Position := udFill.Position;

  SecStat := FSector.Status;
  cboStatus.ItemIndex := Ord(FSector.Status);

  // FDC
  for FIdx := 0 to 7 do
  begin
    cklFDC1.Checked[FIdx] := (FSector.FDCStatus[1] and Power2[FIdx + 1]) = Power2[FIdx + 1];
    cklFDC2.Checked[FIdx] := (FSector.FDCStatus[2] and Power2[FIdx + 1]) = Power2[FIdx + 1];
  end;
end;

procedure TfrmSectorProperties.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Each Sector Properties opens a fresh modeless instance, so release it on close
  CloseAction := caFree;
end;

procedure TfrmSectorProperties.btnCancelClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmSectorProperties.btnApplyClick(Sender: TObject);
begin
  MakeChanges;
end;

procedure TfrmSectorProperties.btnOKClick(Sender: TObject);
begin
  MakeChanges;
  Close;
end;

// The image this window describes part of, or nil once it has let go
function TfrmSectorProperties.ParentImage: TDSKImage;
begin
  if FSector = nil then
    Result := nil
  else
    Result := FSector.ParentTrack.ParentSide.ParentDisk.ParentImage;
end;

// The sector is about to be freed along with its image, so drop it and close.
// Nulling it matters as well as closing: the close only releases this window on
// the next idle, and Apply until then would write through the freed sector.
procedure TfrmSectorProperties.Detach;
begin
  FSector := nil;
  Close;
end;

procedure TfrmSectorProperties.MakeChanges;
var
  FIdx: integer;
  OldLength: word;
  SecData: array[0..MaxSectorSize] of byte;
begin
  if FSector = nil then exit;

  if frmMain.ConfirmChange('change', 'sector') then
    with FSector do
    begin
      // Details
      ID := udSectorID.Position;
      IndexPointOffset := IntStr(edtIndexPos.Text);

      // Status
      if (SecStat = ssFormattedBlank) or (SecStat = ssFormattedFilled) then
        FillSector(udFill.Position);

      // Changing size?
      if DataSize <> word(udSize.Position) then
      begin
        if (DataSize < word(udSize.Position)) and (DataSize > 0) then
        begin
          Move(Data, SecData, DataSize);
          OldLength := DataSize;
          DataSize := word(udSize.Position);
          FillSector(udPad.Position);
          Move(SecData, Data, OldLength);
        end
        else
          DataSize := udSize.Position;
      end;

      // FDC data Size
      if FDCSize <> byte(udFDCSize.Position) then
        FDCSize := byte(udFDCSize.Position);

      // FDC status
      FDCStatus[1] := 0;
      for FIdx := 0 to 7 do
        if cklFDC1.Checked[FIdx] then
          FDCStatus[1] := FDCStatus[1] + Power2[FIdx + 1];

      FDCStatus[2] := 0;
      for FIdx := 0 to 7 do
        if cklFDC2.Checked[FIdx] then FDCStatus[2] := FDCStatus[2] + Power2[FIdx + 1];

    end;
  frmMain.RefreshList;
end;

procedure TfrmSectorProperties.cboStatusChange(Sender: TObject);
begin
  SecStat := TDSKSectorStatus(cboStatus.ItemIndex);

  if (SecStat = ssFormattedInUse) and (FSector.Status <> ssFormattedInUse) then
  begin
    ShowMessage('Sector can not be made in-use when it was not previously');
    cboStatus.ItemIndex := Ord(FSector.Status);
  end;

  if SecStat = ssUnformatted then
    udSize.Position := 0
  else
  if udSize.Position = 0 then
    if FSector.DataSize <> 0 then
      udSize.Position := FSector.DataSize
    else
      udSize.Position := FSector.ParentTrack.SectorSize * 256;

  UpdateFill;
end;

procedure TfrmSectorProperties.edtSizeChange(Sender: TObject);
begin
  if (udSize.Position > 0) and (FSector.DataSize = 0) then
    cboStatus.ItemIndex := Ord(ssFormattedBlank);
  if udSize.Position = 0 then
    cboStatus.ItemIndex := Ord(ssUnformatted);
  UpdatePad;
end;

procedure TfrmSectorProperties.UpdatePad;
var
  ShowPad: boolean;
begin
  ShowPad := (word(udSize.Position) > FSector.DataSize) and (FSector.DataSize > 0);
  lblPad.Visible := ShowPad;
  edtPad.Visible := ShowPad;
  udPad.Visible := ShowPad;
end;

procedure TfrmSectorProperties.UpdateFill;
var
  ShowFill: boolean;
begin
  ShowFill := ((SecStat = ssFormattedBlank) or (SecStat = ssFormattedFilled)) or (word(udSize.Position) > FSector.DataSize);
  if (cboStatus.ItemIndex = 1) then
    udFill.Position := FSector.ParentTrack.Filler;
  lblFill.Visible := ShowFill;
  edtFill.Visible := ShowFill;
  udFill.Visible := ShowFill;
end;

end.
