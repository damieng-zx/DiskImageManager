unit Options;

{$MODE Delphi}

{
  Disk Image Manager -  Options window

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DiskMap, Utils, Settings,
  Graphics, Forms, ComCtrls, StdCtrls, Controls, ExtCtrls, Dialogs, StrUtils, Classes;

type

  { TfrmOptions }

  TfrmOptions = class(TForm)
    btnFontStrings: TButton;
    cboStringSorting: TComboBox;
    cboOpenView: TComboBox;
    cboHighASCII: TComboBox;
    chkExpandRestoredFiles: TCheckBox;
    edtFontStrings: TEdit;
    edtMinString: TEdit;
    lblDefaultView: TLabel;
    lblFontStringsLabel: TLabel;
    lblMapping: TLabel;
    lblStringSorting: TLabel;
    lblMinStringLabel: TLabel;
    pnlButtons: TPanel;
    pagOptions: TPageControl;
    tabMain: TTabSheet;
    btnOK: TButton;
    btnCancel: TButton;
    tabSectors: TTabSheet;
    tabDiskMap: TTabSheet;
    lblFontMainLabel: TLabel;
    dlgFont: TFontDialog;
    edtFontMain: TEdit;
    btnFontMain: TButton;
    DiskMap: TSpinDiskMap;
    lblFontMapLabel: TLabel;
    edtFontMap: TEdit;
    btnFontMap: TButton;
    lblFontSectorLabel: TLabel;
    edtFontSector: TEdit;
    btnFontSector: TButton;
    lblTrackMarksLabel: TLabel;
    tabStrings: TTabSheet;
    udTrackMarks: TUpDown;
    edtTrackMarks: TEdit;
    lblBytesLabel: TLabel;
    edtBytes: TEdit;
    udBytes: TUpDown;
    lblNonDisplayLabel: TLabel;
    edtNonDisplay: TEdit;
    chkRestoreWindow: TCheckBox;
    chkRestoreWorkspace: TCheckBox;
    btnReset: TButton;
    chkDarkBlankSectors: TCheckBox;
    cbxBack: TColorButton;
    cbxGrid: TColorButton;
    tabSaving: TTabSheet;
    chkWarnConversionProblems: TCheckBox;
    chkSaveRemoveEmptyTracks: TCheckBox;
    lblMapSave: TLabel;
    edtMapX: TEdit;
    edtMapY: TEdit;
    lblBy: TLabel;
    udMapX: TUpDown;
    udMapY: TUpDown;
    chkWarnSectorChange: TCheckBox;
    pnlTabs: TPanel;
    udMinString: TUpDown;
    procedure btnFontStringsClick(Sender: TObject);
    procedure cbxBackColorChanged(Sender: TObject);
    procedure btnFontMainClick(Sender: TObject);
    procedure btnFontMapClick(Sender: TObject);
    procedure btnFontSectorClick(Sender: TObject);
    procedure cbxGridColorChanged(Sender: TObject);
    procedure edtTrackMarksChange(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure chkDarkBlankSectorsClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
  private
    FontMain, FontSector, FontStrings: TFont;
    Settings: TSettings;
    procedure Read;
    procedure Write;
  public
    constructor Create(Owner: TForm; Settings: TSettings); reintroduce;
    destructor Destroy; override;
    function Show: boolean;
  end;

const
  HighASCIIOptions: array[0..3] of string = ('None', '437', '850', '1252');
  StringSortOptions: array[0..2] of string = ('None', 'Alpha', 'Size');

var
  frmOptions: TfrmOptions;

implementation

{$R *.lfm}

constructor TfrmOptions.Create(Owner: TForm; Settings: TSettings);
begin
  inherited Create(Owner);
  self.Settings := Settings;
  // The pending choices, held here until OK writes them back to the settings.
  // They are assigned into so that neither the settings nor the font dialog
  // ever hands over ownership of a font.
  FontMain := TFont.Create;
  FontSector := TFont.Create;
  FontStrings := TFont.Create;
end;

destructor TfrmOptions.Destroy;
begin
  FontMain.Free;
  FontSector.Free;
  FontStrings.Free;
  inherited Destroy;
end;

procedure TfrmOptions.cbxBackColorChanged(Sender: TObject);
begin
  DiskMap.Color := cbxBack.ButtonColor;
end;

procedure TfrmOptions.btnFontStringsClick(Sender: TObject);
begin
  with dlgFont do
  begin
    Font := FontStrings;
    if Execute then
    begin
      edtFontStrings.Text := FontHumanReadable(Font);
      FontStrings.Assign(Font);
    end;
  end;
end;

procedure TfrmOptions.btnFontMainClick(Sender: TObject);
begin
  with dlgFont do
  begin
    Font := FontMain;
    Options := Options - [fdFixedPitchOnly];
    if Execute then
    begin
      edtFontMain.Text := FontHumanReadable(Font);
      FontMain.Assign(Font);
    end;
  end;
end;

procedure TfrmOptions.btnFontMapClick(Sender: TObject);
begin
  with dlgFont do
  begin
    Font := DiskMap.Font;
    Options := Options - [fdFixedPitchOnly];
    if Execute then
    begin
      edtFontMap.Text := FontHumanReadable(Font);
      DiskMap.Font := Font;
    end;
  end;
end;

procedure TfrmOptions.btnFontSectorClick(Sender: TObject);
begin
  with dlgFont do
  begin
    Font := FontSector;
    Options := Options + [fdFixedPitchOnly];
    if Execute then
    begin
      edtFontSector.Text := FontHumanReadable(Font);
      FontSector.Assign(Font);
    end;
  end;
end;

procedure TfrmOptions.cbxGridColorChanged(Sender: TObject);
begin
  DiskMap.GridColor := cbxGrid.ButtonColor;
end;

procedure TfrmOptions.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Each View > Options creates a fresh instance, so release it on close. This
  // is safe despite Show reading the controls after ShowModal returns: caFree
  // defers to Application.ReleaseComponent, which frees on the next idle.
  CloseAction := caFree;
end;

function TfrmOptions.Show: boolean;
begin
  pagOptions.ActivePageIndex := 0;
  Read;
  Result := ShowModal = mrOk;
  if Result then
  begin
    Write;
    Settings.Apply;
  end;
end;

procedure TfrmOptions.Read;
begin
  with Settings do
  begin
    FontMain.Assign(WindowFont);
    edtFontMain.Text := FontHumanReadable(WindowFont);

    FontSector.Assign(SectorFont);
    edtFontSector.Text := FontHumanReadable(SectorFont);

    DiskMap.Font := DiskMapFont;
    edtFontMap.Text := FontHumanReadable(DiskMapFont);

    FontStrings.Assign(StringsFont);
    edtFontStrings.Text := FontHumanReadable(StringsFont);

    chkRestoreWindow.Checked := RestoreWindow;
    chkRestoreWorkspace.Checked := RestoreWorkspace;
    udBytes.Position := BytesPerLine;
    udTrackMarks.Position := DiskMapTrackMark;
    chkDarkBlankSectors.Checked := DarkBlankSectors;
    edtNonDisplay.Text := UnknownASCII;
    cboHighASCII.ItemIndex := IndexStr(Mapping, HighASCIIOptions);

    cbxBack.ButtonColor := DiskMapBackgroundColor;
    cbxGrid.ButtonColor := DiskMapGridColor;
    chkWarnConversionProblems.Checked := WarnConversionProblems;
    chkWarnSectorChange.Checked := WarnSectorChange;
    chkSaveRemoveEmptyTracks.Checked := RemoveEmptyTracks;
    udMapX.Position := SaveDiskMapWidth;
    udMapY.Position := SaveDiskMapHeight;
    cboOpenView.Text := OpenView;
    udMinString.Position := StringMinLength;
    cboStringSorting.ItemIndex := IndexStr(StringSort, StringSortOptions);
  end;
end;

procedure TfrmOptions.Write;
begin
  with Settings do
  begin
    WindowFont.Assign(FontMain);
    SectorFont.Assign(FontSector);
    DiskMapFont.Assign(DiskMap.Font);
    StringsFont.Assign(FontStrings);

    DiskMapBackgroundColor := cbxBack.ButtonColor;
    DarkBlankSectors := chkDarkBlankSectors.Checked;
    DiskMapGridColor := cbxGrid.ButtonColor;
    DiskMapTrackMark := udTrackMarks.Position;
    RestoreWindow := chkRestoreWindow.Checked;
    BytesPerLine := udBytes.Position;
    UnknownASCII := edtNonDisplay.Text;
    Mapping := HighASCIIOptions[cboHighASCII.ItemIndex];
    RestoreWorkspace := chkRestoreWorkspace.Checked;
    WarnConversionProblems := chkWarnConversionProblems.Checked;
    WarnSectorChange := chkWarnSectorChange.Checked;
    RemoveEmptyTracks := chkSaveRemoveEmptyTracks.Checked;
    SaveDiskMapWidth := udMapX.Position;
    SaveDiskMapHeight := udMapY.Position;
    OpenView := cboOpenView.Text;
  end;
end;

procedure TfrmOptions.edtTrackMarksChange(Sender: TObject);
begin
  DiskMap.TrackMark := udTrackMarks.Position;
end;

procedure TfrmOptions.btnResetClick(Sender: TObject);
begin
  Settings.Reset;
  Read;
end;

procedure TfrmOptions.chkDarkBlankSectorsClick(Sender: TObject);
begin
  Settings.DarkBlankSectors := chkDarkBlankSectors.Checked;
end;

end.
