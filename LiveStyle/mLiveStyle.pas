// -----------------------------------------------------------------------------
// Emmet LiveStyle
//
// Copyright (c) Kuro. All Rights Reserved.
// e-mail: info@haijin-boys.com
// www:    https://www.haijin-boys.com/
// -----------------------------------------------------------------------------

unit mLiveStyle;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils,
{$ELSE}
  Windows, Messages, SysUtils,
{$IFEND}
  mCommon, mMain, mFrame, mPlugin;

resourcestring
  SName = 'Emmet LiveStyle';
  SVersion = '2.3.1';

type
  TLiveStyleFrame = class(TFrame)
  private
    { Private êÈåæ }
    function QueryProperties: Boolean;
    function SetProperties(hwnd: HWND): Boolean;
    function PreTranslateMessage(hwnd: HWND; var Msg: tagMSG): Boolean;
  protected
    { Protected êÈåæ }
  public
    { Public êÈåæ }
    procedure OnIdle(hwnd: HWND);
    procedure OnCommand(hwnd: HWND); override;
    function QueryStatus(hwnd: HWND; pbChecked: PBOOL): BOOL; override;
    procedure OnEvents(hwnd: HWND; nEvent: Cardinal; lParam: LPARAM); override;
    function PluginProc(hwnd: HWND; nMsg: Cardinal; wParam: WPARAM; lParam: LPARAM): LRESULT; override;
  end;

procedure WorkThread(AMain: Pointer);

implementation

uses
  mUtils, mProp;

{ TLiveStyleFrame }

function TLiveStyleFrame.QueryProperties: Boolean;
begin
  Result := True;
end;

function TLiveStyleFrame.SetProperties(hwnd: HWND): Boolean;
var
  LPort: Integer;
begin
  Result := False;
  LPort := FPort;
  if Prop(Handle, FPort, FDebug, FSendUnsavedChanges) then
  begin
    if (FPort <> LPort) and (FMain <> nil) then
    begin
      FreeAndNil(FMain);
      FMain := TMain.Create;
    end;
    Result := True;
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
  if FMain <> nil then
  begin
    with FMain do
    begin
      if UpdateLiveStyle then
      begin
        if WorkHandle = 0 then
        begin
          Id := 0;
          WorkHandle := BeginThread(nil, 0, @WorkThread, @FMain, 0, Id);
          if WorkHandle > 0 then
            SetThreadPriority(WorkHandle, THREAD_PRIORITY_LOWEST);
        end;
      end;
      if UpdateLiveStyle then
        SetEvent(QueEvent);
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
  pbChecked^ := FMain <> nil;
  Result := True;
end;

procedure TLiveStyleFrame.OnEvents(hwnd: HWND; nEvent: Cardinal; lParam: LPARAM);
var
  Doc: THandle;
begin
  if (nEvent and EVENT_FILE_OPENED) <> 0 then
  begin
    if FMain <> nil then
      FMain.RefreshLiveStyleFiles;
  end;
  if (nEvent and EVENT_DOC_CLOSE) <> 0 then
  begin
    if FMain <> nil then
      FMain.RefreshLiveStyleFiles;
  end;
  if (nEvent and EVENT_CHANGED) <> 0 then
  begin
    Doc := GetActiveDoc(hwnd);
    if FMain <> nil then
      with FMain do
        if IsSupportedDoc(Doc, True) and (not IsLocked(Doc)) then
        begin
          WorkDoc := Doc;
          UpdateLiveStyle := True;
        end;
  end;
  if (nEvent and (EVENT_SET_FOCUS or EVENT_MODE_CHANGED or EVENT_DOC_SEL_CHANGED)) <> 0 then
  begin
    if FMain <> nil then
      with FMain do
      begin
        RefreshLiveStyleFiles;
        Doc := GetActiveDoc(hwnd);
        if IsSupportedDoc(Doc, True) then
          SendInitialContent(Doc);
      end;
  end;
  if (nEvent and EVENT_FILE_SAVED) <> 0 then
  begin
    if FMain <> nil then
      FMain.RefreshLiveStyleFiles;
  end;
  if (nEvent and EVENT_IDLE) <> 0 then
    OnIdle(hwnd);
end;

function TLiveStyleFrame.PluginProc(hwnd: HWND; nMsg: Cardinal; wParam: WPARAM; lParam: LPARAM): LRESULT;
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

procedure WorkThread(AMain: Pointer);
var
  Main: TMain;
  Doc: THandle;
  QueEvent: THandle;
  Mutex: THandle;
begin
  Main := TMain(AMain^);
  QueEvent := Main.QueEvent;
  Mutex := Main.Mutex;
  while not Main.AbortThread do
  begin
    if WaitForSingleObject(QueEvent, INFINITE) <> WAIT_OBJECT_0 then
      Break;
    if WaitForSingleObject(Mutex, INFINITE) <> WAIT_OBJECT_0 then
      Break;
    if Main.AbortThread then
    begin
      ReleaseMutex(Mutex);
      Break;
    end;
    Doc := Main.WorkDoc;
    Main.WorkDoc := 0;
    ResetEvent(QueEvent);
    try
      Main.LiveStyleAll(Doc);
    except
      Main.AbortThread := True;
    end;
    ReleaseMutex(Mutex);
  end;
  Main.AbortThread := False;
end;

end.
