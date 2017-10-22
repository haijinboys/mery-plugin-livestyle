// -----------------------------------------------------------------------------
// Emmet LiveStyle
//
// Copyright (c) Kuro. All Rights Reserved.
// e-mail: info@haijin-boys.com
// www:    https://www.haijin-boys.com/
// -----------------------------------------------------------------------------

library LiveStyle;

{$RTTI EXPLICIT METHODS([]) FIELDS([]) PROPERTIES([])}
{$WEAKLINKRTTI ON}

{$R 'mPlugin.res' 'mPlugin.rc'}


uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IniFiles,
  Vcl.Forms,
  mCommon in 'mCommon.pas',
  mMain in 'mMain.pas',
  mClient in 'mClient.pas',
  mServer in 'mServer.pas',
  mDiff in 'mDiff.pas',
  mUtils in 'mUtils.pas',
  mFileReader in 'mFileReader.pas',
  mJSONHelper in 'mJSONHelper.pas',
  mProp in 'mProp.pas' {PropForm},
  mFrame in 'mFrame.pas',
  mLiveStyle in 'mLiveStyle.pas',
  mPlugin in 'mPlugin.pas',
  mPerMonitorDpi in 'mPerMonitorDpi.pas';

const
  IDS_MENU_TEXT = 1;
  IDS_STATUS_MESSAGE = 2;
  IDI_ICON = 101;

var
  FOpenStartup: Boolean;

{$IFDEF DEBUG}
{$R *.res}
{$ENDIF}


procedure Open;
begin
  if FMain = nil then
    try
      FMain := TMain.Create;
    except
      FreeAndNil(FMain);
    end;
end;

procedure Close;
begin
  if FMain <> nil then
    FreeAndNil(FMain);
end;

procedure OnCommand(hwnd: HWND); stdcall;
begin
  if FMain = nil then
    Open
  else
    Close;
  FOpenStartup := FMain <> nil;
end;

function QueryStatus(hwnd: HWND; pbChecked: PBOOL): BOOL; stdcall;
var
  LFrame: TFrame;
begin
  Result := False;
  LFrame := FList.Find(hwnd);
  if LFrame <> nil then
    Result := LFrame.QueryStatus(hwnd, pbChecked);
end;

function GetMenuTextID: Cardinal; stdcall;
begin
  Result := IDS_MENU_TEXT;
end;

function GetStatusMessageID: Cardinal; stdcall;
begin
  Result := IDS_STATUS_MESSAGE;
end;

function GetIconID: Cardinal; stdcall;
begin
  Result := IDI_ICON;
end;

procedure OnEvents(hwnd: HWND; nEvent: Cardinal; lParam: LPARAM); stdcall;
var
  S: string;
  I: Integer;
  LFrame: TFrame;
begin
  if (nEvent and EVENT_CREATE) <> 0 then
  begin
    Application.Handle := HiWord(lParam);
    FList := TFrameList.Create;
    if not GetIniFileName(S) then
      Exit;
    FPort := 54000;
    FDebug := False;
    FSendUnsavedChanges := True;
    with TMemIniFile.Create(S, TEncoding.UTF8) do
      try
        FOpenStartup := ReadBool('LiveStyle', 'OpenStartup', False);
        FPort := ReadInteger('LiveStyle', 'Port', FPort);
        FDebug := ReadBool('LiveStyle', 'Debug', FDebug);
        FSendUnsavedChanges := ReadBool('LiveStyle', 'SendUnsavedChanges', FSendUnsavedChanges);
      finally
        Free;
      end;
  end
  else
  begin
    if Assigned(FList) then
    begin
      if (nEvent and EVENT_CREATE_FRAME) <> 0 then
      begin
        LFrame := TLiveStyleFrame.Create;
        with LFrame do
        begin
          Handle := hwnd;
          OnEvents(hwnd, nEvent, lParam);
        end;
        FList.Add(LFrame);
        if FOpenStartup then
          if FMain = nil then
            Open;
      end
      else if (nEvent and EVENT_CLOSE_FRAME) <> 0 then
      begin
        LFrame := FList.Find(hwnd);
        if LFrame <> nil then
          with LFrame do
          begin
            OnEvents(hwnd, nEvent, lParam);
            FList.Remove(LFrame);
            Free;
          end;
      end
      else if (nEvent and EVENT_CLOSE) <> 0 then
      begin
        FOpenStartup := FMain <> nil;
        if FIniFailed or (not GetIniFileName(S)) then
          Exit;
        try
          with TMemIniFile.Create(S, TEncoding.UTF8) do
            try
              WriteBool('LiveStyle', 'OpenStartup', FOpenStartup);
              WriteInteger('LiveStyle', 'Port', FPort);
              WriteBool('LiveStyle', 'Debug', FDebug);
              WriteBool('LiveStyle', 'SendUnsavedChanges', FSendUnsavedChanges);
              UpdateFile;
            finally
              Free;
            end;
        except
          FIniFailed := True;
        end;
        Close;
        for I := FList.Count - 1 downto 0 do
          FList[I].Free;
        FList.Free;
      end
      else
      begin
        LFrame := FList.Find(hwnd);
        if LFrame <> nil then
          LFrame.OnEvents(hwnd, nEvent, lParam);
      end;
    end;
  end;
end;

function PluginProc(hwnd: HWND; nMsg: Cardinal; wParam: WPARAM; lParam: LPARAM): LRESULT; stdcall;
var
  LFrame: TFrame;
begin
  Result := 0;
  case nMsg of
    MP_GET_NAME:
      begin
        Result := Length(SName);
        if lParam <> 0 then
          lstrcpynW(PChar(lParam), PChar(SName), wParam);
      end;
    MP_GET_VERSION:
      begin
        Result := Length(SVersion);
        if lParam <> 0 then
          lstrcpynW(PChar(lParam), PChar(SVersion), wParam);
      end;
  else
    begin
      LFrame := FList.Find(hwnd);
      if LFrame = nil then
      begin
        hwnd := GetParent(hwnd);
        LFrame := FList.Find(hwnd);
      end;
      if LFrame <> nil then
        Result := LFrame.PluginProc(hwnd, nMsg, wParam, lParam);
    end;
  end;
end;

exports
  OnCommand,
  QueryStatus,
  GetMenuTextID,
  GetStatusMessageID,
  GetIconID,
  OnEvents,
  PluginProc;

begin
{$IFDEF DEBUG}
  ReportMemoryLeaksOnShutdown := True;
{$ENDIF}

end.
