// -----------------------------------------------------------------------------
// Emmet LiveStyle
//
// Copyright (c) Kuro. All Rights Reserved.
// e-mail: info@haijin-boys.com
// www:    http://www.haijin-boys.com/
// -----------------------------------------------------------------------------

unit mLiveStyle;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, Data.DBXPlatform,
  Data.DBXJSON,
{$ELSE}
  Windows, Messages, SysUtils, DBXPlatform, DBXJSON,
{$IFEND}
  mCommon, mMain, mFrame, mPlugin;

resourcestring
  SName = 'Emmet LiveStyle';
  SVersion = '1.0.0';

type
  TLiveStyleFrame = class(TFrame)
  private
    { Private éŒ¾ }
    function QueryProperties: Boolean;
    function SetProperties(hwnd: HWND): Boolean;
    function PreTranslateMessage(hwnd: HWND; var Msg: tagMSG): Boolean;
  protected
    { Protected éŒ¾ }
  public
    { Public éŒ¾ }
    procedure OnIdle(hwnd: HWND);
    procedure OnCommand(hwnd: HWND); override;
    function QueryStatus(hwnd: HWND; pbChecked: PBOOL): BOOL; override;
    procedure OnEvents(hwnd: HWND; nEvent: NativeInt; lParam: LPARAM); override;
    function PluginProc(hwnd: HWND; nMsg: NativeInt; wParam: WPARAM; lParam: LPARAM): LRESULT; override;
  end;

procedure WorkThread(AServer: Pointer);

implementation

uses
{$IF CompilerVersion > 22.9}
  System.RegularExpressions,
{$ELSE}
  RegularExpressions,
{$IFEND}
  NotePadClipbrd, mProp, mDiff, mUtils;

{ TLiveStyleFrame }

function TLiveStyleFrame.QueryProperties: Boolean;
begin
  Result := Assigned(FServer);
end;

function TLiveStyleFrame.SetProperties(hwnd: HWND): Boolean;
var
  S: string;
  I: NativeInt;
  Doc: THandle;
  Sources: THandleArray;
  Data: TJSONObject;
  Patch: TJSONArray;
begin
  Result := False;
  if FServer <> nil then
  begin
    if not IsCssDoc(GetActiveDoc(hwnd)) then
    begin
      MessageBox(0, PChar('You should run this action on CSS file'), PChar(SName), MB_OK or MB_ICONEXCLAMATION);
      Exit;
    end;
    SetLength(Sources, 0);
    for Doc in GetAllDocs do
      if TRegEx.IsMatch(GetFileName(Doc), '[\/\\]lspatch-[\w\-]+\.json$') then
      begin
        SetLength(Sources, Length(Sources) + 1);
        Sources[Length(Sources) - 1] := Doc;
      end;
    FPatches.Clear;
    for Doc in Sources do
    begin
      Data := TJSONObject.ParseJSONValue(GetContent(Doc)) as TJSONObject;
      try
        FDiff.ParsePatch(Data, GetFileName(Doc));
      finally
        Data.Free;
      end;
    end;
    S := GetFromClipbrd;
    if S <> '' then
    begin
      Data := TJSONObject.ParseJSONValue(S) as TJSONObject;
      try
        FDiff.ParsePatch(Data, 'Clipboard');
      finally
        Data.Free;
      end;
    end;
    I := -1;
    if Prop(nil, I) then
    begin
      if (I > -1) and (I < FPatches.Count) then
      begin
        Patch := TJSONObject.ParseJSONValue(FPatches[I].Data) as TJSONArray;
        FServer.ApplyPatchOnView(GetActiveDoc(hwnd), Patch);
      end;
      Result := True;
    end;
  end;
end;

function TLiveStyleFrame.PreTranslateMessage(hwnd: HWND; var Msg: tagMSG): Boolean;
begin
  Result := False;
end;

procedure TLiveStyleFrame.OnIdle(hwnd: HWND);
var
  Id: Cardinal;
begin
  if FServer <> nil then
  begin
    with FServer do
    begin
      if UpdateLiveStyle then
      begin
        if WorkHandle = 0 then
        begin
          Id := 0;
          WorkHandle := BeginThread(nil, 0, @WorkThread, @FServer, 0, Id);
          if WorkHandle > 0 then
            SetThreadPriority(WorkHandle, THREAD_PRIORITY_LOWEST);
        end;
      end;
      if UpdateLiveStyle then
      begin
        WorkDoc := GetActiveDoc(hwnd);
        SetEvent(QueEvent);
      end;
      UpdateLiveStyle := False;
    end;
  end;
end;

procedure TLiveStyleFrame.OnCommand(hwnd: HWND);
begin
  //
end;

function TLiveStyleFrame.QueryStatus(hwnd: HWND; pbChecked: PBOOL): BOOL;
begin
  pbChecked^ := FServer <> nil;
  Result := True;
end;

procedure TLiveStyleFrame.OnEvents(hwnd: HWND; nEvent: NativeInt; lParam: LPARAM);
var
  Doc: THandle;
  Idx: NativeInt;
begin
  if (nEvent and EVENT_FILE_OPENED) <> 0 then
  begin
    Doc := GetActiveDoc(hwnd);
    FViewFileNames.Values[IntToStr(Doc)] := GetFileName(Doc);
    if IsCssDoc(Doc) then
      if FServer <> nil then
        FServer.UpdateFiles;
  end;
  if (nEvent and EVENT_DOC_CLOSE) <> 0 then
  begin
    Idx := FViewFileNames.IndexOfName(IntToStr(lParam));
    if Idx > -1 then
      FViewFileNames.Delete(Idx);
    if FServer <> nil then
      FServer.UpdateFiles;
  end;
  if (nEvent and EVENT_CHANGED) <> 0 then
  begin
    Doc := GetActiveDoc(hwnd);
    if GetModified(Doc) then
      if FServer <> nil then
        with FServer do
        begin
          OutputString('Run diff');
          UpdateLiveStyle := True;
        end;
  end;
  if (nEvent and EVENT_MODE_CHANGED) <> 0 then
  begin
    Doc := GetActiveDoc(hwnd);
    FViewFileNames.Values[IntToStr(Doc)] := GetFileName(Doc);
    if IsCssDoc(Doc) then
    begin
      if FServer <> nil then
        with FServer do
        begin
          OutputString('Prepare diff');
          UpdateFiles;
          FDiff.PrepareDiff(Doc);
        end;
    end;
  end;
  if (nEvent and EVENT_DOC_SEL_CHANGED) <> 0 then
  begin
    Doc := GetActiveDoc(hwnd);
    FViewFileNames.Values[IntToStr(Doc)] := GetFileName(Doc);
    if IsCssDoc(Doc) then
    begin
      if FServer <> nil then
        with FServer do
        begin
          OutputString('Prepare diff');
          UpdateFiles;
          FDiff.PrepareDiff(Doc);
        end;
    end;
  end;
  if (nEvent and EVENT_FILE_SAVED) <> 0 then
  begin
    Doc := GetActiveDoc(hwnd);
    if FServer <> nil then
      FServer.RenameFile(Doc);
    FViewFileNames.Values[IntToStr(Doc)] := GetFileName(Doc);
  end;
  if (nEvent and EVENT_IDLE) <> 0 then
    OnIdle(hwnd);
end;

function TLiveStyleFrame.PluginProc(hwnd: HWND; nMsg: NativeInt; wParam: WPARAM; lParam: LPARAM): LRESULT;
begin
  Result := 0;
  case nMsg of
    MP_QUERY_PROPERTIES:
      Result := LRESULT(QueryProperties);
    MP_SET_PROPERTIES:
      Result := LRESULT(SetProperties(hwnd));
    MP_PRE_TRANSLATE_MSG:
      Result := LRESULT(PreTranslateMessage(hwnd, PMsg(lParam)^));
  end;
end;

procedure WorkThread(AServer: Pointer);
var
  Server: TMain;
  Doc: THandle;
  QueEvent: THandle;
  Mutex: THandle;
begin
  Server := TMain(AServer^);
  QueEvent := Server.QueEvent;
  Mutex := Server.Mutex;
  while not Server.AbortThread do
  begin
    if WaitForSingleObject(QueEvent, INFINITE) <> WAIT_OBJECT_0 then
      Break;
    if WaitForSingleObject(Mutex, INFINITE) <> WAIT_OBJECT_0 then
      Break;
    if Server.AbortThread then
    begin
      ReleaseMutex(Mutex);
      Break;
    end;
    Doc := Server.WorkDoc;
    Server.WorkDoc := 0;
    ResetEvent(QueEvent);
    try
      Server.LiveStyleAll(Doc);
    except
      Server.AbortThread := True;
    end;
    ReleaseMutex(Mutex);
  end;
  Server.AbortThread := False;
end;

end.
