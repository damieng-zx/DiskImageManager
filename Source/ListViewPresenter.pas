unit ListViewPresenter;

{$MODE Delphi}

{
  Disk Image Manager - List view presentation

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DskImage, FileSystem, MGTFileSystem, Utils, Settings,
  Classes, SysUtils, ComCtrls, Contnrs, Graphics, LConvEncoding, FGL;

type
  ItemType = (itDisk, itSpecification, itTracksAll, itTrack, itFiles, itSector,
    itAnalyse, itSides, itSide0, itSide1, itDiskCorrupt, itMessages, itStrings);

  TListColumnArray = array of TListColumn;

  TListViewPresenter = class
  private
    FListView: TListView;
    FSettings: TSettings;
    // The file objects the Files views hand to the list as ListItem.Data.
    // The list keeps raw pointers to them, so they must outlive the refresh
    // that created them and are released by ClearOwnedFiles when the list is
    // rebuilt or the presenter goes away.
    FOwnedFiles: TObjectList;

    procedure SetListSimple;
    function AddColumn(Caption: string): TListColumn;
    function AddColumns(Captions: array of string): TListColumnArray;
    function AddListInfo(Key: string; Value: string): TListItem;
    function AddListTrack(Track: TDSKTrack; ShowModulation: boolean;
      ShowDataRate: boolean; ShowBitLength: boolean): TListItem;
    function AddListSector(Sector: TDSKSector; ShowCopies: boolean;
      ShowIndexPointOffsets: boolean): TListItem;
    function AddListSides(Side: TDSKSide): TListItem;
    procedure WriteSectorLine(Offset: integer; SecHex: string; SecData: string);
    function MapByte(Raw: byte): string;
  public
    constructor Create(AListView: TListView; ASettings: TSettings);
    destructor Destroy; override;

    procedure ClearOwnedFiles;
    procedure RefreshImage(Image: TDSKImage);
    procedure RefreshSpecification(Specification: TDSKSpecification);
    procedure RefreshTrack(Side: TDSKSide);
    procedure RefreshSector(Track: TDSKTrack);
    procedure RefreshSectorData(Sector: TDSKSector);
    procedure RefreshFiles(FileSystem: TCPMFileSystem);
    procedure RefreshFilesMGT(FileSystem: TMGTFileSystem);
    procedure RefreshMessages(Messages: TStringList);
  end;

implementation

constructor TListViewPresenter.Create(AListView: TListView; ASettings: TSettings);
begin
  inherited Create;
  FListView := AListView;
  FSettings := ASettings;
  FOwnedFiles := TObjectList.Create(True);
end;

destructor TListViewPresenter.Destroy;
begin
  FOwnedFiles.Free;
  FListView := nil;
  FSettings := nil;
  inherited Destroy;
end;

// Release the file objects behind the current list contents. Call this as the
// list is cleared: any ListItem.Data still pointing at them is about to go.
procedure TListViewPresenter.ClearOwnedFiles;
begin
  FOwnedFiles.Clear;
end;

procedure TListViewPresenter.SetListSimple;
begin
  FListView.ShowColumnHeaders := False;
  with FListView.Columns do
  begin
    Clear;
    with Add do
      Caption := 'Key';
    with Add do
      Caption := 'Value';
  end;
end;

function TListViewPresenter.AddColumn(Caption: string): TListColumn;
begin
  Result := FListView.Columns.Add;
  Result.Caption := Caption;
  Result.Alignment := taRightJustify;
end;

function TListViewPresenter.AddColumns(Captions: array of string): TListColumnArray;
var
  CIdx: integer;
begin
  Result := TListColumnArray.Create;
  SetLength(Result, Length(Captions));
  for CIdx := 0 to Length(Captions) - 1 do
    Result[CIdx] := AddColumn(Captions[CIdx]);
end;

function TListViewPresenter.AddListInfo(Key: string; Value: string): TListItem;
var
  NewListItem: TListItem;
begin
  NewListItem := FListView.Items.Add;
  with NewListItem do
  begin
    Caption := Key;
    SubItems.Add(Value);
  end;
  Result := NewListItem;
end;

function TListViewPresenter.AddListTrack(Track: TDSKTrack; ShowModulation: boolean;
  ShowDataRate: boolean; ShowBitLength: boolean): TListItem;
var
  NewListItem: TListItem;
begin
  NewListItem := FListView.Items.Add;
  with NewListItem do
  begin
    Caption := StrInt(Track.Logical);
    Data := Track;
    with SubItems do
    begin
      Add(StrInt(Track.Track));
      Add(StrInt(Track.Size));
      Add(StrInt(Track.Sectors));
      if (Track.ParentSide.ParentDisk.ParentImage.FileFormat = diStandardDSK) then
        Add(StrInt(Track.SectorSize));
      Add(StrInt(Track.GapLength));
      Add(StrHex(Track.Filler));
      if ShowModulation then Add(DSKRecordingMode[Track.RecordingMode]);
      if ShowDataRate then Add(DSKDataRate[Track.DataRate]);
      if ShowBitLength then Add(StrInt(Track.BitLength div 8));
      Add('');
    end;
  end;
  Result := NewListItem;
end;

function TListViewPresenter.AddListSector(Sector: TDSKSector; ShowCopies: boolean;
  ShowIndexPointOffsets: boolean): TListItem;
var
  NewListItem: TListItem;
begin
  NewListItem := FListView.Items.Add;
  with NewListItem do
  begin
    Caption := StrInt(Sector.Sector);
    Data := Sector;
    with SubItems do
    begin
      Add(StrInt(Sector.Track));
      Add(StrInt(Sector.Side));
      Add(StrInt(Sector.ID));
      Add(Format('%d (%d)', [Sector.FDCSize, FDCSectorSizes[Sector.FDCSize]]));
      Add(Format('%d, %d', [Sector.FDCStatus[1], Sector.FDCStatus[2]]));
      if (Sector.DataSize <> Sector.AdvertisedSize) then
        Add(Format('%d (%d)', [Sector.DataSize, Sector.AdvertisedSize]))
      else
        Add(StrInt(Sector.DataSize));
      if ShowCopies then
        Add(StrInt(Sector.GetCopyCount));
      if ShowIndexPointOffsets then
        Add('+' + StrInt(Sector.IndexPointOffset));
      Add(DSKSectorStatus[Sector.Status]);
    end;
  end;
  Result := NewListItem;
end;

function TListViewPresenter.AddListSides(Side: TDSKSide): TListItem;
var
  NewListItem: TListItem;
begin
  NewListItem := FListView.Items.Add;
  with NewListItem do
  begin
    Caption := StrInt(Side.Side + 1);
    SubItems.Add(StrInt(Side.Tracks));
    Data := Side;
  end;
  Result := NewListItem;
end;

procedure TListViewPresenter.WriteSectorLine(Offset: integer; SecHex: string; SecData: string);
begin
  with FListView.Items.Add do
  begin
    Caption := StrInt(Offset);
    Subitems.Add(SecHex);
    Subitems.Add(SecData);
  end;
end;

function TListViewPresenter.MapByte(Raw: byte): string;
begin
  if Raw <= 31 then
  begin
    Result := FSettings.UnknownASCII;
    exit;
  end;

  Result := Chr(Raw);
  if (FSettings.Mapping = 'None') and (Raw > 127) then Result := FSettings.UnknownASCII;
  if (FSettings.Mapping = '437') then Result := CP437ToUTF8(Result);
  if (FSettings.Mapping = '850') then Result := CP850ToUTF8(Result);
  if (FSettings.Mapping = '1252') then Result := CP1252ToUTF8(Result);
end;

procedure TListViewPresenter.RefreshImage(Image: TDSKImage);
var
  SIdx: integer;
  Side: TDSKSide;
  ImageFormat, Protection, Features: string;
begin
  SetListSimple;
  if Image <> nil then
    with Image do
    begin
      AddListInfo('Creator', Creator);

      ImageFormat := DSKImageFormats[FileFormat];
      if Image.HasV5Extensions then
        if Image.HasOffsetInfo then
          ImageFormat := ImageFormat + ' (SAMdisk)'
        else
          ImageFormat := ImageFormat + ' (v5)';

      if Corrupt then ImageFormat := ImageFormat + ' (Corrupt)';
      AddListInfo('Image Format', ImageFormat);

      Features := '';
      for Side in Image.Disk.Side do
      begin
        if Side.HasDataRate then Features := Features + 'Data Rate, ';
        if Side.HasRecordingMode then Features := Features + 'Recording Mode, ';
        if Side.HasVariantSectors then Features := Features + 'Variant Sectors, ';
        if HasOffsetInfo then Features := Features + 'Offset-Info, ';
      end;
      if not Features.IsEmpty then
        AddListInfo('Features', Features.Substring(0, Features.Length - 2));

      AddListInfo('Sides', StrInt(Disk.Sides));
      if Disk.Sides > 0 then
      begin
        if Disk.Sides > 1 then
        begin
          for SIdx := 0 to Disk.Sides - 1 do
            AddListInfo(SysUtils.Format('Tracks on side %d', [SIdx]),
              StrInt(Disk.Side[SIdx].Tracks));
        end;
        AddListInfo('Tracks total', StrInt(Disk.TrackTotal));
        AddListInfo('Formatted capacity', SysUtils.Format('%d KB',
          [Disk.FormattedCapacity div BytesPerKB]));
        if Disk.IsTrackSizeUniform then
          AddListInfo('Track size', SysUtils.Format('%d bytes',
            [Disk.Side[0].Track[0].Size]))
        else
          AddListInfo('Largest track size', SysUtils.Format('%d bytes',
            [Disk.Side[0].GetLargestTrackSize()]));
        if Disk.IsUniform(False) then
          AddListInfo('Uniform layout', 'Yes')
        else
        if Disk.IsUniform(True) then
          AddListInfo('Uniform layout', 'Yes (except empty tracks)')
        else
          AddListInfo('Uniform layout', 'No');
        AddListInfo('Format analysis', Disk.DetectFormat);
        Protection := Disk.DetectCopyProtection();
        if Protection <> '' then
          AddListInfo('Copy protection', Protection);
        if Disk.BootableOn <> '' then
          AddListInfo('Boot sector', Disk.BootableOn)
        else
          AddListInfo('Boot sector', 'Unknown');
        if disk.HasFDCErrors then
          AddListInfo('FDC errors', 'Yes')
        else
          AddListInfo('FDC errors', 'No');
        if IsChanged then
          AddListInfo('Is changed', 'Yes')
        else
        begin
          AddListInfo('Is changed', 'No');
          AddListInfo('File size', StrFileSize(FileSize));
        end;
      end;
    end;
end;

procedure TListViewPresenter.RefreshSpecification(Specification: TDSKSpecification);
begin
  SetListSimple;
  Specification.Identify;
  AddListInfo('Format', DSKSpecFormats[Specification.Format]);
  if Specification.Format <> dsFormatInvalid then
  begin
    AddListInfo('Source', Specification.Source);
    AddListInfo('Sided', DSKSpecSides[Specification.Side]);
    AddListInfo('Track mode', DSKSpecTracks[Specification.Track]);
    AddListInfo('Tracks/side', StrInt(Specification.TracksPerSide));
    AddListInfo('Sectors/track', StrInt(Specification.SectorsPerTrack));
    AddListInfo('Directory blocks', StrInt(Specification.DirectoryBlocks));
    AddListInfo('Allocation size', DSKSpecAllocations[Specification.AllocationSize]);
    AddListInfo('Reserved tracks', StrInt(Specification.ReservedTracks));
    AddListInfo('Gap (format)', StrInt(Specification.GapFormat));
    AddListInfo('Gap (read/write)', StrInt(Specification.GapReadWrite));
    AddListInfo('Sector size', StrInt(Specification.SectorSize));
    AddListInfo('Block shift', StrInt(Specification.BlockShift));
    AddListInfo('Block size', StrInt(Specification.GetBlockSize));
    AddListInfo('Block count', StrInt(Specification.GetBlockCount));
    AddListInfo('Records per track', StrInt(Specification.GetRecordsPerTrack));
    AddListInfo('Usable capacity', StrFileSize(Specification.GetUsableCapacity));
  end;
end;

procedure TListViewPresenter.RefreshTrack(Side: TDSKSide);
var
  Track: TDSKTrack;
  ShowModulation, ShowDataRate, ShowBitLength: boolean;
begin
  ShowModulation := Side.HasRecordingMode;
  ShowDataRate := Side.HasDataRate;
  ShowBitLength := Side.HasBitLength;

  AddColumn('Logical');
  AddColumn('Physical');
  AddColumn('Track size');
  AddColumn('Sectors');
  if (Side.ParentDisk.ParentImage.FileFormat = diStandardDSK) then
    AddColumn('Sector size');
  AddColumn('Gap');
  AddColumn('Filler');
  if ShowModulation then AddColumn('Modulation');
  if ShowDataRate then AddColumn('Data rate');
  if ShowBitLength then AddColumn('Bit length');
  AddColumn('');

  for Track in Side.Track do
    AddListTrack(Track, ShowModulation, ShowDataRate, ShowBitLength);
end;

procedure TListViewPresenter.RefreshSector(Track: TDSKTrack);
var
  Sector: TDSKSector;
begin
  AddColumns(['Sector', 'Track', 'Side', 'ID', 'FDC size', 'FDC flags', 'Data size']);

  if Track.HasMultiSectoredSector then
    AddColumn('Copies');

  if Track.HasIndexPointOffsets then
    AddColumn('Index Point');

  with FListView.Columns.Add do
    Caption := 'Status';

  for Sector in Track.Sector do
    AddListSector(Sector, Track.HasMultiSectoredSector, Track.HasIndexPointOffsets);
end;

procedure TListViewPresenter.RefreshSectorData(Sector: TDSKSector);
var
  Idx, RowOffset, Offset, TrueSectorSize, VariantNumber: integer;
  Raw: byte;
  HasVariants: boolean;
  RowData, RowHex: string;
begin
  FListView.Font := FSettings.SectorFont;
  // A hex dump is a sequence, not a table of rows that stand alone: the variant
  // markers below label the lines that follow them, so it must not be sorted
  FListView.SortType := stNone;

  with FListView.Columns do
  begin
    BeginUpdate;
    Clear;
    with Add do
    begin
      Caption := 'Off';
      Alignment := taRightJustify;
    end;
    with Add do
      Caption := 'Hex';
    with Add do
      Caption := 'ASCII';
  end;

  RowOffset := 0;
  RowData := '';
  RowHex := '';

  HasVariants := Sector.GetCopyCount > 1;
  TrueSectorSize := FDCSectorSizes[Sector.FDCSize];
  VariantNumber := 0;

  Offset := 0;

  for Idx := 0 to Sector.DataSize - 1 do
  begin
    // If we're starting a new sector variant label it
    if HasVariants and (Idx mod TrueSectorSize = 0) then
      with FListView.Items.Add do
      begin
        Inc(VariantNumber);
        Subitems.Add('Sector variant #' + IntToStr(VariantNumber));
      end;

    // Emit a new line every X bytes depending on setting
    if (Offset mod FSettings.BytesPerLine = 0) and (Offset > 0) then
    begin
      WriteSectorLine(RowOffset, RowHex, RowData);
      RowOffset := Offset;
      RowData := '';
      RowHex := '';
    end;

    // Gather up the data for the next line we'll write
    Raw := Sector.Data[Idx];
    RowData := RowData + MapByte(Raw);
    RowHex := RowHex + StrHex(Raw) + ' ';
    Inc(Offset);

    // Flush and reset the offset for every variant sector
    if HasVariants and (Offset = TrueSectorSize) then
    begin
      WriteSectorLine(RowOffset, RowHex, RowData);
      RowOffset := 0;
      RowData := '';
      RowHex := '';
      Offset := 0;
    end;
  end;

  // Flush any leftover gathered data
  if RowData <> '' then
    WriteSectorLine(RowOffset, RowHex, RowData);
end;

procedure TListViewPresenter.RefreshFiles(FileSystem: TCPMFileSystem);
var
  DiskFile: TCPMFile;
  Files: TFPGList<TCPMFile>;
  Attributes: string;
  HasHeaders, HasUserAreas: boolean;
begin
  HasHeaders := False;
  HasUserAreas := False;
  Files := FileSystem.Directory;

  for DiskFile in Files do
  begin
    FOwnedFiles.Add(DiskFile);
    if DiskFile.User > 0 then HasUserAreas := True;
    if DiskFile.HeaderType <> 'None' then HasHeaders := True;
  end;

  with FListView.Columns do
  begin
    with Add do
      Caption := 'File name';
    if HasUserAreas then
      with Add do
      begin
        Caption := 'User Area';
        Alignment := taRightJustify;
      end;

    with Add do
    begin
      Caption := 'Index';
      Alignment := taRightJustify;
    end;
    with Add do
    begin
      Caption := 'Blocks';
      Alignment := taRightJustify;
    end;
    with Add do
    begin
      Caption := 'Allocated';
      Alignment := taRightJustify;
    end;
    with Add do
    begin
      Caption := 'Actual';
      Alignment := taRightJustify;
    end;
    with Add do
      Caption := 'Attributes';

    if HasHeaders then
    begin
      with Add do
        Caption := 'Header';
      with Add do
        Caption := 'Checksum';
      with Add do
        Caption := 'Meta';
    end;
  end;

  with FListView do
  begin
    BeginUpdate;
    Items.Clear;
    for DiskFile in Files do
      with Items.Add do
      begin
        Data := DiskFile;
        Caption := DiskFile.FileName;
        if HasUserAreas then SubItems.Add(StrInt(DiskFile.User));
        SubItems.Add(StrInt(DiskFile.EntryIndex));
        SubItems.Add(StrInt(DiskFile.Blocks.Count));
        SubItems.Add(StrFileSize(DiskFile.SizeOnDisk));
        SubItems.Add(StrFileSize(DiskFile.Size));
        Attributes := '';
        if (DiskFile.ReadOnly) then Attributes := Attributes + 'R';
        if (DiskFile.System) then Attributes := Attributes + 'S';
        if (DiskFile.Archived) then Attributes := Attributes + 'A';
        SubItems.Add(Attributes);
        if HasHeaders then
        begin
          SubItems.Add(DiskFile.HeaderType);
          SubItems.Add(StrYesNo(DiskFile.Checksum));
          SubItems.Add(DiskFile.Meta);
        end;
      end;
    EndUpdate;
  end;

  // The list container only: the entries themselves belong to FOwnedFiles now
  Files.Free;
end;

procedure TListViewPresenter.RefreshFilesMGT(FileSystem: TMGTFileSystem);
var
  DiskFile: TMGTFile;
  Files: TFPGList<TMGTFile>;
begin
  Files := FileSystem.Directory;

  for DiskFile in Files do
    FOwnedFiles.Add(DiskFile);

  with FListView.Columns do
  begin
    with Add do
      Caption := 'File name';
    with Add do
    begin
      Caption := 'Sectors';
      Alignment := taRightJustify;
    end;
    with Add do
    begin
      Caption := 'Allocated';
      Alignment := taRightJustify;
    end;
    with Add do
      Caption := 'Meta';
  end;

  with FListView do
  begin
    BeginUpdate;
    Items.Clear;
    for DiskFile in Files do
      with Items.Add do
      begin
        Data := DiskFile;
        Caption := DiskFile.FileName;
        SubItems.Add(StrInt(DiskFile.SectorsAllocated));
        SubItems.Add(StrFileSize(DiskFile.AllocatedSize));
        SubItems.Add(DiskFile.Meta);
      end;
    EndUpdate;
  end;

  // The list container only: the entries themselves belong to FOwnedFiles now
  Files.Free;
end;

procedure TListViewPresenter.RefreshMessages(Messages: TStringList);
var
  Message: string;
begin
  SetListSimple;
  if Messages <> nil then
    for Message in Messages do
      AddListInfo('', Message);
end;

end.
