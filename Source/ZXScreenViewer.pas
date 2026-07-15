unit ZXScreenViewer;

{$MODE Delphi}

{
  Disk Image Manager - ZX Spectrum SCREEN$ viewer window

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Classes, SysUtils, Types, Forms, Controls, Graphics, ExtCtrls, ComCtrls,
  StdCtrls, Buttons, Menus, DskImage, FileSystem, Utils, SpectrumScreen;

type

  { TfrmZXScreenViewer }

  TfrmZXScreenViewer = class(TForm)
    btnSave: TButton;
    btnZoom: TSpeedButton;
    imlToolbar: TImageList;
    imgScreen: TImage;
    popZoom: TPopupMenu;
    toolbar: TPanel;
    tmrFlash: TTimer;
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure tmrFlashTimer(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
  private
    FDiskName: string;
    FFileName: string;
    FScreenData: array of byte;
    FZoom: integer;
    FHasFlash: boolean;
    FFlashPhase: boolean;
    FBitmapNormal: TBitmap;
    FBitmapFlash: TBitmap;
    procedure BuildZoomMenu;
    procedure btnZoomClick(Sender: TObject);
    procedure ZoomMenuClick(Sender: TObject);
    procedure UpdateZoomChecks;
    procedure UpdateCaption;
    procedure RenderScreen;
    procedure RenderBothPhases;
    procedure SetZoom(NewZoom: integer);
  public
    destructor Destroy; override;
    procedure LoadScreenFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
    property DiskName: string read FDiskName write FDiskName;
    property FileName: string read FFileName write FFileName;
  end;

procedure ShowZXScreenViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);

implementation

// Note: editing ZXScreenViewer.lfm alone will not refresh the embedded form
// resource unless this unit also recompiles, so keep them changing together.
{$R *.lfm}

procedure ShowZXScreenViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  Viewer: TfrmZXScreenViewer;
begin
  Viewer := TfrmZXScreenViewer.Create(Application);
  Viewer.LoadScreenFile(DiskImage, DiskFile, DiskName);
  Viewer.Show;
end;

procedure TfrmZXScreenViewer.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Each viewed screen opens a fresh modeless instance, so release it on close
  CloseAction := caFree;
end;

procedure TfrmZXScreenViewer.FormCreate(Sender: TObject);
begin
  FDiskName := '';
  FFileName := '';
  FHasFlash := False;
  FFlashPhase := False;
  SetLength(FScreenData, 0);

  // Bitmaps for flash animation
  FBitmapNormal := TBitmap.Create;
  FBitmapFlash := TBitmap.Create;

  BuildZoomMenu;

  // A TSpeedButton's PopupMenu only opens on right-click, so also open the
  // zoom menu on a normal left-click.
  btnZoom.OnClick := btnZoomClick;
end;

destructor TfrmZXScreenViewer.Destroy;
begin
  tmrFlash.Enabled := False;
  FBitmapNormal.Free;
  FBitmapFlash.Free;
  inherited Destroy;
end;

procedure TfrmZXScreenViewer.BuildZoomMenu;
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
    Item.OnClick := ZoomMenuClick;
    popZoom.Items.Add(Item);
  end;
end;

procedure TfrmZXScreenViewer.btnZoomClick(Sender: TObject);
var
  P: TPoint;
begin
  P := btnZoom.ControlToScreen(Point(0, btnZoom.Height));
  popZoom.PopUp(P.X, P.Y);
end;

procedure TfrmZXScreenViewer.ZoomMenuClick(Sender: TObject);
begin
  SetZoom(TMenuItem(Sender).Tag);
end;

procedure TfrmZXScreenViewer.UpdateZoomChecks;
var
  I: integer;
begin
  for I := 0 to popZoom.Items.Count - 1 do
    popZoom.Items[I].Checked := popZoom.Items[I].Tag = FZoom;
end;

procedure TfrmZXScreenViewer.UpdateCaption;
begin
  Caption := Format('%s on %s x%d', [FFileName, FDiskName, FZoom]);
end;

procedure TfrmZXScreenViewer.SetZoom(NewZoom: integer);
begin
  if NewZoom = FZoom then Exit;

  FZoom := NewZoom;
  UpdateCaption;

  // Re-render both phases at new zoom level
  if FHasFlash then
    RenderBothPhases
  else
    RenderScreen;

  UpdateZoomChecks;
end;

procedure TfrmZXScreenViewer.RenderBothPhases;
var
  NewWidth, NewHeight: integer;
begin
  if Length(FScreenData) = 0 then Exit;

  NewWidth := ScreenWidth * FZoom;
  NewHeight := ScreenHeight * FZoom;

  // Render normal phase
  FBitmapNormal.Width := NewWidth;
  FBitmapNormal.Height := NewHeight;
  FBitmapNormal.PixelFormat := pf24bit;
  TSpectrumScreen.RenderToBitmap(FScreenData, FBitmapNormal, FZoom, False);

  // Render flash phase (with ink/paper swapped on flash attributes)
  FBitmapFlash.Width := NewWidth;
  FBitmapFlash.Height := NewHeight;
  FBitmapFlash.PixelFormat := pf24bit;
  TSpectrumScreen.RenderToBitmap(FScreenData, FBitmapFlash, FZoom, True);

  // Show the current phase
  if FFlashPhase then
    imgScreen.Picture.Assign(FBitmapFlash)
  else
    imgScreen.Picture.Assign(FBitmapNormal);

  // Update image and form size
  imgScreen.Width := NewWidth;
  imgScreen.Height := NewHeight;
  ClientWidth := NewWidth;
  ClientHeight := NewHeight + toolbar.Height;
end;

procedure TfrmZXScreenViewer.RenderScreen;
var
  NewWidth, NewHeight: integer;
begin
  if Length(FScreenData) = 0 then Exit;

  NewWidth := ScreenWidth * FZoom;
  NewHeight := ScreenHeight * FZoom;

  // Create bitmap with correct size
  imgScreen.Picture.Bitmap.Width := NewWidth;
  imgScreen.Picture.Bitmap.Height := NewHeight;
  imgScreen.Picture.Bitmap.PixelFormat := pf24bit;

  // Render the screen (no flash phase for non-flashing screens)
  TSpectrumScreen.RenderToBitmap(FScreenData, imgScreen.Picture.Bitmap, FZoom, False);

  // Update image size
  imgScreen.Width := NewWidth;
  imgScreen.Height := NewHeight;

  // Update form size to fit content
  ClientWidth := NewWidth;
  ClientHeight := NewHeight + toolbar.Height;
end;

procedure TfrmZXScreenViewer.LoadScreenFile(DiskImage: TDSKDisk;
  DiskFile: TCPMFile; const DiskName: string);
var
  FileData: TDiskByteArray;
  DataSize: integer;
begin
  FDiskName := DiskName;
  FFileName := DiskFile.FileName;

  // Get file data without header
  FileData := DiskFile.GetData(False);
  DataSize := Length(FileData);

  // Validate screen size
  if not TSpectrumScreen.IsValidScreenSize(DataSize) then
  begin
    Caption := 'Invalid screen file';
    Exit;
  end;

  // Copy data
  SetLength(FScreenData, DataSize);
  Move(FileData[0], FScreenData[0], DataSize);

  // Check for flash attributes
  FHasFlash := TSpectrumScreen.HasFlashAttribute(FScreenData);
  FFlashPhase := False;

  // Enable timer only if flash attributes are present
  tmrFlash.Enabled := FHasFlash;

  SetZoom(2);
end;

procedure TfrmZXScreenViewer.tmrFlashTimer(Sender: TObject);
begin
  // Toggle flash phase
  FFlashPhase := not FFlashPhase;

  // Swap displayed bitmap
  if FFlashPhase then
    imgScreen.Picture.Assign(FBitmapFlash)
  else
    imgScreen.Picture.Assign(FBitmapNormal);
end;

procedure TfrmZXScreenViewer.btnSaveClick(Sender: TObject);
var
  Bitmap: TBitmap;
begin
  if Length(FScreenData) = 0 then
    Exit;

  // Render at native resolution (zoom 1) in the currently shown flash phase.
  Bitmap := TBitmap.Create;
  try
    Bitmap.Width := ScreenWidth;
    Bitmap.Height := ScreenHeight;
    Bitmap.PixelFormat := pf24bit;
    TSpectrumScreen.RenderToBitmap(FScreenData, Bitmap, 1, FFlashPhase);
    SaveBitmapWithDialog(Self, Bitmap, ChangeFileExt(ExtractFileName(FFileName), '.png'));
  finally
    Bitmap.Free;
  end;
end;

end.
