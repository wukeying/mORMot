unit dddToolsAdminLog;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, StdCtrls, CheckLst, Menus, Grids,
  SynCommons, SynLog, mORMotDDD;

type
  TLogFrame = class(TFrame)
    pnlLeft: TPanel;
    pnlRight: TPanel;
    spl1: TSplitter;
    edtSearch: TEdit;
    btnSearchNext: TButton;
    chklstEvents: TCheckListBox;
    pmFilter: TPopupMenu;
    mmoBottom: TMemo;
    drwgrdEvents: TDrawGrid;
    btnStartLog: TButton;
    tmrRefresh: TTimer;
    edtExistingLogKB: TEdit;
    lblExistingLogKB: TLabel;
    btnStopLog: TButton;
    spl2: TSplitter;
    procedure chklstEventsDrawItem(Control: TWinControl; Index: Integer;
      Rect: TRect; State: TOwnerDrawState);
    procedure chklstEventsClick(Sender: TObject);
    procedure btnStartLogClick(Sender: TObject);
    procedure tmrRefreshTimer(Sender: TObject);
    procedure drwgrdEventsDrawCell(Sender: TObject; ACol, ARow: Integer;
      Rect: TRect; State: TGridDrawState);
    procedure drwgrdEventsClick(Sender: TObject);
    procedure btnSearchNextClick(Sender: TObject);
    procedure chklstEventsDblClick(Sender: TObject);
    procedure btnStopLogClick(Sender: TObject);
  protected
    FLog: TSynLogFile;
    FEventCaption: array[TSynLogInfo] of string;
    FMenuFilterAll: TMenuItem;
    FEventsAllChecked: boolean;
    FEventsSet: TSynLogInfos;
    FLastSearch: RawUTF8;
    FLastSearchSender: TObject;
    procedure EventsCheck;
    procedure pmFilterClick(Sender: Tobject);
    procedure ReceivedOne(const Text: RawUTF8);
    procedure SetListItem(Index: integer; const search: RawUTF8='');
  public
    Admin: IAdministratedDaemon;
    Callback: ISynLogCallback;
    OnLogReceived: function(Sender: TLogFrame; Level: TSynLogInfo;
      const Text: RawUTF8): boolean of object;
    constructor Create(Owner: TComponent); override;
    procedure Closing;
  end;

  TLogFrameClass = class of TLogFrame;

implementation

uses
  dddToolsAdminMain;

{$R *.dfm}

{ TLogFrameCallback }

type
  TLogFrameCallback = class(TInterfacedObject,ISynLogCallback)
  public
    Owner: TLogFrame;
    procedure Log(Level: TSynLogInfo; const Text: RawUTF8);
  end;

procedure TLogFrameCallback.Log(Level: TSynLogInfo; const Text: RawUTF8);
begin
  Owner.ReceivedOne(Text);
  if Assigned(Owner.OnLogReceived) then
    Owner.OnLogReceived(Owner,Level,Text);
end;

const
  LOG_COLORS: array[Boolean,TSynLogInfo] of TColor = (
    (clWhite,$DCC0C0,$DCDCDC,clSilver,$8080C0,$8080FF,$C0DCC0,$DCDCC0,
//  sllNone, sllInfo, sllDebug, sllTrace, sllWarning, sllError, sllEnter, sllLeave,
     $C0C0F0, $C080FF, $C080F0, $C080C0, $C080C0,
//  sllLastError, sllException, sllExceptionOS, sllMemory, sllStackTrace,
     $4040FF, $B08080, $B0B080, $8080DC, $80DC80, $DC8080, $DCFF00, $DCD000,
//  sllFail, sllSQL, sllCache, sllResult, sllDB, sllHTTP, sllClient, sllServer,
     $DCDC80, $DC80DC, $DCDCDC,
//  sllServiceCall, sllServiceReturn, sllUserAuth,
     $D0D0D0, $D0D0DC, $D0D0C0, $D0D0E0, $20E0D0, $8080FF, $DCCDCD, clSilver),
//  sllCustom1, sllCustom2, sllCustom3, sllCustom4, sllNewRun, sllDDDError,sllDDDInfo
    (clBlack,clBlack,clBlack,clBlack,clBlack,clWhite,clBlack,clBlack,
     clWhite,clWhite,clWhite,clBlack,clBlack,
     clWhite,clWhite,clBlack,clWhite,clBlack,clBlack,clBlack,clBlack,
     clBlack,clBlack,clBlack,
     clBlack,clBlack,clBlack,clBlack,clBlack,clWhite,clBlack,clBlack));


procedure TLogFrame.chklstEventsDrawItem(Control: TWinControl;
  Index: Integer; Rect: TRect; State: TOwnerDrawState);
var E: TSynLogInfo;
begin
  if Index<0 then
    exit;
  E := TSynLogInfo(chklstEvents.Items.Objects[Index]);
  with chklstEvents.Canvas do begin
    Brush.Color := LOG_COLORS[false,E];
    Font.Color  := LOG_COLORS[true,E];
    TextRect(Rect,Rect.Left+4,Rect.Top,FEventCaption[E]);
  end;
end;

constructor TLogFrame.Create(Owner: TComponent);
var F: TSynLogFilter;
    M: TMenuItem;
begin
  inherited;
  for F := low(F) to high(F) do begin
    M := TMenuItem.Create(self);
    M.Caption := GetCaptionFromEnum(TypeInfo(TSynLogFilter),Ord(F));
    M.Tag := ord(F);
    M.OnClick := pmFilterClick;
    if F=lfAll then
      FMenuFilterAll := M;
    pmFilter.Items.Add(M);
  end;
  btnStopLogClick(nil);
end;

procedure TLogFrame.btnStopLogClick(Sender: TObject);
var E: TSynLogInfo;
begin
  chklstEvents.Top := 56;
  chklstEvents.Items.Clear;
  for E := succ(sllNone) to high(E) do begin
    FEventCaption[E] := GetCaptionFromEnum(TypeInfo(TSynLogInfo),ord(E));
    chklstEvents.Items.AddObject(FEventCaption[E],pointer(ord(E)));
  end;
  chklstEvents.Height := 8+chklstEvents.Count*chklstEvents.ItemHeight;
  pmFilterClick(FMenuFilterAll);
  if Sender=nil then
    exit;
  btnStartLog.Show;
  btnStopLog.Hide;
  edtExistingLogKB.Show;
  lblExistingLogKB.Show;
  edtSearch.Hide;
  btnSearchNext.Hide;
  drwgrdEvents.RowCount := 0;
  (Owner as TAdminForm).EndLog;
end;

procedure TLogFrame.pmFilterClick(Sender: Tobject);
var F: TSynLogFilter;
    i: integer;
begin
  if not Sender.InheritsFrom(TMenuItem) then
    exit;
  F := TSynLogFilter(TMenuItem(Sender).Tag);
  for i := 0 to chklstEvents.Count-1 do
    chklstEvents.Checked[i] := TSynLogInfo(chklstEvents.Items.Objects[i]) in LOG_FILTER[F];
  chklstEventsClick(nil);
end;

procedure TLogFrame.chklstEventsClick(Sender: TObject);
begin
  if not drwgrdEvents.Visible then
    exit;
  EventsCheck;
end;

procedure TLogFrame.EventsCheck;
var i: integer;
begin
  FEventsAllChecked := true;
  integer(FEventsSet) := 0;
  for i := 0 to chklstEvents.Count-1 do
    if chklstEvents.Checked[i] then
      Include(FEventsSet,TSynLogInfo(chklstEvents.Items.Objects[i])) else
      FEventsAllChecked := false;
end;

procedure TLogFrame.btnStartLogClick(Sender: TObject);
var cb: TLogFrameCallback;
    i: integer;
begin
  EventsCheck;
  if integer(FEventsSet)=0 then
    exit;
  cb := TLogFrameCallback.Create;
  cb.Owner := Self;
  Callback := cb;
  try
    FLog := TSynLogFile.Create;
    Admin.SubscribeLog(FEventsSet,Callback,StrToIntDef(edtExistingLogKB.Text,0));
    chklstEvents.Top := lblExistingLogKB.Top;
    for i := chklstEvents.Count-1 downto 0 do
      if not chklstEvents.Checked[i] then
        chklstEvents.Items.Delete(i);
    chklstEvents.Height := 8+chklstEvents.Count*chklstEvents.ItemHeight;
    btnStopLog.Top := chklstEvents.Top+chklstEvents.Height+8;
    btnStartLog.Hide;
    btnStopLog.Show;
    edtExistingLogKB.Hide;
    lblExistingLogKB.Hide;
    edtSearch.Show;
    btnSearchNext.Show;
    drwgrdEvents.DoubleBuffered := true;
    drwgrdEvents.ColCount := 3;
    drwgrdEvents.ColWidths[0] := 70;
    drwgrdEvents.ColWidths[1] := 60;
    drwgrdEvents.ColWidths[2] := 2000;
    drwgrdEvents.Show;
  except
    Callback := nil;
    FreeAndNil(FLog);
  end;
end;

procedure TLogFrame.ReceivedOne(const Text: RawUTF8);
var withoutThreads: boolean;
    P: PUTF8Char;
    line: RawUTF8;
begin
  if FLog=nil then
    exit;
  P := pointer(Text);
  repeat // handle multiple log rows in the incoming text
    line := GetNextLine(P,P);
    if length(line)<24 then
      continue;
    withoutThreads := FLog.EventThread=nil;
    FLog.AddInMemoryLine(line);
    if withoutThreads and (FLog.EventThread<>nil) then
      tmrRefresh.Tag := 1; 
  until P=nil;
  tmrRefresh.Enabled := true; // MUCH faster than Synchronize() to use a timer
end;

procedure TLogFrame.tmrRefreshTimer(Sender: TObject);
begin
  tmrRefresh.Enabled := false;
  if fLog=nil then
    exit; // avoid GPF
  if tmrRefresh.Tag=1 then begin
    tmrRefresh.Tag := 0;
    drwgrdEvents.ColCount := 4;
    drwgrdEvents.ColWidths[2] := 30;
    drwgrdEvents.ColWidths[3] := 2000;
  end;
  drwgrdEvents.RowCount := FLog.Count;
  drwgrdEvents.TopRow := FLog.Count-drwgrdEvents.VisibleRowCount;
  drwgrdEvents.Invalidate;
end;

const
  TIME_FORMAT: array[boolean] of string = (
    'hh:mm:ss.zzz','hh:mm:ss');

procedure TLogFrame.drwgrdEventsDrawCell(Sender: TObject; ACol,
  ARow: Integer; Rect: TRect; State: TGridDrawState);
var txt: string;
    b: boolean;
    Index: integer;
begin
  with drwgrdEvents.Canvas do
    if FLog=nil then
      FillRect(Rect) else
    if FLog.EventLevel<>nil then begin
      Brush.Style := bsClear;
      if cardinal(ARow)<cardinal(FLog.Count) then begin
        Index := ARow;
        b := (gdFocused in State) or (gdSelected in State);
        if b then
          Brush.Color := clBlack else
          Brush.Color := LOG_COLORS[b,FLog.EventLevel[Index]];
        Font.Color  := LOG_COLORS[not b,FLog.EventLevel[Index]];
        FillRect(Rect);
        case ACol of
        0: DateTimeToString(txt,TIME_FORMAT[FLog.Freq=0],FLog.EventDateTime(Index));
        1: txt := FEventCaption[FLog.EventLevel[Index]];
        2: if FLog.EventThread<>nil then
             txt := IntToString(cardinal(FLog.EventThread[Index])) else
             txt := UTF8ToString(StringReplaceAll(FLog.EventText[Index],#9,'   '));
        3: txt := UTF8ToString(StringReplaceAll(FLog.EventText[Index],#9,'   '));
        end;
        TextOut(Rect.Left+4,Rect.Top,txt);
      end else begin
        Brush.Color := clLtGray;
        FillRect(Rect);
      end;
    end else
      TextRect(Rect,Rect.Left+4,Rect.Top,FLog.Strings[ARow]);
end;

procedure TLogFrame.drwgrdEventsClick(Sender: TObject);
var i: integer;
    s: string;
begin
  i := drwgrdEvents.Row;
  if Cardinal(i)>cardinal(FLog.Count) then
    s := '' else
    s := FLog.Strings[i];
  mmoBottom.Text := s;
end;

procedure TLogFrame.btnSearchNextClick(Sender: TObject);
var s: RawUTF8;
    ndx, i, searchnext: integer;
begin
  s := UpperCase(StringToUTF8(edtSearch.Text));
  if (FLog=nil) or (s='') then
    exit;
  if (FLastSearchSender=Sender) and (FLastSearch=s) then
    searchnext := 1 else begin
    FLastSearch := s;
    FLastSearchSender := Sender;
    searchnext := 0;
  end;
  Screen.Cursor := crHourGlass;
  try
    ndx := drwgrdEvents.Row;
    // search from next item
    for i := ndx+searchnext to FLog.Count-1 do
      if FLog.LineContains(s,i) then begin
        SetListItem(i,s);
        exit;
      end;
    // not found -> search from beginning
    for i := 0 to ndx-1 do
      if FLog.LineContains(s,i) then begin
        SetListItem(i,s);
        exit;
      end;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TLogFrame.SetListItem(Index: integer; const search: RawUTF8);
var i: integer;
    s,ss: string;
begin
  if (Index<0) or (FLog=nil) then
    mmoBottom.Text := '' else begin
    drwgrdEvents.Row := Index;
    if (search='') and drwgrdEvents.Visible then
      drwgrdEvents.SetFocus;
    s := FLog.Strings[Index];
    mmoBottom.Text := s;
    if search<>'' then begin
      ss := UTF8ToString(search);
      i := Pos(ss,SysUtils.UpperCase(s));
      if i>0 then begin
        mmoBottom.SelStart := i-1;
        mmoBottom.SelLength := length(ss);
        if FLastSearchSender<>edtSearch then
          mmoBottom.SetFocus;
      end;
    end;
  end;
end;

procedure TLogFrame.Closing;
begin
  Callback := nil;
  FreeAndNil(fLog);
end;

procedure TLogFrame.chklstEventsDblClick(Sender: TObject);
var i: integer;
    E: TSynLogInfo;
begin
  if FLog.EventLevel=nil then // plain text file does not handle this
    exit;
  i := chklstEvents.ItemIndex;
  if i<0 then
    exit;
  E := TSynLogInfo(chklstEvents.Items.Objects[i]);
  // search from next item
  for i := drwgrdEvents.Row+1 to FLog.Count-1 do
    if FLog.EventLevel[i]=E then begin
      SetListItem(i);
      exit;
    end;
  // search from beginning
  for i := 0 to drwgrdEvents.Row-1 do
    if FLog.EventLevel[i]=E then begin
      SetListItem(i);
      exit;
    end;
end;


end.
