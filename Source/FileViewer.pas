unit FileViewer;

{$MODE Delphi}

{
  Disk Image Manager - File content viewer window

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Classes, SysUtils, Forms, Controls,
  DskImage, FileSystem, MGTFileSystem, OpusFileSystem, SinclairBasic,
  AmstradBasic, RTFView, Utils;

type
  TfrmFileViewer = class(TForm)
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FDiskName: string;
    FFileName: string;
    FViewer: TRTFViewer;
    procedure EnsureViewer;
    // Hand RTF to the viewer, or say why there isn't one. EnsureViewer can come
    // back empty handed - the rich edit library may not load, or the window may
    // not be created - and every caller went on to use it regardless.
    procedure ShowRTF(const RTFContent: string);
    procedure UpdateCaption;
  public
    // For a CP/M, MGT or Opus Discovery file
    procedure LoadBasicFile(DiskImage: TDSKDisk; DiskFile: TDiskFile; const DiskName: string);
    procedure LoadStringArrayFile(DiskImage: TDSKDisk; DiskFile: TDiskFile; const DiskName: string);
    procedure LoadTextFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
    property DiskName: string read FDiskName write FDiskName;
    property FileName: string read FFileName write FFileName;
  end;

procedure ShowBasicViewer(DiskImage: TDSKDisk; DiskFile: TDiskFile; const DiskName: string);
procedure ShowStringArrayViewer(DiskImage: TDSKDisk; DiskFile: TDiskFile; const DiskName: string);
procedure ShowTextViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);

implementation

uses
  Windows;

{$R *.lfm}

// A Spectrum decoder set in this machine's monospace font
function NewSpectrumParser: TSinclairBasicParser;
begin
  Result := TSinclairBasicParser.Create(sbMode128K);
  Result.FontName := MonoFontName;
end;

procedure ShowBasicViewer(DiskImage: TDSKDisk; DiskFile: TDiskFile; const DiskName: string);
var
  Viewer: TfrmFileViewer;
begin
  Viewer := TfrmFileViewer.Create(Application);
  // Nothing but this holds the form until it is shown, so a file that
  // will not decode has to take the window with it rather than leave it
  // owned by the application and never seen again
  try
    Viewer.LoadBasicFile(DiskImage, DiskFile, DiskName);
  except
    Viewer.Free;
    raise;
  end;
  Viewer.Show;
end;

procedure ShowStringArrayViewer(DiskImage: TDSKDisk; DiskFile: TDiskFile; const DiskName: string);
var
  Viewer: TfrmFileViewer;
begin
  Viewer := TfrmFileViewer.Create(Application);
  // Nothing but this holds the form until it is shown, so a file that
  // will not decode has to take the window with it rather than leave it
  // owned by the application and never seen again
  try
    Viewer.LoadStringArrayFile(DiskImage, DiskFile, DiskName);
  except
    Viewer.Free;
    raise;
  end;
  Viewer.Show;
end;

procedure ShowTextViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  Viewer: TfrmFileViewer;
begin
  Viewer := TfrmFileViewer.Create(Application);
  // Nothing but this holds the form until it is shown, so a file that
  // will not decode has to take the window with it rather than leave it
  // owned by the application and never seen again
  try
    Viewer.LoadTextFile(DiskImage, DiskFile, DiskName);
  except
    Viewer.Free;
    raise;
  end;
  Viewer.Show;
end;

procedure TfrmFileViewer.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  // Each viewed file opens a fresh modeless instance, so release it on close
  CloseAction := caFree;
end;

procedure TfrmFileViewer.FormCreate(Sender: TObject);
begin
  FDiskName := '';
  FFileName := '';
  FViewer := nil;
end;

procedure TfrmFileViewer.EnsureViewer;
var
  ParentWnd: HWND;
begin
  if FViewer <> nil then
    Exit;

  // Get the native Win32 handle of this form
  if not HandleAllocated then
    HandleNeeded;
  ParentWnd := HWND(Handle);
  if ParentWnd = 0 then
    Exit;

  FViewer := TRTFViewer.Create(ParentWnd);
  FViewer.SetBounds(0, 0, ClientWidth, ClientHeight);
end;

procedure TfrmFileViewer.FormResize(Sender: TObject);
begin
  if FViewer <> nil then
    FViewer.SetBounds(0, 0, ClientWidth, ClientHeight);
end;

procedure TfrmFileViewer.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FViewer);
end;

procedure TfrmFileViewer.ShowRTF(const RTFContent: string);
begin
  if FViewer = nil then
    raise Exception.Create(
      'Could not create the text viewer. riched20.dll may be missing.');
  FViewer.LoadRTF(RTFContent);
end;

procedure TfrmFileViewer.UpdateCaption;
begin
  if (FDiskName <> '') and (FFileName <> '') then
    Caption := Format('%s - %s', [FFileName, FDiskName])
  else if FFileName <> '' then
    Caption := FFileName
  else
    Caption := 'File Viewer';
end;

procedure TfrmFileViewer.LoadBasicFile(DiskImage: TDSKDisk; DiskFile: TDiskFile; const DiskName: string);
var
  SinclairParser: TSinclairBasicParser;
  AmstradParser: TAmstradBasicParser;
  RTFText: string;
begin
  FDiskName := DiskName;
  FFileName := DiskFile.FileName;
  UpdateCaption;

  EnsureViewer;

  if (DiskFile is TCPMFile) and (TCPMFile(DiskFile).HeaderType = 'AMSDOS') then
  begin
    AmstradParser := TAmstradBasicParser.Create;
    try
      AmstradParser.FontName := MonoFontName;
      RTFText := AmstradParser.DecodeFileRTF(DiskImage, TCPMFile(DiskFile));
    finally
      AmstradParser.Free;
    end;
  end
  else
  begin
    SinclairParser := NewSpectrumParser;
    try
      if DiskFile is TOpusFile then
        RTFText := SinclairParser.DecodeRTF(TOpusFile(DiskFile).BasicProgram)
      else if DiskFile is TMGTFile then
        RTFText := SinclairParser.DecodeRTF(TMGTFile(DiskFile).BasicProgram)
      else
        RTFText := SinclairParser.DecodeFileRTF(DiskImage, TCPMFile(DiskFile));
    finally
      SinclairParser.Free;
    end;
  end;

  if RTFText = '' then
    RTFText := '{\rtf1\ansi (Unable to decode BASIC program)}';
  ShowRTF(RTFText);
end;

procedure TfrmFileViewer.LoadStringArrayFile(DiskImage: TDSKDisk; DiskFile: TDiskFile; const DiskName: string);
var
  Parser: TSinclairBasicParser;
  RTFText: string;
begin
  FDiskName := DiskName;
  FFileName := DiskFile.FileName;
  UpdateCaption;

  EnsureViewer;

  Parser := NewSpectrumParser;
  try
    if DiskFile is TCPMFile then
      RTFText := Parser.DecodeStringArrayFileRTF(DiskImage, TCPMFile(DiskFile))
    else
      RTFText := Parser.DecodeStringArrayRTF(DiskFile.GetData(False));
  finally
    Parser.Free;
  end;

  if RTFText = '' then
    RTFText := '{\rtf1\ansi (Unable to decode string array)}';
  ShowRTF(RTFText);
end;

procedure TfrmFileViewer.LoadTextFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  Parser: TSinclairBasicParser;
  RTFText: string;
begin
  FDiskName := DiskName;
  FFileName := DiskFile.FileName;
  UpdateCaption;

  EnsureViewer;

  Parser := NewSpectrumParser;
  try
    RTFText := Parser.DecodeTextFileRTF(DiskImage, DiskFile);
  finally
    Parser.Free;
  end;

  if RTFText = '' then
    RTFText := '{\rtf1\ansi (Unable to decode file)}';
  ShowRTF(RTFText);
end;

end.
