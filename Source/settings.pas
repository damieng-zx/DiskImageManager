unit Settings;

{$MODE Delphi}

{
  Disk Image Manager -  Settings

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Utils, DskImage,
  Classes, Dialogs, SysUtils, IniFiles, Graphics, Forms, FileUtil, ComCtrls,
  LazFileUtils;

type
  TSettings = class(TObject)
  public
    // Disk map
    DarkBlankSectors: boolean;
    DiskMapFont: TFont;
    DiskMapBackgroundColor: TColor;
    DiskMapGridColor: TColor;
    DiskMapTrackMark: integer;

    // Window
    WindowFont: TFont;
    RestoreWindow: boolean;

    // Sector view
    UnknownASCII: string;
    BytesPerLine: integer;
    SectorFont: TFont;
    WarnSectorChange: boolean;
    Mapping: string;

    // Workspace
    RestoreWorkspace: boolean;
    OpenView: string;
    RecentFiles: TStringList;

    // Navigation history (serialized location descriptors + current index)
    NavHistoryRaw: TStringList;
    NavHistoryIndex: integer;

    // Strings
    StringsFont: TFont;
    StringMinLength: integer;
    StringSort: string;

    // Saving
    WarnConversionProblems: boolean;
    RemoveEmptyTracks: boolean;
    SaveDiskMapHeight, SaveDiskMapWidth: integer;

    constructor Create(Owner: TForm);
    procedure Load(ClearFiles: boolean);
    procedure Apply;
    procedure Save;
    procedure Reset;
    procedure AddRecentFile(FileName: string);
  end;

implementation

uses Main;

var
  frmMain: TFrmMain;

constructor TSettings.Create(Owner: TForm);
begin
  frmMain := TFrmMain(Owner);
  RecentFiles := TStringList.Create;
  NavHistoryRaw := TStringList.Create;
  NavHistoryIndex := -1;
end;

// Apply some settings directly to other places
procedure TSettings.Apply;
begin
  with frmMain do
  begin
    Font := WindowFont;
    DiskMap.DarkBlankSectors := DarkBlankSectors;
    DiskMap.GridColor := DiskMapGridColor;
    DiskMap.Color := DiskMapBackgroundColor;
    DiskMap.TrackMark := DiskMapTrackMark;
    memo.Font := StringsFont;
  end;
end;

// Load system settings
procedure TSettings.Load(ClearFiles: boolean);
var
  Reg: TIniFile;
  Idx: integer;
  FileName: TFileName;
  S: string;
begin
  Reg := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));

  S := 'DiskMap';
  DarkBlankSectors := Reg.ReadBool(S, 'DarkBlankSectors', True);
  DiskMapFont := FontFromDescription(Reg.ReadString(S, 'Font', 'Tahoma,7pt,,'));
  DiskMapBackgroundColor := TColor(Reg.ReadInteger(S, 'BackgroundColour', integer(clGray)));
  DiskMapGridColor := TColor(Reg.ReadInteger(S, 'GridColour', integer(clSilver)));
  DiskMapTrackMark := Reg.ReadInteger(S, 'TrackMark', 5);

  S := 'Window';
  WindowFont := FontFromDescription(Reg.ReadString(S, 'Font', 'Tahoma,8pt,,'));
  OpenView := Reg.ReadString(S, 'OpenView', 'Image');
  RestoreWindow := Reg.ReadBool(S, 'Restore', False);
  if RestoreWindow then
    with frmMain do
    begin
      Left := Reg.ReadInteger(S, 'Left', Left);
      Top := Reg.ReadInteger(S, 'Top', Top);
      Height := Reg.ReadInteger(S, 'Height', Height);
      Width := Reg.ReadInteger(S, 'Width', Width);
      tvwMain.Width := Reg.ReadInteger(S, 'TreeWidth', tvwMain.Width);
      toolbar.Visible := Reg.ReadBool(S, 'Toolbar', True);
      itmToolbar.Checked := toolbar.Visible;
      statusbar.Visible := Reg.ReadBool(S, 'StatusBar', True);
      itmStatusBar.Checked := statusBar.Visible;
    end;

  S := 'SectorView';
  UnknownASCII := Reg.ReadString(S, 'UnknownASCII', '?');
  BytesPerLine := Reg.ReadInteger(S, 'BytesPerLine', 8);
  SectorFont := FontFromDescription(Reg.ReadString(S, 'Font', 'Consolas,8pt,,'));
  WarnSectorChange := Reg.ReadBool(S, 'WarnSectorChange', True);
  Mapping := Reg.ReadString(S, 'Mapping', '1252');

  S := 'StringsView';
  StringsFont := FontFromDescription(Reg.ReadString(S, 'Font', 'Tahoma,8pt,,'));
  StringMinLength := Reg.ReadInteger(S, 'MinLength', 5);
  StringSort := Reg.ReadString(S, 'Sort', 'Alpha');

  S := 'Workspace';
  RestoreWorkspace := Reg.ReadBool(S, 'Restore', False);
  if RestoreWorkspace and not ClearFiles then
  begin
    Idx := 1;
    repeat
      FileName := Reg.ReadString(S, StrInt(Idx), '*end');
      if (FileName <> '*end') and (FileExistsUTF8(FileName)) then
        frmMain.LoadImage(FileName);
      Inc(Idx);
    until FileName = '*end';
  end;

  S := 'Saving';
  WarnConversionProblems := Reg.ReadBool(S, 'WarnConversionProblems', True);
  RemoveEmptyTracks := Reg.ReadBool(S, 'RemoveEmptyTracks', False);
  SaveDiskMapWidth := Reg.ReadInteger(S, 'MapWidth', 640);
  SaveDiskMapHeight := Reg.ReadInteger(S, 'MapHeight', 480);

  S := 'Recent';
  Idx := 1;
  RecentFiles.Clear;
  repeat
    FileName := Reg.ReadString(S, StrInt(Idx), '*end');
    Inc(Idx);
    if FileName <> '*end' then
      RecentFiles.Add(FileName);
  until FileName = '*end';

  S := 'History';
  NavHistoryIndex := Reg.ReadInteger(S, 'Index', -1);
  Idx := 1;
  NavHistoryRaw.Clear;
  repeat
    FileName := Reg.ReadString(S, StrInt(Idx), '*end');
    Inc(Idx);
    if FileName <> '*end' then
      NavHistoryRaw.Add(FileName);
  until FileName = '*end';

  Reg.Free;

  Apply;
end;

// Save system settings
procedure TSettings.Save;
var
  Reg: TIniFile;
  Idx, WorkspaceIdx: integer;
  Node: TTreeNode;
  S: string;
begin
  Reg := TIniFile.Create(ChangeFileExt(Application.ExeName, '.ini'));

  S := 'DiskMap';
  Reg.WriteInteger(S, 'BackgroundColour', integer(DiskMapBackgroundColor));
  Reg.WriteBool(s, 'DarkBlankSectors', DarkBlankSectors);
  Reg.WriteInteger(S, 'GridColour', integer(DiskMapGridColor));
  Reg.WriteInteger(S, 'TrackMark', DiskMapTrackMark);
  Reg.WriteString(S, 'Font', FontToDescription(DiskMapFont));

  S := 'Window';
  with frmMain do
  begin
    Reg.WriteBool(S, 'Restore', RestoreWindow);
    Reg.WriteInteger(S, 'Left', Left);
    Reg.WriteInteger(S, 'Top', Top);
    Reg.WriteInteger(S, 'Height', Height);
    Reg.WriteInteger(S, 'Width', Width);
    Reg.WriteInteger(S, 'TreeWidth', tvwMain.Width);
    Reg.WriteString(S, 'Font', FontToDescription(Font));
    Reg.WriteBool(S, 'Toolbar', toolbar.Visible);
    Reg.WriteBool(S, 'StatusBar', statusBar.Visible);
  end;
  Reg.WriteString(S, 'OpenView', OpenView);

  S := 'SectorView';
  Reg.WriteString(S, 'UnknownASCII', UnknownASCII);
  Reg.WriteInteger(S, 'BytesPerLine', BytesPerLine);
  Reg.WriteString(S, 'Font', FontToDescription(SectorFont));
  Reg.WriteBool(S, 'WarnSectorChange', WarnSectorChange);
  Reg.WriteString(S, 'Mapping', Mapping);

  S := 'StringsView';
  Reg.WriteString(S, 'Font', FontToDescription(StringsFont));
  Reg.WriteInteger(S, 'MinLength', StringMinLength);
  Reg.WriteString(S, 'Sort', StringSort);

  S := 'Workspace';
  Reg.EraseSection(S);
  Reg.WriteBool(S, 'Restore', RestoreWorkspace);
  WorkspaceIdx := 1;
  with frmMain do
    for Idx := 0 to tvwMain.Items.Count - 1 do
    begin
      Node := tvwMain.Items[Idx];
      if (Node.Data <> nil) and (TObject(Node.Data).ClassType = TDSKImage) then
      begin
        Reg.WriteString(S, StrInt(WorkspaceIdx), TDSKImage(Node.Data).FileName);
        Inc(WorkspaceIdx);
      end;
    end;

  S := 'Saving';
  Reg.WriteBool(S, 'WarnConversionProblems', WarnConversionProblems);
  Reg.WriteBool(S, 'RemoveEmptyTracks', RemoveEmptyTracks);
  Reg.WriteInteger(S, 'MapWidth', SaveDiskMapWidth);
  Reg.WriteInteger(S, 'MapHeight', SaveDiskMapHeight);

  S := 'Recent';
  Reg.EraseSection(S);
  for Idx := 0 to RecentFiles.Count - 1 do
    Reg.WriteString(S, StrInt(Idx + 1), RecentFiles[Idx]);

  S := 'History';
  Reg.EraseSection(S);
  Reg.WriteInteger(S, 'Index', NavHistoryIndex);
  for Idx := 0 to NavHistoryRaw.Count - 1 do
    Reg.WriteString(S, StrInt(Idx + 1), NavHistoryRaw[Idx]);

  Reg.Free;
end;

procedure TSettings.Reset;
begin
  DeleteFile(ChangeFileExt(Application.ExeName, '.ini'));
  Load(true);
end;

procedure TSettings.AddRecentFile(FileName: string);
var
  Index: integer;
begin
  // Move our recent file to the top of the list
  repeat
    begin
      Index := RecentFiles.IndexOf(FileName);
      if Index >= 0 then
        RecentFiles.Delete(Index);
    end;
  until Index = -1;
  RecentFiles.Insert(0, FileName);

  // Limit size of the list
  while RecentFiles.Count > 8 do
    RecentFiles.Pop;
end;

end.
