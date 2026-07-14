unit Main;

{$MODE Delphi}

{
  Disk Image Manager -  Main window

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DiskMap, DskImage, Utils, About, Options, SectorProperties,
  TrackProperties, Settings, FileSystem, MGTFileSystem, ListViewPresenter,
  Comparers, FileViewer, SinclairBasic, ZXScreenViewer, SpectrumScreen,
  CPCScreenViewer, AmstradScreen,
  Classes, Graphics, SysUtils, Forms, Dialogs, Menus,
  ComCtrls, ExtCtrls, Controls,
  Clipbrd, StdCtrls, FileUtil, StrUtils, LazFileUtils, LConvEncoding, CommCtrl;

type
  { TfrmMain }

  TfrmMain = class(TForm)
    itmCopyDetailsClipboard1: TMenuItem;
    itmCopySep1: TMenuItem;
    itmOpenRecent: TMenuItem;
    itmSaveAllFiles: TMenuItem;
    itmSaveAllFilesTo: TMenuItem;
    itmSaveAllFilesWithHeadersTo: TMenuItem;
    itmSaveAllFilesWithoutHeadersTo: TMenuItem;
    itmTrackProperties: TMenuItem;
    itmTrackUnformat: TMenuItem;
    memo: TMemo;
    itmSaveFile: TMenuItem;
    itmSaveSelectedFiles: TMenuItem;
    itmCopyMapToClipboard: TMenuItem;
    itmToolbar: TMenuItem;
    itemSaveFileWithHeader: TMenuItem;
    itmSaveFileWithoutHeader: TMenuItem;
    itmSaveSelectedWithHeader: TMenuItem;
    itmSaveSelectedWithoutHeader: TMenuItem;
    itmFileSector: TMenuItem;
    itmSaveHeaderlessFile: TMenuItem;
    itmSaveSelectedHeaderlessFiles: TMenuItem;
    itmCollapseAll: TMenuItem;
    itmExpandAll: TMenuItem;
    itmCollapseChildren: TMenuItem;
    itmExpandChildren: TMenuItem;
    itmCloseAllExcept: TMenuItem;
    itmCloseAllExceptModified: TMenuItem;
    itmCloseAllExceptCopyProtected: TMenuItem;
    itmCloseAllExceptV5: TMenuItem;
    itmCloseAllExceptCPC: TMenuItem;
    itmCloseAllExceptZXPlus3: TMenuItem;
    itmCloseAllExceptBootSectors: TMenuItem;
    itmCloseAllExceptDoubleSided: TMenuItem;
    itmCloseAllExceptFDCError: TMenuItem;
    itmViewFile: TMenuItem;
    mnuMain: TMainMenu;
    itmDisk: TMenuItem;
    itmOpen: TMenuItem;
    itmNew: TMenuItem;
    N1: TMenuItem;
    itmSaveCopyAs: TMenuItem;
    N2: TMenuItem;
    itmExit: TMenuItem;
    itmView: TMenuItem;
    itmHelp: TMenuItem;
    itmAbout: TMenuItem;
    dlgOpen: TOpenDialog;
    N8: TMenuItem;
    pnlMemo: TPanel;
    pnlLeft: TPanel;
    dlgSaveBinary: TSaveDialog;
    dlgSelectDirectory: TSelectDirectoryDialog;
    popFileSystem: TPopupMenu;
    popTrack: TPopupMenu;
    Separator1: TMenuItem;
    itmCopySep: TMenuItem;
    Separator2: TMenuItem;
    Separator3: TMenuItem;
    Separator4: TMenuItem;
    Separator5: TMenuItem;
    splVertical: TSplitter;
    statusBar: TStatusBar;
    pnlRight: TPanel;
    pnlListLabel: TPanel;
    toolbar: TToolBar;
    tbnNew: TToolButton;
    tbnOpen: TToolButton;
    tbnSave: TToolButton;
    ToolButton2: TToolButton;
    ToolButton4: TToolButton;
    tbnCopy: TToolButton;
    tbnFind: TToolButton;
    tbnCloseAll: TToolButton;
    tvwMain: TTreeView;
    lvwMain: TListView;
    imlSmall: TImageList;
    pnlTreeLabel: TPanel;
    N4: TMenuItem;
    itmClose: TMenuItem;
    itmOptions: TMenuItem;
    DiskMap: TSpinDiskMap;
    itmCloseAll: TMenuItem;
    dlgSave: TSaveDialog;
    popDiskMap: TPopupMenu;
    itmSaveMapAs: TMenuItem;
    dlgSaveMap: TSaveDialog;
    itmDarkBlankSectorsPop: TMenuItem;
    itmStatusBar: TMenuItem;
    N3: TMenuItem;
    N5: TMenuItem;
    itmDarkUnusedSectors: TMenuItem;
    itmSave: TMenuItem;
    popSector: TPopupMenu;
    itmSectorResetFDC: TMenuItem;
    itmSectorBlankData: TMenuItem;
    itmSectorUnformat: TMenuItem;
    N6: TMenuItem;
    itmSectorProperties: TMenuItem;
    itmEdit: TMenuItem;
    itmEditCopy: TMenuItem;
    itmEditSelectAll: TMenuItem;
    popListItem: TPopupMenu;
    popDiskImage: TPopupMenu;
    itmDiskClose: TMenuItem;
    itmDiskCloseSep: TMenuItem;
    itmDiskCopyPath: TMenuItem;
    itmCopyDetailsClipboard: TMenuItem;
    N7: TMenuItem;
    itmFind: TMenuItem;
    itmFindNext: TMenuItem;
    dlgFind: TFindDialog;
    procedure itmCloseAllExceptClick(Sender: TObject);
    procedure itmCloseAllExceptCopyProtectedClick(Sender: TObject);
    procedure itmCollapseAllClick(Sender: TObject);
    procedure itmCollapseChildrenClick(Sender: TObject);
    procedure itmCopyMapToClipboardClick(Sender: TObject);
    procedure itmDiskCopyPathClick(Sender: TObject);
    procedure itmExpandAllClick(Sender: TObject);
    procedure itmExpandChildrenClick(Sender: TObject);
    procedure itmFileSectorClick(Sender: TObject);
    procedure itmOpenClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure itmOpenRecentClick(Sender: TObject);
    procedure itmRenameFileClick(Sender: TObject);
    procedure itmSaveAllFilesToClick(Sender: TObject);
    procedure itmSaveAllFilesWithHeadersToClick(Sender: TObject);
    procedure itmSaveAllFilesWithoutHeadersToClick(Sender: TObject);
    procedure itmSaveFileWithHeaderAsClick(Sender: TObject);
    procedure itmSaveSelectedFilesToClick(Sender: TObject);
    procedure itmSaveFileAsClick(Sender: TObject);
    procedure itmSaveSelectedFilesWithHeadersToClick(Sender: TObject);
    procedure itmToolbarClick(Sender: TObject);
    procedure itmTrackPropertiesClick(Sender: TObject);
    procedure itmTrackUnformatClick(Sender: TObject);
    procedure ShowFile(Sender: TObject);
    procedure lvwMainCompare(Sender: TObject; Item1, Item2: TListItem;
      Data: integer; var Compare: integer);
    procedure MenuItem1Click(Sender: TObject);
    procedure popFileSystemPopup(Sender: TObject);
    procedure popListItemPopup(Sender: TObject);
    procedure tvwMainChange(Sender: TObject; Node: TTreeNode);
    procedure DiskMapSectorClick(Sender: TObject; Sector: TDSKSector);
    procedure DiskMapTrackClick(Sender: TObject; Track: TDSKTrack);
    procedure itmAboutClick(Sender: TObject);
    procedure itmCloseClick(Sender: TObject);
    procedure itmExitClick(Sender: TObject);
    procedure itmOptionsClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure itmCloseAllClick(Sender: TObject);
    procedure itmSaveCopyAsClick(Sender: TObject);
    procedure itmSaveMapAsClick(Sender: TObject);
    procedure itmDarkBlankSectorsPopClick(Sender: TObject);
    procedure popDiskMapPopup(Sender: TObject);
    procedure itmNewClick(Sender: TObject);
    procedure itmDarkUnusedSectorsClick(Sender: TObject);
    procedure itmStatusBarClick(Sender: TObject);
    procedure itmSaveClick(Sender: TObject);
    procedure itmSectorResetFDCClick(Sender: TObject);
    procedure itmSectorBlankDataClick(Sender: TObject);
    procedure itmSectorUnformatClick(Sender: TObject);
    procedure itmSectorPropertiesClick(Sender: TObject);
    procedure itmEditCopyClick(Sender: TObject);
    procedure itmEditSelectAllClick(Sender: TObject);
    procedure itmFindClick(Sender: TObject);
    procedure dlgFindFind(Sender: TObject);
    procedure itmFindNextClick(Sender: TObject);
    procedure tvwMainDblClick(Sender: TObject);
    procedure tvwMainMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
  private
    NextNewFile: integer;
    FPresenter: TListViewPresenter;
    function AddTree(Parent: TTreeNode; Text: string; ImageIdx: integer;
      NodeObject: TObject): TTreeNode;
    function GetSelectedSector(Sender: TObject): TDSKSector;
    function GetSelectedTrack(Sender: TObject): TDSKTrack;
    function GetTitle(Data: TTreeNode): string;
    function GetCurrentImage: TDSKImage;
    function IsDiskNode(Node: TTreeNode): boolean;
    function FindTreeNodeFromData(Node: TTreeNode; Data: TObject): TTreeNode;

    procedure SaveExtractedFile(WithHeader: boolean);
    procedure SaveExtractedFilesToFolder(WithHeader: boolean; AllFiles: boolean);
    procedure OnApplicationDropFiles(Sender: TObject; const FileNames: array of string);
    procedure UpdateRecentFilesMenu;
  public
    Settings: TSettings;

    procedure AddWorkspaceImage(Image: TDSKImage);
    procedure CloseImage(Image: TDSKImage);
    procedure LoadFiles(FileNames: array of string);
    procedure SaveImage(Image: TDSKImage);
    procedure SaveImageAs(Image: TDSKImage; Copy: boolean; NewName: string);
    procedure AnalyseMap(Side: TDSKSide);
    procedure RefreshList;
    procedure RefreshStrings(Disk: TDSKDisk);
    procedure UpdateMenus;

    function CloseAll(AllowCancel: boolean): boolean;
    function ConfirmChange(Action: string; Upon: string): boolean;
    function LoadImage(FileName: TFileName): boolean;
    function GetNextNewFile: integer;
  end;

const
  TAB = #9;
  CR = #13;
  LF = #10;
  CRLF = CR + LF;

var
  frmMain: TfrmMain;

function GetListViewAsText(ForListView: TListView): string;

implementation

{$R *.lfm}

uses New;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  FileNames: TStringList;
  Idx: integer;
begin
  Settings := TSettings.Create(self);
  Settings.Load(Application.HasOption('c', 'clear'));
  FPresenter := TListViewPresenter.Create(lvwMain, Settings);

  NextNewFile := 0;
  Caption := Application.Title;
  itmAbout.Caption := 'About ' + Application.Title;
  itmDarkUnusedSectors.Checked := DiskMap.DarkBlankSectors;
  DiskMap.OnSectorClick := DiskMapSectorClick;
  DiskMap.OnTrackClick := DiskMapTrackClick;
  Application.AddOnDropFilesHandler(OnApplicationDropFiles);

  FileNames := TStringList.Create();
  for Idx := 1 to ParamCount do
    if (not ParamStr(Idx).StartsWith('--')) then
      FileNames.Add(ParamStr(Idx));
  LoadFiles(FileNames.ToStringArray());

  FileNames.Free;
end;

procedure TfrmMain.LoadFiles(FileNames: array of string);
var
  FileName: string;
begin
  tvwMain.BeginUpdate;
  for FileName in FileNames do
    if FileExistsUTF8(FileName) then
      if LoadImage(FileName) then
        Settings.AddRecentFile(FileName);
  tvwMain.EndUpdate;
  UpdateRecentFilesMenu;
  Settings.Save;
end;

procedure TfrmMain.itmOpenRecentClick(Sender: TObject);
var
  FileName: string;
begin
  if Sender is TMenuItem then
  begin
    FileName := (Sender as TMenuItem).Caption;
    if FileExists(FileName) then
      LoadFiles([FileName])
    else
    if MessageDlg('File does not exist',
      SysUtils.Format('Can not find file %s. Remove from recent list?', [FileName]),
      mtConfirmation, mbYesNo, 0) = mrYes then
      Settings.RecentFiles.Delete(Settings.RecentFiles.IndexOf(FileName));
  end;
end;

procedure TfrmMain.itmRenameFileClick(Sender: TObject);
begin
  if lvwMain.SelCount > 0 then lvwMain.Selected.EditCaption;
end;

procedure TfrmMain.itmSaveAllFilesToClick(Sender: TObject);
begin
  SaveExtractedFilesToFolder(True, True);
end;

procedure TfrmMain.itmSaveAllFilesWithHeadersToClick(Sender: TObject);
begin
  SaveExtractedFilesToFolder(True, True);
end;

procedure TfrmMain.itmSaveAllFilesWithoutHeadersToClick(Sender: TObject);
begin
  SaveExtractedFilesToFolder(False, True);
end;

procedure TfrmMain.itmSaveSelectedFilesWithHeadersToClick(Sender: TObject);
begin
  SaveExtractedFilesToFolder(True, False);
end;

procedure TfrmMain.itmToolbarClick(Sender: TObject);
begin
  toolbar.Visible := not itmToolbar.Checked;
  itmToolbar.Checked := toolbar.Visible;
end;

procedure TfrmMain.itmTrackPropertiesClick(Sender: TObject);
var
  Track: TDSKTrack;
begin
  Track := GetSelectedTrack(popTrack.PopupComponent);

  if Track <> nil then
    TfrmTrackProperties.Create(Self, Track);

  UpdateMenus;
end;

procedure TfrmMain.itmTrackUnformatClick(Sender: TObject);
var
  Track: TDSKTrack;
begin
  Track := GetSelectedTrack(popTrack.PopupComponent);

  if (Track <> nil) and (ConfirmChange('unformat', 'track')) then
  begin
    Track.Unformat;
    tvwMain.Selected.DeleteChildren;
  end;

  RefreshList;
  UpdateMenus;
end;

procedure TfrmMain.lvwMainCompare(Sender: TObject; Item1, Item2: TListItem;
  Data: integer; var Compare: integer);
begin
  Compare := CompareItems(Item1, Item2, lvwMain);
end;

procedure TfrmMain.MenuItem1Click(Sender: TObject);
begin

end;

procedure TfrmMain.popFileSystemPopup(Sender: TObject);
var
  AllHeaderlessFilesSelected: boolean;
  ListItem: TListItem;
begin
  AllHeaderlessFilesSelected := True;
  for ListItem in lvwMain.Items do
    if (TObject(ListItem.Data).ClassType = TCPMFile) and
      (TCPMFile(ListItem.Data).HeaderType <> 'None') then
    begin
      AllHeaderlessFilesSelected := False;
      Break;
    end;

  itmSaveAllFiles.Visible := not AllHeaderlessFilesSelected;
  itmSaveAllFilesTo.Visible := AllHeaderlessFilesSelected;
end;

procedure TfrmMain.itmSaveSelectedFilesToClick(Sender: TObject);
begin
  SaveExtractedFilesToFolder(False, False);
end;

procedure TfrmMain.SaveExtractedFilesToFolder(WithHeader: boolean; AllFiles: boolean);
var
  SaveCount: integer;
  ListItem: TListItem;
  Folder: string;
  Stream: TStream;
  DiskFile: TCPMFile;
  Data: TDiskByteArray;
begin
  if not dlgSelectDirectory.Execute then exit;

  SaveCount := 0;
  Folder := dlgSelectDirectory.FileName + PathDelim;
  for ListItem in lvwMain.Items do
    if (AllFiles or ListItem.Selected) and (TObject(ListItem.Data).ClassType =
      TCPMFile) then
    begin
      DiskFile := TCPMFile(ListItem.Data);
      Stream := TFileStream.Create(Folder + DiskFile.FileName, fmCreate);
      try
        Data := DiskFile.GetData(WithHeader);
        Stream.WriteBuffer(Pointer(Data)^, Length(Data));
      finally
        Stream.Free;
      end;
      Inc(SaveCount);
    end;

  statusBar.SimpleText := Format('%d files saved to %s',
    [SaveCount, dlgSelectDirectory.FileName]);
end;

procedure TfrmMain.itmSaveFileWithHeaderAsClick(Sender: TObject);
begin
  SaveExtractedFile(True);
end;

procedure TfrmMain.itmSaveFileAsClick(Sender: TObject);
begin
  SaveExtractedFile(False);
end;

procedure TfrmMain.SaveExtractedFile(WithHeader: boolean);
var
  DiskFile: TCPMFile;
  Data: TDiskByteArray;
  Stream: TStream;
begin
  if (lvwMain.Selected = nil) or (lvwMain.Selected.Data = nil) or
    (TObject(lvwMain.Selected.Data).ClassType <> TCPMFile) then
    exit;

  DiskFile := TCPMFile(lvwMain.Selected.Data);

  dlgSaveBinary.FileName := DiskFile.FileName;
  if not dlgSaveBinary.Execute then exit;

  Stream := TFileStream.Create(dlgSaveBinary.FileName, fmCreate);
  try
    Data := DiskFile.GetData(WithHeader);
    Stream.WriteBuffer(Pointer(Data)^, Length(Data));
  finally
    Stream.Free;
  end;

  statusBar.SimpleText := Format('File %s saved as %s',
    [DiskFile.FileName, dlgSaveBinary.FileName]);
end;

procedure TfrmMain.popListItemPopup(Sender: TObject);
var
  DiskFile: TCPMFile;
  AllHeaderlessFilesSelected: boolean;
  ListItem: TListItem;
  DataSelect: TObject;
begin
  itmSaveFile.Visible := False;
  itmSaveHeaderlessFile.Visible := False;

  if (lvwMain.SelCount = 1) and (lvwMain.Selected.Data <> nil) and
    (TObject(lvwMain.Selected.Data).ClassType = TCPMFile) then
  begin
    DiskFile := TCPMFile((lvwMain.Selected).Data);
    itmSaveFile.Visible := DiskFile.HeaderType <> 'None';
    itmSaveFile.Caption := Format('Save %s', [DiskFile.FileName]);

    itmSaveHeaderlessFile.Visible := DiskFile.HeaderType = 'None';
    itmSaveHeaderlessFile.Caption := Format('Save %s as...', [DiskFile.FileName]);
  end;

  // In the case of multiple files selected we need to know if any have headers
  AllHeaderlessFilesSelected := True;
  for ListItem in lvwMain.Items do
    if (ListItem.Selected) and (ListItem.Data <> nil) then
    begin
      DataSelect := TObject(ListItem.Data);
      if (DataSelect.ClassType = TCPMFile) and
        (TCPMFile(ListItem.Data).HeaderType <> 'None') then
      begin
        AllHeaderlessFilesSelected := False;
        Break;
      end;
    end;

  itmSaveSelectedFiles.Visible := not AllHeaderlessFilesSelected;
  itmSaveSelectedFiles.Caption := Format('Save %d selected files', [lvwMain.SelCount]);

  itmSaveSelectedHeaderlessFiles.Visible := AllHeaderlessFilesSelected;
  itmSaveSelectedHeaderlessFiles.Caption :=
    Format('Save %d selected files to...', [lvwMain.SelCount]);
end;

function TfrmMain.FindTreeNodeFromData(Node: TTreeNode; Data: TObject): TTreeNode;
var
  ChildNode, FoundInChildNode: TTreeNode;
begin
  Result := nil;
  if Node.HasChildren then
  begin
    ChildNode := Node.GetFirstChild;
    repeat
      if ChildNode.Data = Data then
      begin
        Result := ChildNode;
        exit;
      end;
      FoundInChildNode := FindTreeNodeFromData(ChildNode, Data);
      if FoundInChildNode <> nil then
      begin
        Result := FoundInChildNode;
        exit;
      end;
      ChildNode := Node.GetNextChild(ChildNode);
    until ChildNode = nil;
  end;
end;

procedure TfrmMain.UpdateRecentFilesMenu;
var
  MenuItem: TMenuItem;
  RecentFile: string;
begin
  itmOpenRecent.Clear;
  for RecentFile in Settings.RecentFiles do
  begin
    MenuItem := TMenuItem.Create(itmOpenRecent);
    MenuItem.OnClick := itmOpenRecentClick;
    MenuItem.Caption := RecentFile;
    itmOpenRecent.Add(MenuItem);
  end;
end;

procedure TfrmMain.itmOpenClick(Sender: TObject);
begin
  if dlgOpen.Execute then
    LoadFiles(dlgOpen.Files.ToStringArray());
end;

procedure TfrmMain.itmCopyMapToClipboardClick(Sender: TObject);
var
  MapImage: TBitmap;
begin
  MapImage := DiskMap.CreateImage(Settings.SaveDiskMapWidth, Settings.SaveDiskMapHeight);
  Clipboard.Assign(MapImage);
  MapImage.Free;

end;

procedure TfrmMain.itmExpandAllClick(Sender: TObject);
var
  Node: TTreeNode;
begin
  tvwMain.Items.BeginUpdate;
  try
    Node := tvwMain.Items.GetFirstNode;
    while Node <> nil do
    begin
      Node.Expand(True);  // Recursively expands this node and all children
      Node := Node.GetNextSibling;  // Move to next sibling, not next in hierarchy
    end;
  finally
    tvwMain.Items.EndUpdate;
  end;
end;

procedure TfrmMain.itmExpandChildrenClick(Sender: TObject);
begin
  tvwMain.Selected.Expand(True);
end;

procedure TfrmMain.itmCollapseAllClick(Sender: TObject);
var
  Node: TTreeNode;
begin
  tvwMain.Items.BeginUpdate;
  try
    Node := tvwMain.Items.GetFirstNode;
    while Node <> nil do
    begin
      Node.Collapse(True);
      Node := Node.GetNextSibling;
    end;
  finally
    tvwMain.Items.EndUpdate;
  end;
end;

procedure TfrmMain.itmCloseAllExceptClick(Sender: TObject);
var
  Current: TTreeNode;
  CurrentImage: TDSKImage;
  ShouldClose: boolean;
  Format: string;
  i: integer;
  NodesToDelete: TList;
begin
  Cursor := crHourGlass;
  Application.ProcessMessages;  // Allow cursor to update

  NodesToDelete := TList.Create;
  try
    // First pass: identify nodes to delete and free images
    for i := 0 to tvwMain.Items.Count - 1 do
    begin
      Current := tvwMain.Items[i];

      if IsDiskNode(Current) then
      begin
        CurrentImage := TDSKImage(Current.Data);
        ShouldClose := True;

        if Sender = itmCloseAllExceptModified then
          ShouldClose := not CurrentImage.IsChanged;
        if Sender = itmCloseAllExceptV5 then
          ShouldClose := not CurrentImage.HasV5Extensions;
        if Sender = itmCloseAllExceptCopyProtected then
          ShouldClose := CurrentImage.Disk.DetectCopyProtection() = '';
        if Sender = itmCloseAllExceptBootSectors then
          ShouldClose := CurrentImage.Disk.BootableOn = '';
        if Sender = itmCloseAllExceptDoubleSided then
          ShouldClose := CurrentImage.Disk.Sides <> 2;
        if Sender = itmCloseAllExceptFDCError then
          ShouldClose := not CurrentImage.Disk.HasFDCErrors;

        if (Sender = itmCloseAllExceptCPC) or (Sender = itmCloseAllExceptZXPlus3) then
        begin
          Format := CurrentImage.Disk.DetectFormat();
          ShouldClose := ((Sender = itmCloseAllExceptCPC) and
            (not Format.Contains('CPC')) or
            (Sender = itmCloseAllExceptZXPlus3) and (not Format.Contains('+3')));
        end;

        if ShouldClose then
        begin
          CurrentImage.Free;
          NodesToDelete.Add(Current);
        end;
      end;
    end;

    // Second pass: delete nodes only
    if NodesToDelete.Count > 0 then
    begin
      tvwMain.BeginUpdate;
      try
        for i := 0 to NodesToDelete.Count - 1 do
          TTreeNode(NodesToDelete[i]).Delete;
      finally
        tvwMain.EndUpdate;
      end;
    end;
  finally
    NodesToDelete.Free;
    Cursor := crDefault;
  end;
end;

procedure TfrmMain.itmCloseAllExceptCopyProtectedClick(Sender: TObject);
begin

end;

procedure TfrmMain.itmCollapseChildrenClick(Sender: TObject);
begin
  tvwMain.Selected.Collapse(True);
end;

procedure TfrmMain.itmFileSectorClick(Sender: TObject);
var
  FoundNode: TTreeNode;
  FirstSector: TDSKSector;
begin
  FirstSector := nil;

  // Jump to the first sector for this file
  if TObject(lvwMain.Selected.Data).ClassType = TCPMFile then
    FirstSector := TCPMFile((lvwMain.Selected).Data).FirstSector
  else if TObject(lvwMain.Selected.Data).ClassType = TMGTFile then
    FirstSector := TMGTFile((lvwMain.Selected).Data).FirstSector;

  if FirstSector = nil then exit;

  FoundNode := FindTreeNodeFromData(tvwMain.Selected.Parent, FirstSector);
  if FoundNode <> nil then
    tvwMain.Selected := FoundNode;
end;

function TfrmMain.LoadImage(FileName: TFileName): Boolean;
var
  NewImage: TDSKImage;
begin
  Result := False;
  NewImage := nil;

  try
    NewImage := TDSKImage.CreateFromFile(FileName);

    if NewImage <> nil then
    begin
      AddWorkspaceImage(NewImage);
      Result := True;
    end;
  except
    on E: Exception do
    begin
      // Clean up if creation partially succeeded
      if NewImage <> nil then
        NewImage.Free;

      MessageDlg('Error loading ' + FileName, e.Message, mtError, [mbOK], 0);
    end;
  end;
end;

procedure TfrmMain.AddWorkspaceImage(Image: TDSKImage);
var
  SIdx, TIdx, EIdx: integer;
  ImageNode, SideNode, TrackNode, TracksNode, SpecsNode, SectorNode, MapNode: TTreeNode;
begin
  SideNode := nil;
  tvwMain.Items.BeginUpdate;

  if Image.Corrupt then
    ImageNode := AddTree(nil, ExtractFileName(Image.FileName), Ord(itDiskCorrupt), Image)
  else
    ImageNode := AddTree(nil, ExtractFileName(Image.FileName), Ord(itDisk), Image);

  tvwMain.Selected := ImageNode;

  if Image.Disk.Sides > 0 then
  begin
    // Optional specification
    Image.Disk.Specification.Identify;
    if Image.Disk.Specification.Format <> dsFormatInvalid then
    begin
      SpecsNode := AddTree(ImageNode, 'Specification', Ord(itSpecification),
        Image.Disk.Specification);
      if Settings.OpenView = 'Specification' then
        tvwMain.Selected := SpecsNode;
    end;

    // Add the sides
    for SIdx := 0 to Image.Disk.Sides - 1 do
    begin
      SideNode := AddTree(ImageNode, Format('Side %d', [SIdx + 1]),
        Ord(itSide0) + SIdx, Image.Disk.Side[SIdx]);
      if (SIdx = 0) and (Settings.OpenView = 'Track list') then
        tvwMain.Selected := SideNode;

      MapNode := AddTree(SideNode, 'Map', Ord(itAnalyse), Image.Disk.Side[SIdx]);
      if (SIdx = 0) and (Settings.OpenView = 'Map') then
        tvwMain.Selected := MapNode;

      // Add the tracks
      TracksNode := AddTree(SideNode, 'Tracks', Ord(itTracksAll), Image.Disk.Side[SIdx]);
      with Image.Disk.Side[SIdx] do
        for TIdx := 0 to Tracks - 1 do
        begin
          TrackNode := AddTree(TracksNode, Format('Track %d', [TIdx]),
            Ord(itTrack), Track[TIdx]);
          if (SIdx = 0) and (TIdx = 0) and (Settings.OpenView = 'First track') then
            tvwMain.Selected := TrackNode;

          // Add the sectors
          with Image.Disk.Side[SIdx].Track[TIdx] do
            for EIdx := 0 to Sectors - 1 do
            begin
              SectorNode := AddTree(TrackNode, SysUtils.Format('Sector %d', [EIdx]),
                Ord(itSector), Sector[EIdx]);
              if (SIdx = 0) and (TIdx = 0) and (EIdx = 0) and
                (Settings.OpenView = 'First sector') then
                tvwMain.Selected := SectorNode;
            end;
        end;
    end;

    if (Image.Disk.DetectFormat().StartsWith('MGT')) then
      AddTree(ImageNode, 'Files', Ord(itFiles), TMGTFileSystem.Create(Image.Disk))
    else
      AddTree(ImageNode, 'Files', Ord(itFiles), TCPMFileSystem.Create(Image.Disk));
    AddTree(ImageNode, 'Strings', Ord(itStrings), Image.Disk);

    if Image.Messages.Count > 0 then
      AddTree(ImageNode, 'Messages', Ord(itMessages), Image.Messages);
  end;
  tvwMain.Items.EndUpdate;

  ImageNode.Expanded := True;
  if (Image.Disk.Sides = 1) and (SideNode <> nil) then
    SideNode.Expanded := True;
end;

function TfrmMain.AddTree(Parent: TTreeNode; Text: string; ImageIdx: integer;
  NodeObject: TObject): TTreeNode;
var
  NewTreeNode: TTreeNode;
begin
  NewTreeNode := tvwMain.Items.AddChild(Parent, Text);
  with NewTreeNode do
  begin
    ImageIndex := ImageIdx;
    SelectedIndex := ImageIdx;
    Data := NodeObject;
  end;
  Result := NewTreeNode;
end;

procedure TfrmMain.tvwMainChange(Sender: TObject; Node: TTreeNode);
begin
  UpdateMenus;
end;

// Jump the treeview to the sector clicked on the disk map
procedure TfrmMain.DiskMapSectorClick(Sender: TObject; Sector: TDSKSector);
var
  Node: TTreeNode;
begin
  for Node in tvwMain.Items do
    if Node.Data = Pointer(Sector) then
    begin
      Node.Selected := True;
      Node.MakeVisible;
      tvwMain.SetFocus;
      Exit;
    end;
end;

// Jump the treeview to the (unformatted) track clicked on the disk map
procedure TfrmMain.DiskMapTrackClick(Sender: TObject; Track: TDSKTrack);
var
  Node: TTreeNode;
begin
  for Node in tvwMain.Items do
    if Node.Data = Pointer(Track) then
    begin
      Node.Selected := True;
      Node.MakeVisible;
      tvwMain.SetFocus;
      Exit;
    end;
end;

procedure TfrmMain.UpdateMenus;
var
  AllowImageFile: boolean;
  ObjectData: TObject;
begin
  AllowImageFile := False;
  tvwMain.PopupMenu := nil;

  // Decide what class operating on
  if (tvwMain.Selected <> nil) and (tvwMain.Selected.Data <> nil) then
  begin
    AllowImageFile := True;
    ObjectData := TObject(tvwMain.Selected.Data);
    if ObjectData.ClassType = TDSKImage then
      tvwMain.PopupMenu := popDiskImage;
    if ObjectData.ClassType = TDSKSector then
      tvwMain.PopupMenu := popSector;
    if ObjectData.ClassType = TDSKTrack then
      tvwMain.PopupMenu := popTrack;
    if ObjectData.ClassType = TCPMFileSystem then
      tvwMain.PopupMenu := popFileSystem;
    if ItemType(tvwMain.Selected.ImageIndex) = itAnalyse then
      tvwMain.PopupMenu := popDiskMap;
  end;

  // Set main menu options
  itmClose.Enabled := AllowImageFile;
  itmSave.Enabled := AllowImageFile;
  itmSaveCopyAs.Enabled := AllowImageFile;

  // Hide disk map if no longer selected
  if (lvwMain.Selected = nil) then
  begin
    DiskMap.Visible := False;
    pnlMemo.Visible := False;
    lvwMain.Visible := True;
  end;

  RefreshList;
end;

function TfrmMain.GetTitle(Data: TTreeNode): string;
var
  CurNode: TTreeNode;
begin
  Result := '';
  CurNode := Data;
  while CurNode <> nil do
  begin
    if (CurNode.ImageIndex <> 2) or (CurNode = tvwMain.Selected) then
      Result := CurNode.Text + ' > ' + Result;
    CurNode := CurNode.Parent;
  end;
  Result := Copy(Result, 0, Length(Result) - 3);
end;

procedure TfrmMain.RefreshList;
var
  OldViewStyle: TViewStyle;
begin
  with lvwMain do
  begin
    PopupMenu := popListItem;
    OldViewStyle := ViewStyle;
    Items.BeginUpdate;
    ViewStyle := vsList;
    Items.Clear;
    Columns.BeginUpdate;
    Columns.Clear;

    ParentFont := True;
    ShowColumnHeaders := True;

    if tvwMain.Selected <> nil then
      with tvwMain.Selected do
      begin
        pnlListLabel.Caption :=
          ' ' + AnsiReplaceStr(GetTitle(tvwMain.Selected), '&', '&&');
        lvwMain.Visible := (ItemType(ImageIndex) <> itAnalyse) and
          (Caption <> 'Strings');
        lvwMain.ReadOnly := True;
        DiskMap.Visible := ItemType(ImageIndex) = itAnalyse;
        pnlMemo.Visible := Caption = 'Strings';
        if Data <> nil then
        begin
          case ItemType(ImageIndex) of
            itDisk, itDiskCorrupt: FPresenter.RefreshImage(Data);
            itSpecification: FPresenter.RefreshSpecification(Data);
            itTracksAll:
              begin
                lvwMain.PopupMenu := popTrack;
                FPresenter.RefreshTrack(Data);
              end;
            itTrack:
              begin
                lvwMain.PopupMenu := popSector;
                FPresenter.RefreshSector(Data);
              end;
            itAnalyse: AnalyseMap(Data);
            itStrings: RefreshStrings(Data);
            itMessages: FPresenter.RefreshMessages(Data);
            else
              if TObject(Data).ClassType = TDSKSide then
              begin
                lvwMain.PopupMenu := popTrack;
                FPresenter.RefreshTrack(TDSKSide(Data));
              end;
              if TObject(Data).ClassType = TDSKSector then
                FPresenter.RefreshSectorData(TDSKSector(Data));
              if (TObject(Data).ClassType = TCPMFileSystem) then
                FPresenter.RefreshFiles(TCPMFileSystem(Data));
              if (TObject(Data).ClassType = TMGTFileSystem) then
                FPresenter.RefreshFilesMGT(TMGTFileSystem(Data));
          end;
        end;
      end
    else
      pnlListLabel.Caption := '';

    ViewStyle := OldViewStyle;
    Columns.EndUpdate;
    AutoResizeListView(lvwMain);
    Items.EndUpdate;
  end;
end;

// Menu: Help > About
procedure TfrmMain.itmAboutClick(Sender: TObject);
begin
  frmAbout := TfrmAbout.Create(Self);
  frmAbout.ShowModal;
  frmAbout.Free;
end;

// Find a disk image and remove it from the tree
procedure TfrmMain.CloseImage(Image: TDSKImage);
var
  Previous, Current: TTreeNode;
begin
  Previous := nil;
  for Current in tvwMain.Items do
  begin
    if IsDiskNode(Current) then
    begin
      if Current.Data = Image then
      begin
        TDSKImage(Current.Data).Free;
        Current.Delete;
        if tvwMain.Selected = nil then
          if Previous <> nil then
            Previous.Selected := True
          else
          if tvwMain.Items.Count > 0 then
            tvwMain.Items[0].Selected := True;
        exit;
      end;
      Previous := Current;
    end;
  end;
end;

// Get the current image
function TfrmMain.GetCurrentImage: TDSKImage;
var
  Node: TTreeNode;
begin
  Result := nil;
  Node := tvwMain.Selected;
  if (Node = nil) then
    exit;

  while (TObject(Node.Data).ClassType <> TDskImage) do
    Node := Node.Parent;

  Result := TDskImage(Node.Data);
end;

procedure TfrmMain.itmCloseClick(Sender: TObject);
begin
  if (tvwMain.Selected <> nil) then
    CloseImage(GetCurrentImage);
  Settings.Save();
end;

procedure TfrmMain.itmDiskCopyPathClick(Sender: TObject);
var
  Image: TDSKImage;
begin
  Image := GetCurrentImage;
  if Image <> nil then
    Clipboard.AsText := Image.FileName;
end;

procedure TfrmMain.itmExitClick(Sender: TObject);
begin
  Close;
end;

// Show the disk map
procedure TfrmMain.AnalyseMap(Side: TDSKSide);
begin
  lvwMain.Visible := False;
  DiskMap.Side := Side;
  DiskMap.Visible := True;
end;

procedure TfrmMain.RefreshStrings(Disk: TDSKDisk);
var
  Idx: integer;
  Strings: TStringList;
begin
  Strings := Disk.GetAllStrings(Settings.StringMinLength, 4);
  memo.Clear;
  lvwMain.Hide;

  if Settings.StringSort = 'Alpha' then
    Strings.Sort;
  if Settings.StringSort = 'Size' then
    Strings.CustomSort(CompareByLength);

  for Idx := 0 to Strings.Count - 1 do
    memo.Lines.Append(Strings[Idx]);
  if memo.Lines.Count > 0 then
    memo.Lines.Delete(memo.Lines.Count - 1);

  pnlMemo.Show;
end;

// Menu: View > Options
procedure TfrmMain.itmOptionsClick(Sender: TObject);
begin
  TfrmOptions.Create(self, Settings).Show;
  RefreshList;
end;

procedure TfrmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Settings.Save;
  if CloseAll(True) then
  begin
    FPresenter.Free;
    Action := caFree;
  end
  else
    Action := caNone;
end;

procedure TfrmMain.itmCloseAllClick(Sender: TObject);
begin
  CloseAll(True);
end;

function TfrmMain.IsDiskNode(Node: TTreeNode): boolean;
begin
  Result := (node.ImageIndex = Ord(itDisk)) or (node.ImageIndex = Ord(itDiskCorrupt));
end;

function TfrmMain.CloseAll(AllowCancel: boolean): boolean;
var
  Image: TDSKImage;
  Buttons: TMsgDlgButtons;
begin
  Result := True;
  if AllowCancel then
    Buttons := [mbYes, mbNo, mbCancel]
  else
    Buttons := [mbYes, mbNo];

  tvwMain.BeginUpdate;
  while tvwMain.Items.GetFirstNode <> nil do
  begin
    if IsDiskNode(tvwMain.Items.GetFirstNode) then
    begin
      Image := TDSKImage(tvwMain.Items.GetFirstNode.Data);
      if Image.IsChanged and not Image.Corrupt then
        case MessageDlg(Format('Save unsaved image "%s" ?', [Image.FileName]),
            mtWarning, Buttons, 0) of
          mrYes: SaveImage(Image);
          mrCancel:
          begin
            Result := False;
            exit;
          end;
        end;
      Image.Free;
      tvwMain.Items.GetFirstNode.Delete;
    end;
  end;
  tvwMain.EndUpdate;
  RefreshList;
  UpdateMenus;
end;

procedure TfrmMain.itmSaveCopyAsClick(Sender: TObject);
begin
  if tvwMain.Selected <> nil then
    SaveImageAs(GetCurrentImage, True, '');
end;

procedure TfrmMain.SaveImageAs(Image: TDSKImage; Copy: boolean; NewName: string);
var
  AbandonSave: boolean;
begin
  if NewName <> '' then
    dlgSave.FileName := NewName
  else
    dlgSave.FileName := Image.FileName;

  case Image.FileFormat of
    diStandardDSK: dlgSave.FilterIndex := 1;
    diRawMGT: dlgSave.FilterIndex := 3;
    else
      dlgSave.FilterIndex := 2;
  end;

  if dlgSave.Execute then
    case dlgSave.FilterIndex of
      3: Image.SaveFile(dlgSave.FileName, diRawMGT, Copy, False);
      2: Image.SaveFile(dlgSave.FileName, diExtendedDSK, Copy,
          Settings.RemoveEmptyTracks);
      1:
      begin
        AbandonSave := False;
        if Image.HasV5Extensions and
          (MessageDlg(
          'This image has modulation, data rate that "Standard DSK format" does not support. ' +

          'Save anyway and lose this information?', mtWarning, [mbYes, mbNo], 0) <> mrYes) then
          AbandonSave := True;

        if Image.HasOffsetInfo and
          (MessageDlg(
          'This image has SAMdisk OffsetInfo which "Standard DSK format" does not support. ' +
          'Save anyway and lose this information?', mtWarning, [mbYes, mbNo], 0) <> mrYes) then
          AbandonSave := True;

        if (not Image.Disk.IsTrackSizeUniform) and Settings.WarnConversionProblems and
          (MessageDlg(
          'This image has variable track sizes that "Standard DSK format" does not support. ' +
          'Save anyway using largest track size?', mtWarning, [mbYes, mbNo], 0) <> mrYes) then
          AbandonSave := True;

        if not AbandonSave then
          Image.SaveFile(dlgSave.FileName, diStandardDSK, Copy, False);
      end;
    end;
end;

procedure TfrmMain.itmSaveMapAsClick(Sender: TObject);
var
  DefaultFileName: string;
begin
  DefaultFileName := DiskMap.Side.ParentDisk.ParentImage.FileName;
  if DiskMap.Side.Side > 0 then
    DefaultFileName := DefaultFileName + ' Side ' + StrInt(DiskMap.Side.Side);
  dlgSaveMap.FileName := ExtractFileNameOnly(DefaultFileName);
  if dlgSaveMap.Execute then
    DiskMap.SaveMap(dlgSaveMap.FileName, Settings.SaveDiskMapWidth,
      Settings.SaveDiskMapHeight);
end;

procedure TfrmMain.itmDarkBlankSectorsPopClick(Sender: TObject);
begin
  DiskMap.DarkBlankSectors := not itmDarkBlankSectorsPop.Checked;
  itmDarkBlankSectorsPop.Checked := DiskMap.DarkBlankSectors;
end;

procedure TfrmMain.popDiskMapPopup(Sender: TObject);
begin
  itmDarkBlankSectorsPop.Checked := DiskMap.DarkBlankSectors;
end;

procedure TfrmMain.itmNewClick(Sender: TObject);
begin
  TfrmNew.Create(Self).Show;
end;

function TfrmMain.GetNextNewFile: integer;
begin
  NextNewFile := NextNewFile + 1;
  Result := NextNewFile;
end;

procedure TfrmMain.itmDarkUnusedSectorsClick(Sender: TObject);
begin
  DiskMap.DarkBlankSectors := not itmDarkUnusedSectors.Checked;
  itmDarkUnusedSectors.Checked := DiskMap.DarkBlankSectors;
end;

procedure TfrmMain.itmStatusBarClick(Sender: TObject);
begin
  statusBar.Visible := not itmStatusBar.Checked;
  itmStatusBar.Checked := statusBar.Visible;
end;

procedure TfrmMain.itmSaveClick(Sender: TObject);
var
  selectedImage: TDSKImage;
  Node: TTreeNode;
begin
  Node := tvwMain.Selected;
  if Node <> nil then
  begin
    selectedImage := GetCurrentImage;
    SaveImage(selectedImage);
    while (TObject(Node.Data).ClassType <> TDskImage) do
      Node := Node.Parent;
    Node.Text := ExtractFileName(selectedImage.FileName);
  end;
end;

procedure TfrmMain.SaveImage(Image: TDSKImage);
begin
  if Image.FileFormat = diNotYetSaved then
    SaveImageAs(Image, False, '')
  else
  if ExtractFileExt(Image.FileName) = '.gz' then
    SaveImageAs(Image, False, ExtractFileNameWithoutExt(Image.FileName))
  else
    Image.SaveFile(Image.FileName, Image.FileFormat, False,
      (Settings.RemoveEmptyTracks and (Image.FileFormat = diExtendedDSK)));

  RefreshList();
end;

procedure TfrmMain.itmSectorResetFDCClick(Sender: TObject);
var
  Sector: TDSKSector;
begin
  Sector := GetSelectedSector(popSector.PopupComponent);

  if (Sector <> nil) and (ConfirmChange('reset FDC flags for', 'sector')) then
    TDSKSector(tvwMain.Selected.Data).ResetFDC;

  if (popSector.PopupComponent = tvwMain) and (tvwMain.Selected <> nil) then
    if (TObject(tvwMain.Selected.Data).ClassType = TDSKTrack) and
      (ConfirmChange('reset FDC flags for', 'track')) then
      for Sector in TDSKTrack(tvwMain.Selected.Data).Sector do
        Sector.ResetFDC;

  RefreshList;
  UpdateMenus;
end;

function TfrmMain.GetSelectedSector(Sender: TObject): TDSKSector;
begin
  Result := nil;
  if (Sender = lvwMain) and (lvwMain.Selected <> nil) then
    Result := TDSKSector(lvwMain.Selected.Data);
  if (Sender = tvwMain) and (tvwMain.Selected <> nil) then
    if TObject(tvwMain.Selected.Data).ClassType = TDSKSector then
      Result := TDSKSector(tvwMain.Selected.Data);
end;

function TfrmMain.GetSelectedTrack(Sender: TObject): TDSKTrack;
begin
  Result := nil;
  if (Sender = lvwMain) and (lvwMain.Selected <> nil) then
    Result := TDSKTrack(lvwMain.Selected.Data);
  if (Sender = tvwMain) and (tvwMain.Selected <> nil) then
    if TObject(tvwMain.Selected.Data).ClassType = TDSKTrack then
      Result := TDSKTrack(tvwMain.Selected.Data);
end;

procedure TfrmMain.itmSectorBlankDataClick(Sender: TObject);
var
  Sector: TDSKSector;
begin
  Sector := GetSelectedSector(popSector.PopupComponent);
  if (Sector <> nil) and (ConfirmChange('format', 'sector')) then
  begin
    Sector.DataSize := Sector.ParentTrack.SectorSize;
    Sector.FillSector(Sector.ParentTrack.Filler);
  end;

  // TODO: Format track would require more details

  UpdateMenus;
  RefreshList;
end;

procedure TfrmMain.itmSectorUnformatClick(Sender: TObject);
var
  Sector: TDSKSector;
begin
  Sector := GetSelectedSector(popSector.PopupComponent);

  if (Sector <> nil) and (ConfirmChange('unformat', 'sector')) then
    Sector.Unformat;

  RefreshList;
  UpdateMenus;
end;

procedure TfrmMain.itmSectorPropertiesClick(Sender: TObject);
var
  Track: TDSKTrack;
  Sector: TDSKSector;
begin
  Sector := GetSelectedSector(popSector.PopupComponent);

  if Sector <> nil then
    TfrmSectorProperties.Create(Self, Sector);

  if (popSector.PopupComponent = tvwMain) and (tvwMain.Selected <> nil) then
    if TObject(tvwMain.Selected.Data).ClassType = TDSKTrack then
    begin
      Track := TDSKTrack(tvwMain.Selected.Data);
      for Sector in Track.Sector do
        TfrmSectorProperties.Create(Self, Sector);
    end;

  UpdateMenus;
end;

function TfrmMain.ConfirmChange(Action: string; Upon: string): boolean;
begin
  if not Settings.WarnSectorChange then
  begin
    Result := True;
    exit;
  end;
  Result := MessageDlg('You are about to ' + Action + ' this ' +
    Upon + '. ' + CR + CR + 'Do you know what you are doing?', mtWarning,
    [mbYes, mbNo], 0) = mrYes;
end;

function GetListViewAsText(ForListView: TListView): string;
var
  CIdx: integer;
  Item: TListItem;
  SubItem: string;
  SelectAll: boolean;
begin
  Result := '';
  // Headings
  for CIdx := 0 to ForListView.Columns.Count - 1 do
    Result := Result + ForListView.Columns[CIdx].Caption + TAB;
  Result := Result + CRLF;

  // Details
  SelectAll := ForListView.Selected = nil;
  for Item in ForListView.Items do
    if Item.Selected or SelectAll then
    begin
      Result := Result + Item.Caption + TAB;
      for SubItem in Item.SubItems do
        Result := Result + SubItem + TAB;
      Result := Result + CRLF;
    end;
end;

procedure TfrmMain.itmEditCopyClick(Sender: TObject);
begin
  if DiskMap.Visible then
    itmCopyMapToClipboardClick(Sender)
  else
    Clipboard.AsText := GetListViewAsText(lvwMain);
end;

procedure TfrmMain.itmEditSelectAllClick(Sender: TObject);
begin
  lvwMain.SelectAll;
end;

procedure TfrmMain.itmFindClick(Sender: TObject);
begin
  dlgFind.Execute;
end;

procedure TfrmMain.dlgFindFind(Sender: TObject);
var
  StartSector, FoundSector: TDSKSector;
  Node: TTreeNode;
  Obj: TObject;
begin
  if tvwMain.Selected.Data = nil then exit;

  // Find out where to start searching
  Obj := TObject(tvwMain.Selected.Data);
  StartSector := nil;
  if Obj.ClassType = TDSKImage then
    StartSector := TDSKImage(Obj).Disk.Side[0].Track[0].Sector[0];
  if Obj.ClassType = TDSKDisk then
    StartSector := TDSKDisk(Obj).Side[0].Track[0].Sector[0];
  if Obj.ClassType = TDSKSide then
    StartSector := TDSKSide(Obj).Track[0].Sector[0];
  if Obj.ClassType = TDSKTrack then
    StartSector := TDSKTrack(Obj).Sector[0];
  if Obj.ClassType = TDSKSector then
    StartSector := TDSKSector(Obj);

  if StartSector = nil then
    exit;

  FoundSector := StartSector.ParentTrack.ParentSide.ParentDisk.ParentImage.FindText(
    StartSector, dlgFind.FindText, frMatchCase in dlgFind.Options);

  if FoundSector <> nil then
  begin
    for Node in tvwMain.Items do
      if Node.Data = FoundSector then
        tvwMain.Selected := Node;
  end;
end;

procedure TfrmMain.itmFindNextClick(Sender: TObject);
begin
  dlgFindFind(Sender);
end;

procedure TfrmMain.tvwMainDblClick(Sender: TObject);
begin
  itmSectorPropertiesClick(Sender);
end;

// Select the node under the cursor on right-click so context-menu actions
// operate on the clicked node rather than the previously selected one
procedure TfrmMain.tvwMainMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  Node: TTreeNode;
begin
  if Button = mbRight then
  begin
    Node := tvwMain.GetNodeAt(X, Y);
    if Node <> nil then
      Node.Selected := True;
  end;
end;

procedure TfrmMain.ShowFile(Sender: TObject);
var
  DiskFile: TCPMFile;
  DiskImage: TDSKImage;
  DiskName: string;
begin
  // Check if a file is selected and it's a TCPMFile
  if (lvwMain.Selected = nil) or (lvwMain.Selected.Data = nil) then
    Exit;

  if TObject(lvwMain.Selected.Data).ClassType <> TCPMFile then
    Exit;

  DiskFile := TCPMFile(lvwMain.Selected.Data);

  // Get the disk image for the title
  DiskImage := GetCurrentImage;
  if DiskImage <> nil then
    DiskName := ExtractFileName(DiskImage.FileName)
  else
    DiskName := '';

  // Amstrad (AMSDOS) tokenized BASIC files
  if (DiskFile.HeaderType = 'AMSDOS') and (DiskFile.Meta = 'BASIC') then
  begin
    ShowBasicViewer(DiskImage.Disk, DiskFile, DiskName);
    Exit;
  end;

  // Amstrad CPC screen dumps: roughly 16K files (raw screen RAM carries no
  // header, and some carry a few extra bytes spilling into a 17th block), plus
  // Advanced OCP Art Studio screens and .WIN window clips (both optionally
  // MJH-compressed). Compressed files fail the size check, so confirm the data
  // decodes to a screen or window. PLUS3DOS files go to the Spectrum viewers.
  if (DiskFile.HeaderType <> 'PLUS3DOS') and
     (TAmstradScreen.IsValidScreenSize(DiskFile.Size) or
      TAmstradScreen.CanDisplay(DiskFile.GetData(False))) then
  begin
    ShowCPCScreenViewer(DiskImage.Disk, DiskFile, DiskName);
    Exit;
  end;

  // Check for PLUS3DOS files
  if DiskFile.HeaderType <> 'PLUS3DOS' then
    Exit;

  // Check if this is a SCREEN$ file (6912 bytes with color, 6144 bytes without)
  if TSpectrumScreen.IsValidScreenSize(DiskFile.Size - DiskFile.HeaderSize) then
  begin
    ShowZXScreenViewer(DiskImage.Disk, DiskFile, DiskName);
    Exit;
  end;

  // Check if this is a BASIC file
  if DiskFile.Meta.StartsWith('BASIC') then
  begin
    ShowBasicViewer(DiskImage.Disk, DiskFile, DiskName);
    Exit;
  end;

  // Character (string) array, e.g. DATA a$(10) - list one string per line
  if DiskFile.Meta.StartsWith('DATA ') and (Pos('$(', DiskFile.Meta) > 0) then
  begin
    ShowStringArrayViewer(DiskImage.Disk, DiskFile, DiskName);
    Exit;
  end;
end;

procedure TfrmMain.OnApplicationDropFiles(Sender: TObject;
  const FileNames: array of string);
begin
  LoadFiles(FileNames);
end;

end.
