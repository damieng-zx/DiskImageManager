unit ShellDragDrop;

{$MODE Delphi}

{
  Disk Image Manager - Drag files out to other applications

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

  A minimal OLE drag source. Given the paths of files that already exist on
  disk, it lets the user drag them into another application exactly as if they
  had been dragged from Explorer: the target receives a CF_HDROP and copies the
  files. Windows only.
}

interface

// Drag the given existing files out of the application as an Explorer-style
// copy. Blocks until the drag ends. Returns True if the files were dropped
// somewhere that took a copy of them.
function DragFilesAsCopy(const Files: array of string): boolean;

implementation

uses
  Windows, ActiveX, SysUtils;

const
  // Drag-drop HRESULTs and data-object errors the ActiveX unit does not declare
  DRAGDROP_S_DROP = HRESULT($00040100);
  DRAGDROP_S_CANCEL = HRESULT($00040101);
  DRAGDROP_S_USEDEFAULTCURSORS = HRESULT($00040102);
  DV_E_FORMATETC = HRESULT($80040064);
  DV_E_TYMED = HRESULT($80040069);
  DV_E_DVASPECT = HRESULT($8004006B);
  OLE_E_ADVISENOTSUPPORTED = HRESULT($80040003);

type
  // The header a CF_HDROP block starts with, before the file list. Declared
  // here as the RTL does not carry it.
  TDropFiles = record
    pFiles: DWORD;  // offset from the start of this block to the file list
    pt: TPoint;
    fNC: BOOL;
    fWide: BOOL;    // the file list is wide characters
  end;
  PDropFiles = ^TDropFiles;

  // Enumerates the single format the data object offers (CF_HDROP).
  THDropEnumFormat = class(TInterfacedObject, IEnumFORMATETC)
  private
    FIndex: integer;
  public
    function Next(Celt: ULONG; out Rgelt: FORMATETC; pceltFetched: pULONG): HResult; stdcall;
    function Skip(Celt: ULONG): HResult; stdcall;
    function Reset: HResult; stdcall;
    function Clone(out penum: IEnumFORMATETC): HResult; stdcall;
  end;

  // Serves the dragged files as a single CF_HDROP on global memory.
  THDropDataObject = class(TInterfacedObject, IDataObject)
  private
    FData: HGLOBAL;  // the master CF_HDROP block; copies are handed out
  public
    constructor Create(const Files: array of string);
    destructor Destroy; override;
    function GetData(const formatetcIn: FORMATETC; out medium: STGMEDIUM): HRESULT; stdcall;
    function GetDataHere(const pformatetc: FORMATETC; out medium: STGMEDIUM): HRESULT; stdcall;
    function QueryGetData(const pformatetc: FORMATETC): HRESULT; stdcall;
    function GetCanonicalFormatEtc(const pformatetcIn: FORMATETC; out pformatetcOut: FORMATETC): HResult; stdcall;
    function SetData(const pformatetc: FORMATETC; var medium: STGMEDIUM; fRelease: BOOL): HRESULT; stdcall;
    function EnumFormatEtc(dwDirection: DWORD; out enumformatetcpara: IENUMFORMATETC): HRESULT; stdcall;
    function DAdvise(const formatetc: FORMATETC; advf: DWORD; const AdvSink: IAdviseSink; out dwConnection: DWORD): HRESULT; stdcall;
    function DUnadvise(dwconnection: DWORD): HRESULT; stdcall;
    function EnumDAdvise(out enumAdvise: IEnumStatData): HResult; stdcall;
  end;

  // A do-nothing drop source: follow the mouse buttons, use the default cursors.
  THDropSource = class(TInterfacedObject, IDropSource)
  public
    function QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: DWORD): HResult; stdcall;
    function GiveFeedback(dwEffect: DWORD): HResult; stdcall;
  end;

// Describe the one format the data object offers: CF_HDROP, whole content, on
// global memory.
procedure FillHDropFormat(out Fmt: FORMATETC);
begin
  Fmt.CfFormat := CF_HDROP;
  Fmt.Ptd := nil;
  Fmt.dwAspect := DVASPECT_CONTENT;
  Fmt.lindex := -1;
  Fmt.tymed := TYMED_HGLOBAL;
end;

// Build a CF_HDROP global-memory block naming the given files.
function BuildHDrop(const Files: array of string): HGLOBAL;
var
  Idx, TotalChars, Bytes: integer;
  Handle: HGLOBAL;
  Header: PDropFiles;
  Dest: PWideChar;
  Wide: WideString;
begin
  Result := 0;
  TotalChars := 1; // the extra terminator after the last file
  for Idx := 0 to High(Files) do
    TotalChars := TotalChars + Length(WideString(Files[Idx])) + 1;

  Bytes := SizeOf(TDropFiles) + (TotalChars * SizeOf(WideChar));
  Handle := GlobalAlloc(GMEM_MOVEABLE or GMEM_ZEROINIT, Bytes);
  if Handle = 0 then exit;

  Header := GlobalLock(Handle);
  Header^.pFiles := SizeOf(TDropFiles);
  Header^.pt.X := 0;
  Header^.pt.Y := 0;
  Header^.fNC := BOOL(0);
  Header^.fWide := BOOL(1);

  Dest := PWideChar(PByte(Header) + SizeOf(TDropFiles));
  for Idx := 0 to High(Files) do
  begin
    Wide := WideString(Files[Idx]);
    if Length(Wide) > 0 then
    begin
      Move(PWideChar(Wide)^, Dest^, Length(Wide) * SizeOf(WideChar));
      Inc(Dest, Length(Wide));
    end;
    Dest^ := #0;  // terminate this file
    Inc(Dest);
  end;
  Dest^ := #0;    // and the list

  GlobalUnlock(Handle);
  Result := Handle;
end;

// A private copy of a global-memory block, for handing to a caller that will
// free it with ReleaseStgMedium.
function DupGlobal(Source: HGLOBAL): HGLOBAL;
var
  Size: PtrUInt;
  Src, Dst: Pointer;
begin
  Result := 0;
  if Source = 0 then exit;
  Size := GlobalSize(Source);
  Result := GlobalAlloc(GMEM_MOVEABLE, Size);
  if Result = 0 then exit;
  Src := GlobalLock(Source);
  Dst := GlobalLock(Result);
  if (Src <> nil) and (Dst <> nil) then
    Move(Src^, Dst^, Size);
  GlobalUnlock(Result);
  GlobalUnlock(Source);
end;

{ THDropEnumFormat }

function THDropEnumFormat.Next(Celt: ULONG; out Rgelt: FORMATETC; pceltFetched: pULONG): HResult;
begin
  if (Celt >= 1) and (FIndex = 0) then
  begin
    FillHDropFormat(Rgelt);
    FIndex := 1;
    if pceltFetched <> nil then pceltFetched^ := 1;
    Result := S_OK;
  end
  else
  begin
    if pceltFetched <> nil then pceltFetched^ := 0;
    Result := S_FALSE;
  end;
end;

function THDropEnumFormat.Skip(Celt: ULONG): HResult;
begin
  if FIndex + integer(Celt) <= 1 then
  begin
    Inc(FIndex, Celt);
    Result := S_OK;
  end
  else
  begin
    FIndex := 1;
    Result := S_FALSE;
  end;
end;

function THDropEnumFormat.Reset: HResult;
begin
  FIndex := 0;
  Result := S_OK;
end;

function THDropEnumFormat.Clone(out penum: IEnumFORMATETC): HResult;
var
  Copy: THDropEnumFormat;
begin
  Copy := THDropEnumFormat.Create;
  Copy.FIndex := FIndex;
  penum := Copy;
  Result := S_OK;
end;

{ THDropDataObject }

constructor THDropDataObject.Create(const Files: array of string);
begin
  inherited Create;
  FData := BuildHDrop(Files);
end;

destructor THDropDataObject.Destroy;
begin
  if FData <> 0 then GlobalFree(FData);
  inherited Destroy;
end;

function THDropDataObject.GetData(const formatetcIn: FORMATETC; out medium: STGMEDIUM): HRESULT;
begin
  if QueryGetData(formatetcIn) <> S_OK then
  begin
    Result := DV_E_FORMATETC;
    exit;
  end;

  medium.Tymed := TYMED_HGLOBAL;
  medium.HGLOBAL := DupGlobal(FData);
  medium.PUnkForRelease := nil;
  if medium.HGLOBAL = 0 then
    Result := E_OUTOFMEMORY
  else
    Result := S_OK;
end;

function THDropDataObject.GetDataHere(const pformatetc: FORMATETC; out medium: STGMEDIUM): HRESULT;
begin
  Result := DV_E_FORMATETC;
end;

function THDropDataObject.QueryGetData(const pformatetc: FORMATETC): HRESULT;
begin
  if pformatetc.CfFormat <> CF_HDROP then
    Result := DV_E_FORMATETC
  else if (pformatetc.tymed and TYMED_HGLOBAL) = 0 then
    Result := DV_E_TYMED
  else if pformatetc.dwAspect <> DVASPECT_CONTENT then
    Result := DV_E_DVASPECT
  else
    Result := S_OK;
end;

function THDropDataObject.GetCanonicalFormatEtc(const pformatetcIn: FORMATETC; out pformatetcOut: FORMATETC): HResult;
begin
  pformatetcOut.Ptd := nil;
  Result := E_NOTIMPL;
end;

function THDropDataObject.SetData(const pformatetc: FORMATETC; var medium: STGMEDIUM; fRelease: BOOL): HRESULT;
begin
  Result := E_NOTIMPL;
end;

function THDropDataObject.EnumFormatEtc(dwDirection: DWORD; out enumformatetcpara: IENUMFORMATETC): HRESULT;
begin
  if dwDirection = DATADIR_GET then
  begin
    enumformatetcpara := THDropEnumFormat.Create;
    Result := S_OK;
  end
  else
  begin
    enumformatetcpara := nil;
    Result := E_NOTIMPL;
  end;
end;

function THDropDataObject.DAdvise(const formatetc: FORMATETC; advf: DWORD; const AdvSink: IAdviseSink; out dwConnection: DWORD): HRESULT;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function THDropDataObject.DUnadvise(dwconnection: DWORD): HRESULT;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

function THDropDataObject.EnumDAdvise(out enumAdvise: IEnumStatData): HResult;
begin
  Result := OLE_E_ADVISENOTSUPPORTED;
end;

{ THDropSource }

function THDropSource.QueryContinueDrag(fEscapePressed: BOOL; grfKeyState: DWORD): HResult;
begin
  if fEscapePressed then
    Result := DRAGDROP_S_CANCEL
  else if (grfKeyState and (MK_LBUTTON or MK_RBUTTON)) = 0 then
    Result := DRAGDROP_S_DROP  // the button that began the drag was released
  else
    Result := S_OK;
end;

function THDropSource.GiveFeedback(dwEffect: DWORD): HResult;
begin
  Result := DRAGDROP_S_USEDEFAULTCURSORS;
end;

{ Entry point }

function DragFilesAsCopy(const Files: array of string): boolean;
var
  DataObject: IDataObject;
  DropSource: IDropSource;
  Effect: DWORD;
  Started: HRESULT;
  DidInit: boolean;
begin
  Result := False;
  if Length(Files) = 0 then exit;

  // DoDragDrop needs an OLE-initialised thread. The LCL may already have done
  // it, in which case this returns S_FALSE and we still balance it below.
  DidInit := False;
  Started := OleInitialize(nil);
  if Started >= 0 then DidInit := True;
  try
    DataObject := THDropDataObject.Create(Files);
    DropSource := THDropSource.Create;
    Effect := DROPEFFECT_NONE;
    Result := (DoDragDrop(DataObject, DropSource, DROPEFFECT_COPY, @Effect) = DRAGDROP_S_DROP)
      and ((Effect and DROPEFFECT_COPY) <> 0);
  finally
    DataObject := nil;
    DropSource := nil;
    if DidInit then OleUninitialize;
  end;
end;

end.
