unit DiskMap;

{
  Disk Image Manager -  Copyright 2002-2023 Envy Technologies Ltd.

  Disk map graphical component
}

interface

uses
  DskImage, Utils,
  Forms, SysUtils, Classes, Controls, Graphics, GraphUtil, Types,
  IntfGraphics, FPImage;

type
  TSectorClickEvent = procedure(Sender: TObject; Sector: TDSKSector) of object;
  TTrackClickEvent = procedure(Sender: TObject; Track: TDSKTrack) of object;

  TDiskMapHitKind = (hkSector, hkTrack);

  TDiskMapHit = record
    Bounds: TRect;
    Kind: TDiskMapHitKind;
    Sector: TDSKSector;
    Track: TDSKTrack;
    Side: integer;
    TrackIndex: integer;
    SectorIndex: integer;
  end;

  TSpinDiskMap = class(TGraphicControl)
  private
    FBevelWidth: integer;
    FBorderStyle: TSpinBorderStyle;
    FDarkBlankSectors: boolean;
    FGridColor: TColor;
    FSide: TDSKSide;
    FTrackMark: integer;
    FHits: array of TDiskMapHit;
    FHasHover: boolean;
    FHoverHit: TDiskMapHit;
    FHoverPos: TPoint;
    FOnSectorClick: TSectorClickEvent;
    FOnTrackClick: TTrackClickEvent;
    function GetMaxSectors: integer;
    procedure SetBorderStyle(NewBorderStyle: TSpinBorderStyle);
    procedure SetDarkBlankSectors(NewDarkBlankSectors: boolean);
    procedure SetGridColor(NewGridColor: TColor);
    procedure SetSide(NewSide: TDSKSide);
    procedure SetTrackMark(NewTrackMark: integer);
    procedure RenderBitmap(BufMap: TBitmap; Rect: TRect; CaptureHits: boolean);
    function HitAtPos(X, Y: integer): integer;
    procedure DrawOverlay(BufMap: TBitmap; const Hit: TDiskMapHit; Anchor: TPoint);
    procedure ClearHover;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: integer); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function CreateImage(SaveWidth: integer; SaveHeight: integer): TBitmap;
    function SaveMap(FileName: TFileName; SaveWidth: integer; SaveHeight: integer): boolean;
  published
    property Align;
    property BorderStyle: TSpinBorderStyle read FBorderStyle write SetBorderStyle;
    property Color;
    property DarkBlankSectors: boolean read FDarkBlankSectors write SetDarkBlankSectors;
    property Font;
    property GridColor: TColor read FGridColor write SetGridColor;
    property ParentFont;
    property PopupMenu;
    property Side: TDSKSide read FSide write SetSide;
    property TrackMark: integer read FTrackMark write SetTrackMark;
    property Visible;
    property OnSectorClick: TSectorClickEvent read FOnSectorClick write FOnSectorClick;
    property OnTrackClick: TTrackClickEvent read FOnTrackClick write FOnTrackClick;
    property OnMouseDown;
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterComponents('DIM', [TSpinDiskMap]);
end;

constructor TSpinDiskMap.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  Color := clAppWorkspace;
  FTrackMark := 5;
  FGridColor := clSilver;
  FBevelWidth := 2;
  FBorderStyle := bsLowered;
  ShowHint := False;
end;

destructor TSpinDiskMap.Destroy;
begin
  inherited Destroy;
end;

procedure TSpinDiskMap.Paint;
var
  BufMap: TBitmap;
  Rect: TRect;
begin
  BufMap := TBitmap.Create;
  try
    BufMap.Height := Height;
    BufMap.Width := Width;
    Rect := ClientRect;

    RenderBitmap(BufMap, Rect, True);

    // Floating overlay for the hovered sector/track, drawn onto the buffer so
    // its translucent shadow blends against the map underneath
    if FHasHover then
      DrawOverlay(BufMap, FHoverHit, FHoverPos);

    BufMap.Canvas.Pen.Style := psSolid;
    Canvas.CopyMode := cmSrcCopy;
    Canvas.Draw(0, 0, BufMap);
    DrawBorder(Canvas, Rect, FBorderStyle);
  finally
    BufMap.Free;
  end;
end;

// Find the hit-region index under a client point, or -1 if none
function TSpinDiskMap.HitAtPos(X, Y: integer): integer;
var
  Idx: integer;
begin
  Result := -1;
  for Idx := 0 to High(FHits) do
    if PtInRect(FHits[Idx].Bounds, Point(X, Y)) then
    begin
      Result := Idx;
      Exit;
    end;
end;

// Draw the custom floating overlay describing a sector or unformatted track,
// as a card anchored near Anchor and kept within the control's client area.
// It is rendered onto BufMap so the translucent drop shadow can be blended
// against the map pixels beneath it.
procedure TSpinDiskMap.DrawOverlay(BufMap: TBitmap; const Hit: TDiskMapHit; Anchor: TPoint);
const
  FDC1Flags: array[0..7] of string = (
    'ID address mark missing', 'Write protected', 'ID missing', '',
    'Over-run', 'ID CRC error', '', 'End of cylinder');
  FDC2Flags: array[0..7] of string = (
    'Data address mark missing', 'Bad cylinder', 'Sector not found',
    'Scan equal satisfied', 'Wrong cylinder', 'Data CRC error',
    'Deleted (control mark)', '');
  PadX = 10;
  PadY = 8;
  RowGap = 4;
  SepPad = 7;            // breathing room above and below each separator
  LabelGap = 12;
  BulletSize = 7;
  ShadowOffset = 5;
  CornerRadius = 8;
  ColHeader = TColor($00303030);
  ColLabel = TColor($00808080);
  ColValue = TColor($00202020);
  ColCard = TColor($00FBFBFB);
  ColBorder = TColor($00B0B0B0);
  ColFlagOk = TColor($00388E3C);  // green
  ColFlagErr = TColor($002020D0);  // red
var
  C: TCanvas;
  Sector: TDSKSector;
  Labels, Values: array of string;
  FlagText: array of string;
  FlagErr: array of boolean;
  Header: string;
  Bit, Idx, RowH, LineH: integer;
  LabelW, ValueW, FlagW, BodyW, CardW, CardH, ContentH, TextBaseY: integer;
  CardX, CardY, TextX, CurY, W: integer;
  HasFlags: boolean;

  procedure AddRow(const ALabel, AValue: string);
  begin
    SetLength(Labels, Length(Labels) + 1);
    SetLength(Values, Length(Values) + 1);
    Labels[High(Labels)] := ALabel;
    Values[High(Values)] := AValue;
  end;

  procedure AddFlag(const AText: string; AnErr: boolean);
  begin
    SetLength(FlagText, Length(FlagText) + 1);
    SetLength(FlagErr, Length(FlagErr) + 1);
    FlagText[High(FlagText)] := AText;
    FlagErr[High(FlagErr)] := AnErr;
  end;

  // Blend a rounded rectangle region of BufMap toward black at 50% (a soft
  // semi-transparent drop shadow) using raw pixel access.
  procedure BlendShadow(R: TRect; Radius: integer);
  var
    Img: TLazIntfImage;
    Col: TFPColor;
    YY, XX, V, Inset, X0, X1: integer;
  begin
    if R.Left < 0 then R.Left := 0;
    if R.Top < 0 then R.Top := 0;
    if R.Right > BufMap.Width then R.Right := BufMap.Width;
    if R.Bottom > BufMap.Height then R.Bottom := BufMap.Height;
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;

    Img := BufMap.CreateIntfImage;
    try
      for YY := R.Top to R.Bottom - 1 do
      begin
        V := 0;
        if YY < R.Top + Radius then
          V := (R.Top + Radius) - YY
        else if YY >= R.Bottom - Radius then
          V := YY - (R.Bottom - 1 - Radius);
        if V < 0 then V := 0;
        if V > Radius then V := Radius;
        Inset := Radius - Round(Sqrt(Radius * Radius - V * V));
        X0 := R.Left + Inset;
        X1 := R.Right - Inset;
        for XX := X0 to X1 - 1 do
        begin
          Col := Img.Colors[XX, YY];
          Col.Red := Col.Red shr 1;
          Col.Green := Col.Green shr 1;
          Col.Blue := Col.Blue shr 1;
          Img.Colors[XX, YY] := Col;
        end;
      end;
      BufMap.LoadFromIntfImage(Img);
    finally
      Img.Free;
    end;
  end;

begin
  C := BufMap.Canvas;
  Sector := Hit.Sector;

  // Build the header and the label/value rows for the hit kind
  if Hit.Kind = hkTrack then
  begin
    Header := Format('Side %d  ·  Track %d', [Hit.Side, Hit.TrackIndex]);
    AddRow('Status', 'Unformatted');
    AddRow('Sectors', '0');
  end
  else
  begin
    Header := Format('Side %d  ·  Track %d  ·  Sector %d',
      [Hit.Side, Hit.TrackIndex, Hit.SectorIndex]);
    AddRow('Sector ID', IntToStr(Sector.ID));
    AddRow('Status', DSKSectorStatus[Sector.Status]);
    AddRow('Size', Format('%d bytes', [Sector.DataSize]));
    AddRow('Index offset', IntToStr(Sector.IndexPointOffset));
    AddRow('FDC status', Format('$%.2x  $%.2x', [Sector.FDCStatus[1], Sector.FDCStatus[2]]));

    // FDC flag lines (genuine errors flagged red, benign markers green)
    for Bit := 0 to 7 do
      if (FDC1Flags[Bit] <> '') and ((Sector.FDCStatus[1] and (1 shl Bit)) <> 0) then
        AddFlag(FDC1Flags[Bit], Bit <> 1);
    for Bit := 0 to 7 do
      if (FDC2Flags[Bit] <> '') and ((Sector.FDCStatus[2] and (1 shl Bit)) <> 0) then
        AddFlag(FDC2Flags[Bit], Bit <> 6);
  end;
  HasFlags := Length(FlagText) > 0;

  // Measure
  C.Font := Self.Font;
  LineH := C.TextHeight('Wg');
  RowH := LineH + RowGap;

  C.Font.Style := [fsBold];
  W := C.TextWidth(Header);
  C.Font.Style := [];

  LabelW := 0;
  ValueW := 0;
  for Idx := 0 to High(Labels) do
  begin
    if C.TextWidth(Labels[Idx]) > LabelW then LabelW := C.TextWidth(Labels[Idx]);
    if C.TextWidth(Values[Idx]) > ValueW then ValueW := C.TextWidth(Values[Idx]);
  end;
  BodyW := LabelW + LabelGap + ValueW;
  if W > BodyW then BodyW := W;

  if HasFlags then
  begin
    FlagW := 0;
    for Idx := 0 to High(FlagText) do
    begin
      W := BulletSize + 6 + C.TextWidth(FlagText[Idx]);
      if W > FlagW then FlagW := W;
    end;
    if FlagW > BodyW then BodyW := FlagW;
  end;

  ContentH := LineH                       // header
    + SepPad + 1 + SepPad                 // separator
    + Length(Labels) * RowH;
  if HasFlags then
    ContentH := ContentH + SepPad + 1 + SepPad + Length(FlagText) * RowH;
  ContentH := ContentH - RowGap;          // no trailing gap after the last row

  CardW := BodyW + PadX * 2;
  CardH := PadY + ContentH + PadY;

  // Position the card near the cursor, flipping to stay inside the control
  CardX := Anchor.X + 18;
  CardY := Anchor.Y + 18;
  if CardX + CardW > ClientWidth - 2 then CardX := Anchor.X - CardW - 6;
  if CardX < 2 then CardX := 2;
  if CardY + CardH > ClientHeight - 2 then CardY := ClientHeight - CardH - 2;
  if CardY < 2 then CardY := 2;

  // Translucent drop shadow, then the opaque card
  BlendShadow(Bounds(CardX + ShadowOffset, CardY + ShadowOffset, CardW, CardH), CornerRadius);
  C.Brush.Style := bsSolid;
  C.Pen.Style := psSolid;
  C.Brush.Color := ColCard;
  C.Pen.Color := ColBorder;
  C.RoundRect(CardX, CardY, CardX + CardW, CardY + CardH, CornerRadius, CornerRadius);

  C.Brush.Style := bsClear;
  TextX := CardX + PadX;
  CurY := CardY + PadY;

  // Header
  C.Font.Style := [fsBold];
  C.Font.Color := ColHeader;
  C.TextOut(TextX, CurY, Header);
  C.Font.Style := [];
  CurY := CurY + LineH + SepPad;

  // Separator
  C.Pen.Color := ColBorder;
  C.Line(TextX, CurY, CardX + CardW - PadX, CurY);
  CurY := CurY + 1 + SepPad;

  // Label/value rows
  for Idx := 0 to High(Labels) do
  begin
    C.Font.Color := ColLabel;
    C.TextOut(TextX, CurY, Labels[Idx]);
    C.Font.Color := ColValue;
    C.TextOut(TextX + LabelW + LabelGap, CurY, Values[Idx]);
    CurY := CurY + RowH;
  end;

  // FDC flag lines with coloured bullets
  if HasFlags then
  begin
    CurY := CurY - RowGap + SepPad;
    C.Pen.Color := ColBorder;
    C.Line(TextX, CurY, CardX + CardW - PadX, CurY);
    CurY := CurY + 1 + SepPad;
    for Idx := 0 to High(FlagText) do
    begin
      TextBaseY := CurY + (LineH - BulletSize) div 2;
      C.Brush.Style := bsSolid;
      if FlagErr[Idx] then
        C.Brush.Color := ColFlagErr
      else
        C.Brush.Color := ColFlagOk;
      C.Pen.Color := C.Brush.Color;
      C.Ellipse(TextX, TextBaseY, TextX + BulletSize, TextBaseY + BulletSize);
      C.Brush.Style := bsClear;
      C.Font.Color := ColValue;
      C.TextOut(TextX + BulletSize + 6, CurY, FlagText[Idx]);
      CurY := CurY + RowH;
    end;
  end;
end;

procedure TSpinDiskMap.ClearHover;
begin
  if FHasHover then
  begin
    FHasHover := False;
    Invalidate;
  end;
end;

procedure TSpinDiskMap.MouseMove(Shift: TShiftState; X, Y: integer);
var
  Idx: integer;
begin
  inherited MouseMove(Shift, X, Y);
  Idx := HitAtPos(X, Y);

  if Idx < 0 then
  begin
    Cursor := crDefault;
    ClearHover;
    Exit;
  end;

  Cursor := crHandPoint;
  if (not FHasHover) or (FHits[Idx].Sector <> FHoverHit.Sector) or
    (FHits[Idx].Track <> FHoverHit.Track) then
  begin
    FHasHover := True;
    FHoverHit := FHits[Idx];
    FHoverPos := Point(X, Y);
    Invalidate;
  end;
end;

procedure TSpinDiskMap.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: integer);
var
  Idx: integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then
    Exit;
  Idx := HitAtPos(X, Y);
  if Idx < 0 then
    Exit;
  ClearHover;
  if (FHits[Idx].Kind = hkTrack) then
  begin
    if Assigned(FOnTrackClick) then
      FOnTrackClick(Self, FHits[Idx].Track);
  end
  else
  if Assigned(FOnSectorClick) then
    FOnSectorClick(Self, FHits[Idx].Sector);
end;

procedure TSpinDiskMap.MouseLeave;
begin
  inherited MouseLeave;
  ClearHover;
end;

procedure TSpinDiskMap.RenderBitmap(BufMap: TBitmap; Rect: TRect; CaptureHits: boolean);
var
  Tracks, TrackIdx, TrackSize: integer;
  Sectors, SectorIdx, SectorSize: integer;
  GRect: TRect;
  X, Y: integer;
  TextH, TextW: integer;
  TextA: string;
  ErrDE, ErrCM: boolean;
  HitCount: integer;
begin
  if CaptureHits then
    SetLength(FHits, 0);
  if Side <> nil then
  begin
    Tracks := Side.Tracks;
    Sectors := GetMaxSectors;
  end
  else
  begin
    Tracks := 40;
    Sectors := 9;
  end;

  with BufMap.Canvas do
  begin
    // Setup the canvas
    Brush.Color := Self.Color;
    FillRect(Rect);

    // Setup for drawing
    Font := Self.Font;
    Pen.Color := clWhite;
    TextH := TextHeight('X');
    TextW := TextWidth('M');
    InflateRect(Rect, -TextW, -TextH);

    // Calculate usable track/sector sizes and new area
    GRect := Rect;
    with GRect do
    begin
      Left := Left + (TextW * 2);
      Bottom := Bottom - TextH;
      Top := TextH div 2;
      Right := Right - TextW;

      if Sectors > 0 then
        SectorSize := (Bottom - Top) div Sectors
      else
        SectorSize := 0;

      if Tracks > 0 then
        TrackSize := (Right - Left) div Tracks
      else
        TrackSize := 0;

      Top := GRect.Bottom - (Sectors * SectorSize);
      Right := GRect.Left + (Tracks * TrackSize);
    end;

    Pen.Color := GridColor;
    // Draw the main grid
    for TrackIdx := 0 to Tracks do
    begin
      X := GRect.Left + (TrackIdx * TrackSize);

      // Track markers
      MoveTo(X, GRect.Bottom);
      LineTo(X, GRect.Top);
      if TrackIdx mod TrackMark = 0 then
      begin
        LineTo(X, GRect.Bottom + TextH);
        TextA := StrInt(TrackIdx);
        TextOut(X + (TrackSize div 2) - (TextW div 2), GRect.Bottom + TextH, TextA);
      end
      else
        LineTo(X, GRect.Bottom + (TextH div 2));

      for SectorIdx := 0 to Sectors do
      begin
        Y := GRect.Bottom - (SectorSize * SectorIdx);

        // Sector markers
        MoveTo(GRect.Left - TextW, Y);
        LineTo(GRect.Right, Y);
        if (TrackIdx = 0) and (SectorIdx < Sectors) then
        begin
          TextA := StrInt(SectorIdx);
          TextOut(GRect.Left - TextWidth(TextA) - TextW, Y - (SectorSize div 2) - (TextHeight(Text) div 2), TextA);
        end;
      end;
    end;

    // Populate the grid
    if Side <> nil then
    begin
      HitCount := 0;
      if CaptureHits then
      begin
        for TrackIdx := 0 to Side.Tracks - 1 do
          if Side.Track[TrackIdx].Sectors = 0 then
            Inc(HitCount)                              // one hit for the empty track
          else
            Inc(HitCount, Side.Track[TrackIdx].Sectors);
        SetLength(FHits, HitCount);
        HitCount := 0;
      end;
      Pen.Style := psClear;
      for TrackIdx := 0 to Side.Tracks - 1 do
      begin
        X := GRect.Left + (TrackIdx * TrackSize);

        // Unformatted track (no sectors): record a track-wide hit region
        if CaptureHits and (Side.Track[TrackIdx].Sectors = 0) then
        begin
          FHits[HitCount].Bounds := Types.Rect(X + 1, GRect.Top, X + TrackSize + 1, GRect.Bottom);
          FHits[HitCount].Kind := hkTrack;
          FHits[HitCount].Sector := nil;
          FHits[HitCount].Track := Side.Track[TrackIdx];
          FHits[HitCount].Side := Side.Side;
          FHits[HitCount].TrackIndex := TrackIdx;
          FHits[HitCount].SectorIndex := -1;
          Inc(HitCount);
        end;

        for SectorIdx := 0 to Side.Track[TrackIdx].Sectors - 1 do
        begin
          Brush.Color := clWhite;
          with Side.Track[TrackIdx].Sector[SectorIdx] do
          begin
            ErrDE := (((FDCStatus[1] and 32) = 32) or ((FDCStatus[2] and 32) = 32));
            ErrCM := ((FDCStatus[2] and 64) = 64);
            if ErrDE then
              Brush.Color := clRed;
            if ErrCM then
              Brush.Color := $00000BBFF;
            if ErrDE and ErrCM then
              Brush.Color := clYellow;
            if (Status <> ssFormattedInUse) and DarkBlankSectors then
              Brush.Color := GetShadowColor(Brush.Color);
          end;
          Y := GRect.Bottom - (SectorIdx * SectorSize);
          Rectangle(X + 1, Y - (SectorSize) + 1, X + (TrackSize) + 1, Y + 1);
          if CaptureHits then
          begin
            FHits[HitCount].Bounds := Types.Rect(X + 1, Y - SectorSize + 1, X + TrackSize + 1, Y + 1);
            FHits[HitCount].Kind := hkSector;
            FHits[HitCount].Sector := Side.Track[TrackIdx].Sector[SectorIdx];
            FHits[HitCount].Track := Side.Track[TrackIdx];
            FHits[HitCount].Side := Side.Side;
            FHits[HitCount].TrackIndex := TrackIdx;
            FHits[HitCount].SectorIndex := SectorIdx;
            Inc(HitCount);
          end;
        end;
      end;
    end;
  end;
end;

// Set the side to analyse
procedure TSpinDiskMap.SetSide(NewSide: TDSKSide);
begin
  if NewSide <> FSide then
  begin
    FSide := NewSide;
    FHasHover := False;
    Invalidate;
  end;
end;

// DarkBlankSectors property changes
procedure TSpinDiskMap.SetDarkBlankSectors(NewDarkBlankSectors: boolean);
begin
  if NewDarkBlankSectors <> FDarkBlankSectors then
  begin
    FDarkBlankSectors := NewDarkBlankSectors;
    Invalidate;
  end;
end;

// TrackMark property change
procedure TSpinDiskMap.SetTrackMark(NewTrackMark: integer);
begin
  if NewTrackMark <> FTrackMark then
  begin
    FTrackMark := NewTrackMark;
    Invalidate;
  end;
end;

// Detect maximum sector number
function TSpinDiskMap.GetMaxSectors: integer;
var
  TrackIdx: integer;
begin
  Result := 0;
  for TrackIdx := 0 to Side.Tracks - 1 do
    if Side.Track[TrackIdx].Sectors > Result then
      Result := Side.Track[TrackIdx].Sectors;
end;

// GridColor property change
procedure TSpinDiskMap.SetGridColor(NewGridColor: TColor);
begin
  if NewGridColor <> FGridColor then
  begin
    FGridColor := NewGridColor;
    Invalidate;
  end;
end;

procedure TSpinDiskMap.SetBorderStyle(NewBorderStyle: TSpinBorderStyle);
begin
  if NewBorderStyle <> FBorderStyle then
  begin
    FBorderStyle := NewBorderStyle;
    Invalidate;
  end;
end;

function TSpinDiskMap.CreateImage(SaveWidth: integer; SaveHeight: integer): TBitmap;
begin
  Result := TBitmap.Create;
  // The caller only takes ownership if this returns, so drop the bitmap if
  // rendering into it fails rather than stranding it
  try
    Result.Width := SaveWidth;
    Result.Height := SaveHeight;
    RenderBitmap(Result, Rect(0, 0, SaveWidth - 1, SaveHeight - 1), False);
  except
    Result.Free;
    raise;
  end;
end;

function TSpinDiskMap.SaveMap(FileName: TFileName; SaveWidth: integer; SaveHeight: integer): boolean;
var
 SaveImage: TBitmap;
begin
  SaveImage := CreateImage(SaveWidth, SaveHeight);
  try
    SaveImage.SaveToFile(FileName);
  finally
    SaveImage.Free;
  end;
  Result := True;
end;

end.
