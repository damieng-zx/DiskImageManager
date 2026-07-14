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
  DskImage, FileSystem, SinclairBasic, AmstradBasic, RTFView;

type
  TfrmFileViewer = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FDiskName: string;
    FFileName: string;
    FViewer: TRTFViewer;
    procedure EnsureViewer;
    procedure UpdateCaption;
  public
    procedure LoadBasicFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
    procedure LoadStringArrayFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
    procedure LoadTextFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
    property DiskName: string read FDiskName write FDiskName;
    property FileName: string read FFileName write FFileName;
  end;

procedure ShowBasicViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
procedure ShowStringArrayViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
procedure ShowTextViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);

implementation

uses
  Windows;

{$R *.lfm}

procedure ShowBasicViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  Viewer: TfrmFileViewer;
begin
  Viewer := TfrmFileViewer.Create(Application);
  Viewer.LoadBasicFile(DiskImage, DiskFile, DiskName);
  Viewer.Show;
end;

procedure ShowStringArrayViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  Viewer: TfrmFileViewer;
begin
  Viewer := TfrmFileViewer.Create(Application);
  Viewer.LoadStringArrayFile(DiskImage, DiskFile, DiskName);
  Viewer.Show;
end;

procedure ShowTextViewer(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  Viewer: TfrmFileViewer;
begin
  Viewer := TfrmFileViewer.Create(Application);
  Viewer.LoadTextFile(DiskImage, DiskFile, DiskName);
  Viewer.Show;
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

procedure TfrmFileViewer.UpdateCaption;
begin
  if (FDiskName <> '') and (FFileName <> '') then
    Caption := Format('%s - %s', [FFileName, FDiskName])
  else if FFileName <> '' then
    Caption := FFileName
  else
    Caption := 'File Viewer';
end;

procedure TfrmFileViewer.LoadBasicFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  SinclairParser: TSinclairBasicParser;
  AmstradParser: TAmstradBasicParser;
  RTFText: string;
begin
  FDiskName := DiskName;
  FFileName := DiskFile.FileName;
  UpdateCaption;

  EnsureViewer;

  if DiskFile.HeaderType = 'AMSDOS' then
  begin
    AmstradParser := TAmstradBasicParser.Create;
    try
      RTFText := AmstradParser.DecodeFileRTF(DiskImage, DiskFile);
    finally
      AmstradParser.Free;
    end;
  end
  else
  begin
    SinclairParser := TSinclairBasicParser.Create(sbMode128K);
    try
      RTFText := SinclairParser.DecodeFileRTF(DiskImage, DiskFile);
    finally
      SinclairParser.Free;
    end;
  end;

  if RTFText = '' then
    RTFText := '{\rtf1\ansi (Unable to decode BASIC program)}';
  FViewer.LoadRTF(RTFText);
end;

procedure TfrmFileViewer.LoadStringArrayFile(DiskImage: TDSKDisk; DiskFile: TCPMFile; const DiskName: string);
var
  Parser: TSinclairBasicParser;
  RTFText: string;
begin
  FDiskName := DiskName;
  FFileName := DiskFile.FileName;
  UpdateCaption;

  EnsureViewer;

  Parser := TSinclairBasicParser.Create(sbMode128K);
  try
    RTFText := Parser.DecodeStringArrayFileRTF(DiskImage, DiskFile);
  finally
    Parser.Free;
  end;

  if RTFText = '' then
    RTFText := '{\rtf1\ansi (Unable to decode string array)}';
  FViewer.LoadRTF(RTFText);
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

  Parser := TSinclairBasicParser.Create(sbMode128K);
  try
    RTFText := Parser.DecodeTextFileRTF(DiskImage, DiskFile);
  finally
    Parser.Free;
  end;

  if RTFText = '' then
    RTFText := '{\rtf1\ansi (Unable to decode file)}';
  FViewer.LoadRTF(RTFText);
end;

end.
