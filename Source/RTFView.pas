unit RTFView;

{$MODE Delphi}

{
  Disk Image Manager - Minimal RichEdit viewer wrapper

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  Windows, Messages, Classes, SysUtils, RichEdit;

type
  // A read only rich edit control. Text it holds hidden is an escape, such as the
  // backslash that goes with an underlined user defined graphic: it is not shown,
  // but copying includes it.
  TRTFViewer = class
  private
    class var FLibHandle: HMODULE;
    class procedure LoadRichEditLib;
  private
    FHandle: HWND;
    FControlProc: Pointer;
    function SelectionHasHidden: boolean;
    function IsHidden(Position: integer): boolean;
    procedure Select(const Range: TCharRange);
    function SelectedText(const Range: TCharRange): UnicodeString;
    procedure CopySelection;
  public
    constructor Create(AParentHandle: HWND);
    destructor Destroy; override;
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: integer);
    procedure LoadRTF(const RTFContent: AnsiString);
    property Handle: HWND read FHandle;
  end;

implementation

type
  TSetTextEx = record
    flags: DWORD;
    codepage: UINT;
  end;

const
  EM_SETTEXTEX = WM_USER + 97;
  EM_GETSCROLLPOS = WM_USER + 221;
  EM_SETSCROLLPOS = WM_USER + 222;
  ST_DEFAULT = 0;
  CP_ACP = 0;
  // The window property holding the viewer a control belongs to
  ViewerProperty = 'DiskImageManager.RTFViewer';

procedure PutTextOnClipboard(Owner: HWND; const Text: UnicodeString);
var
  Block: HGLOBAL;
  Size: integer;
begin
  Size := (Length(Text) + 1) * SizeOf(widechar);
  if not OpenClipboard(Owner) then
    Exit;
  try
    EmptyClipboard;
    Block := GlobalAlloc(GMEM_MOVEABLE, Size);
    if Block = 0 then
      Exit;
    Move(PWideChar(Text)^, GlobalLock(Block)^, Size);
    GlobalUnlock(Block);
    // The clipboard owns the block from here, unless it will not take it
    if SetClipboardData(CF_UNICODETEXT, Block) = 0 then
      GlobalFree(Block);
  finally
    CloseClipboard;
  end;
end;

// Stands in front of the control's own window procedure to take over copying
function ViewerProc(Wnd: HWND; Msg: UINT; W: WPARAM; L: LPARAM): LRESULT; stdcall;
var
  Viewer: TRTFViewer;
begin
  Viewer := TRTFViewer(GetPropW(Wnd, ViewerProperty));
  // The control copies on these keys without sending itself WM_COPY. Control
  // with Alt is AltGr, which types characters.
  if (Msg = WM_COPY) or ((Msg = WM_KEYDOWN) and
    ((W = Ord('C')) or (W = VK_INSERT)) and
    (GetKeyState(VK_CONTROL) < 0) and (GetKeyState(VK_MENU) >= 0)) then
  begin
    Viewer.CopySelection;
    Exit(0);
  end;
  Result := CallWindowProcW(Viewer.FControlProc, Wnd, Msg, W, L);
end;

// Whether any of the selection is hidden. The control clears the mask for an
// attribute that is not the same throughout. Only the longer of its two format
// records says whether text is hidden.
function TRTFViewer.SelectionHasHidden: boolean;
var
  Format: TCharFormat2W;
begin
  FillChar(Format, SizeOf(Format), 0);
  Format.cbSize := SizeOf(Format);
  SendMessageW(FHandle, EM_GETCHARFORMAT, SCF_SELECTION, LPARAM(@Format));
  Result := (Format.dwMask and CFM_HIDDEN = 0) or
    (Format.dwEffects and CFE_HIDDEN <> 0);
end;

function TRTFViewer.IsHidden(Position: integer): boolean;
var
  Range: TCharRange;
begin
  Range.cpMin := Position;
  Range.cpMax := Position + 1;
  Select(Range);
  Result := SelectionHasHidden;
end;

procedure TRTFViewer.Select(const Range: TCharRange);
begin
  SendMessageW(FHandle, EM_EXSETSEL, 0, LPARAM(@Range));
end;

// The text of the selection, which is the given range, hidden text and all
function TRTFViewer.SelectedText(const Range: TCharRange): UnicodeString;
var
  Buffer: array of widechar;
begin
  SetLength(Buffer, Range.cpMax - Range.cpMin + 1);
  SendMessageW(FHandle, EM_GETSELTEXT, 0, LPARAM(@Buffer[0]));
  // The control ends each line with a carriage return alone
  Result := UnicodeStringReplace(PWideChar(@Buffer[0]), #13, #13#10,
    [rfReplaceAll]);
end;

procedure TRTFViewer.CopySelection;
var
  Chosen, Wanted: TCharRange;
  Scroll: TPoint;
begin
  SendMessageW(FHandle, EM_EXGETSEL, 0, LPARAM(@Chosen));
  if Chosen.cpMax <= Chosen.cpMin then
    Exit;

  // The selection is moved about below, none of which is to be seen
  SendMessageW(FHandle, EM_GETSCROLLPOS, 0, LPARAM(@Scroll));
  SendMessageW(FHandle, WM_SETREDRAW, 0, 0);
  try
    Wanted := Chosen;
    // The caret steps over hidden text, so a selection starting at an escaped
    // character leaves its escape behind, and one stopping just short of such a
    // character can take the escape without it
    if (Wanted.cpMin > 0) and IsHidden(Wanted.cpMin - 1) then
      Dec(Wanted.cpMin);
    if IsHidden(Wanted.cpMax - 1) then
      Dec(Wanted.cpMax);

    if Wanted.cpMax > Wanted.cpMin then
    begin
      Select(Wanted);
      // Escaped text goes as plain text only, so that the escapes show wherever
      // it is pasted. Anything else is the control's to copy, formatting and all.
      if SelectionHasHidden then
        PutTextOnClipboard(FHandle, SelectedText(Wanted))
      else
        CallWindowProcW(FControlProc, FHandle, WM_COPY, 0, 0);
    end;
  finally
    Select(Chosen);
    SendMessageW(FHandle, EM_SETSCROLLPOS, 0, LPARAM(@Scroll));
    SendMessageW(FHandle, WM_SETREDRAW, 1, 0);
    InvalidateRect(FHandle, nil, True);
  end;
end;

class procedure TRTFViewer.LoadRichEditLib;
begin
  if FLibHandle = 0 then
    FLibHandle := LoadLibrary('riched20.dll');
end;

constructor TRTFViewer.Create(AParentHandle: HWND);
begin
  inherited Create;
  LoadRichEditLib;
  FHandle := CreateWindowExW(
    WS_EX_CLIENTEDGE,
    'RICHEDIT20W',
    nil,
    WS_CHILD or WS_VISIBLE or WS_VSCROLL
      or ES_MULTILINE or ES_READONLY,
    0, 0, 100, 100,
    AParentHandle,
    0,
    HInstance,
    nil
  );
  if FHandle <> 0 then
  begin
    SetPropW(FHandle, ViewerProperty, THandle(Self));
    FControlProc := Pointer(SetWindowLongPtrW(FHandle, GWLP_WNDPROC,
      LONG_PTR(@ViewerProc)));
  end;
end;

destructor TRTFViewer.Destroy;
begin
  if FHandle <> 0 then
  begin
    // The control outlives this object until destroyed, so give it its own back
    if FControlProc <> nil then
      SetWindowLongPtrW(FHandle, GWLP_WNDPROC, LONG_PTR(FControlProc));
    RemovePropW(FHandle, ViewerProperty);
    DestroyWindow(FHandle);
  end;
  inherited;
end;

procedure TRTFViewer.SetBounds(ALeft, ATop, AWidth, AHeight: integer);
begin
  if FHandle <> 0 then
    MoveWindow(FHandle, ALeft, ATop, AWidth, AHeight, True);
end;

procedure TRTFViewer.LoadRTF(const RTFContent: AnsiString);
var
  STE: TSetTextEx;
begin
  if FHandle = 0 then
    Exit;

  // Temporarily remove ES_READONLY so we can set text
  SetWindowLongW(FHandle, GWL_STYLE,
    GetWindowLongW(FHandle, GWL_STYLE) and not ES_READONLY);

  STE.flags := ST_DEFAULT;
  STE.codepage := CP_ACP;
  Windows.SendMessageA(FHandle, EM_SETTEXTEX,
    WPARAM(@STE), LPARAM(PAnsiChar(RTFContent)));

  // Restore ES_READONLY
  SetWindowLongW(FHandle, GWL_STYLE,
    GetWindowLongW(FHandle, GWL_STYLE) or ES_READONLY);
end;

end.
