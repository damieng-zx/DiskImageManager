unit CPCScreenViewer;

{$MODE Delphi}

{
  Disk Image Manager - Amstrad CPC screen viewer window

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, ExtCtrls, ComCtrls,
  StdCtrls, Buttons, Menus, DskImage, FileSystem, Utils, AmstradScreen;

type

  { TfrmCPCScreenViewer }

  TfrmCPCScreenViewer = class(TForm)
    btnSave: TButton;
    btnZoom: TSpeedButton;
    cmbMode: TComboBox;
    imlToolbar: TImageList;
    imgScreen: TImage;
    lblMode: TLabel;
    popZoom: TPopupMenu;
    toolbar: TPanel;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure cmbModeChange(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FDiskName: string;
    FFileName: string;
    FImage: TAmstradImage;
    FZoom: integer;
    procedure BuildZoomMenu;
    procedure btnZoomClick(Sender: TObject);
    procedure ZoomMenuClick(Sender: TObject);
    procedure UpdateCaption;
    procedure RenderScreen;
  public
    procedure LoadScreenFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
    property DiskName: string read FDiskName write FDiskName;
    property FileName: string read FFileName write FFileName;
  end;

procedure ShowCPCScreenViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);

implementation

// Note: editing CPCScreenViewer.lfm alone will not refresh the embedded form
// resource unless this unit also recompiles, so keep them changing together.
{$R *.lfm}

procedure ShowCPCScreenViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  Viewer: TfrmCPCScreenViewer;
begin
  Viewer := TfrmCPCScreenViewer.Create(Application);
  Viewer.LoadScreenFile(DiskImage, DiskFile, DiskName);
  Viewer.Show;
end;

procedure TfrmCPCScreenViewer.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Each viewed screen opens a fresh modeless instance, so release it on close
  CloseAction := caFree;
end;

procedure TfrmCPCScreenViewer.FormCreate(Sender: TObject);
begin
  FDiskName := '';
  FFileName := '';
  FZoom := 1;
  SetLength(FImage.Data, 0);
  BuildZoomMenu;

  // A TSpeedButton's PopupMenu only opens on right-click, so also open the
  // zoom menu on a normal left-click.
  btnZoom.OnClick := btnZoomClick;
end;

procedure TfrmCPCScreenViewer.UpdateCaption;
begin
  Caption := Format('%s on %s x%d', [FFileName, FDiskName, FZoom]);
  if FImage.IsWindow then
    Caption := Caption + ' (window)';
end;

procedure TfrmCPCScreenViewer.RenderScreen;
var
  ClientW: integer;
begin
  if Length(FImage.Data) = 0 then
    Exit;

  TAmstradScreen.RenderImage(FImage, imgScreen.Picture.Bitmap, FZoom);

  imgScreen.Width := imgScreen.Picture.Bitmap.Width;
  imgScreen.Height := imgScreen.Picture.Bitmap.Height;

  // A small window can be narrower than the toolbar; keep room for its controls.
  ClientW := imgScreen.Picture.Bitmap.Width;
  if ClientW < 240 then
    ClientW := 240;
  ClientWidth := ClientW;
  ClientHeight := imgScreen.Picture.Bitmap.Height + toolbar.Height;

  UpdateCaption;
end;

procedure TfrmCPCScreenViewer.LoadScreenFile(DiskImage: TDSKDisk;
  DiskFile: TCPMFile; const DiskName: string);
begin
  FDiskName := DiskName;
  FFileName := DiskFile.FileName;

  // Decode the file (AMSDOS header stripped, MJH compression expanded) into a
  // full screen or window image with a guessed mode. Empty means unrecognised.
  if not TAmstradScreen.LoadImage(DiskFile.GetData(False), FImage) then
  begin
    Caption := 'Invalid screen file';
    Exit;
  end;

  // Reflect the guessed mode; the user can still override via the dropdown.
  // Setting ItemIndex in code does not fire OnChange.
  cmbMode.ItemIndex := Ord(FImage.Mode);

  RenderScreen;
end;

procedure TfrmCPCScreenViewer.BuildZoomMenu;
var
  I: integer;
  Item: TMenuItem;
begin
  for I := 1 to 4 do
  begin
    Item := TMenuItem.Create(popZoom);
    Item.Caption := Format('%d' + #$C3#$97, [I]);  // e.g. "2x" with a multiply sign
    Item.Tag := I;
    Item.RadioItem := True;
    Item.Checked := I = FZoom;
    Item.OnClick := ZoomMenuClick;
    popZoom.Items.Add(Item);
  end;
end;

procedure TfrmCPCScreenViewer.btnZoomClick(Sender: TObject);
var
  P: TPoint;
begin
  P := btnZoom.ControlToScreen(Point(0, btnZoom.Height));
  popZoom.PopUp(P.X, P.Y);
end;

procedure TfrmCPCScreenViewer.ZoomMenuClick(Sender: TObject);
var
  I: integer;
begin
  FZoom := TMenuItem(Sender).Tag;
  for I := 0 to popZoom.Items.Count - 1 do
    popZoom.Items[I].Checked := popZoom.Items[I].Tag = FZoom;
  RenderScreen;
end;

procedure TfrmCPCScreenViewer.cmbModeChange(Sender: TObject);
begin
  case cmbMode.ItemIndex of
    0: FImage.Mode := amMode0;
    1: FImage.Mode := amMode1;
    2: FImage.Mode := amMode2;
  end;
  RenderScreen;
end;

procedure TfrmCPCScreenViewer.btnSaveClick(Sender: TObject);
var
  Bitmap: TBitmap;
begin
  if Length(FImage.Data) = 0 then
    Exit;

  // Render at native resolution (zoom 1) regardless of the on-screen zoom.
  Bitmap := TBitmap.Create;
  try
    TAmstradScreen.RenderImage(FImage, Bitmap, 1);
    SaveBitmapWithDialog(Self, Bitmap, ChangeFileExt(ExtractFileName(FFileName), '.png'));
  finally
    Bitmap.Free;
  end;
end;

end.
