unit mMain;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.ExtCtrls, Data.DBXPlatform, Data.DBXJSON,
{$ELSE}
  Windows, Messages, SysUtils, Classes, ExtCtrls, DBXPlatform, DBXJSON,
{$IFEND}
  D6DLLSynchronizer, mFrame, mServer, mClient, mDiff;

const
  MeryVer = 2;
  MaxConnAttempts = 10;

type
  TMain = class(TObject)
  private
    { Private éŒ¾ }
    FConnAttempts: Integer;
    FRestart: TTimer;
    FDiff: TDiff;
    FUpdateLiveStyle: Boolean;
    FWorkDoc: THandle;
    FWorkThread: THandle;
    FAbortThread: Boolean;
    FQueEvent: THandle;
    FMutex: THandle;
    procedure StartApp;
    procedure RestartApp;
    procedure StopApp;
    procedure Identify;
    procedure SendClientId;
    procedure PatcherConnect;
    procedure ApplyIncomingUpdates(const Data: string);
    procedure HandlePatchRequest(const Data: string);
    procedure RespondWithDependecyList(const Data: string);
    procedure HandleUnsavedChangesRequest(const Data: string);
    procedure SendUnsavedChanges(Doc: THandle);
    procedure ReplaceContent(Doc: THandle; const Data: string);
    // procedure PushUnsavedChanges(Doc: THandle);
    procedure RestartTimer(Sender: TObject);
    procedure ClientConnect(Sender: TObject);
    procedure ClientDisconnect(Sender: TObject);
    procedure ClientMessage(Sender: TObject; const Name, Data: string);
  public
    { Public éŒ¾ }
    constructor Create;
    destructor Destroy; override;
    function IsSupportedDoc(Doc: THandle; AStrict: Boolean = False): Boolean;
    procedure RefreshLiveStyleFiles;
    procedure SendInitialContent(Doc: THandle);
    procedure ResetThread;
    procedure LiveStyleAll(Doc: THandle);
    property UpdateLiveStyle: Boolean read FUpdateLiveStyle write FUpdateLiveStyle;
    property WorkHandle: THandle read FWorkThread write FWorkThread;
    property WorkDoc: THandle read FWorkDoc write FWorkDoc;
    property AbortThread: Boolean read FAbortThread write FAbortThread;
    property QueEvent: THandle read FQueEvent write FQueEvent;
    property Mutex: THandle read FMutex write FMutex;
  end;

var
  FMain: TMain;
  FList: TFrameList;
  FPort: Integer;
  FDebug: Boolean;
  FSendUnsavedChanges: Boolean;
  FServer: TServer;
  FClient: TClient;

implementation

uses
{$IF CompilerVersion > 22.9}
  System.IniFiles,
{$ELSE}
  IniFiles,
{$IFEND}
  mCommon, mUtils, mFileReader, mPlugin, mJSONHelper;

function WaitMessageLoop(Count: LongWord; var Handles: THandle;
  Milliseconds: DWORD): Integer;
var
  Quit: Boolean;
  ExitCode: Integer;
  WaitResult: DWORD;
  Msg: TMsg;
begin
  Quit := False;
  ExitCode := 0;
  repeat
    while PeekMessage(Msg, 0, 0, 0, PM_REMOVE) do
    begin
      case Msg.message of
        WM_QUIT:
          begin
            Quit := True;
            ExitCode := Integer(Msg.wParam);
            Break;
          end;
        WM_MOUSEMOVE:
          ;
        WM_LBUTTONDOWN:
          ;
      else
        DispatchMessage(Msg);
      end;
    end;
    WaitResult := MsgWaitForMultipleObjects(Count, Handles, False, Milliseconds, QS_ALLINPUT);
  until WaitResult <> WAIT_OBJECT_0 + 1;
  if Quit then
    PostQuitMessage(ExitCode);
  Result := Integer(WaitResult - WAIT_OBJECT_0);
end;

{ TMain }

constructor TMain.Create;
begin
  FUpdateLiveStyle := False;
  FWorkDoc := 0;
  FQueEvent := CreateEvent(nil, True, False, nil);
  FMutex := CreateMutex(nil, False, nil);
  FConnAttempts := 0;
  FRestart := TTimer.Create(nil);
  with FRestart do
  begin
    Enabled := False;
    Interval := 3000;
  end;
  FDiff := TDiff.Create;
  FServer := TServer.Create;
  FClient := TClient.Create;
  with FClient do
  begin
    OnConnect := ClientConnect;
    OnDisconnect := ClientDisconnect;
    OnMessage := ClientMessage;
  end;
  StartApp;
end;

destructor TMain.Destroy;
begin
  ResetThread;
  if FQueEvent > 0 then
  begin
    CloseHandle(FQueEvent);
    FQueEvent := 0;
  end;
  if FMutex > 0 then
  begin
    CloseHandle(FMutex);
    FMutex := 0;
  end;
  StopApp;
  if Assigned(FClient) then
    FreeAndNil(FClient);
  if Assigned(FServer) then
    FreeAndNil(FServer);
  if Assigned(FDiff) then
    FreeAndNil(FDiff);
  if Assigned(FRestart) then
    FreeAndNil(FRestart);
  inherited;
end;

function TMain.IsSupportedDoc(Doc: THandle; AStrict: Boolean): Boolean;
var
  S: string;
begin
  Result := mUtils.IsSupportedDoc(Doc, AStrict, S);
end;

procedure TMain.RefreshLiveStyleFiles;
var
  S: string;
  A: TStringArray;
  P: TJSONArray;
begin
  A := GetSupportedFiles;
  P := TJSONArray.Create;
  for S in A do
    P.Add(S);
  with TJSONObject.Create do
    try
      AddPair('id', Format('me%d', [MeryVer]));
      AddPair('files', P);
      S := ToJSON;
    finally
      Free;
    end;
  FClient.Send('editor-files', S);
end;

procedure TMain.SendInitialContent(Doc: THandle);
var
  S: string;
begin
  with TJSONObject.ParseJSONValue(GetPayload(Doc)) as TJSONObject do
    try
      S := ToJSON;
    finally
      Free;
    end;
  FClient.Send('initial-content', S);
end;

procedure TMain.ResetThread;
begin
  if FWorkThread > 0 then
  begin
    FAbortThread := True;
    SetEvent(FQueEvent);
    SetThreadPriority(FWorkThread, THREAD_PRIORITY_ABOVE_NORMAL);
    WaitMessageLoop(1, FWorkThread, INFINITE);
    CloseHandle(FWorkThread);
    FWorkThread := 0;
    FAbortThread := False;
  end;
end;

procedure TMain.LiveStyleAll(Doc: THandle);
begin
  FDiff.Diff(Doc);
end;

procedure TMain.StartApp;
begin
  if FClient.Connected then
    Exit;
  Inc(FConnAttempts);
  if FConnAttempts >= MaxConnAttempts then
  begin
    OutputString(Format('Unable to create to LiveStyle server. Make sure your firewall/proxy does not block %d port', [FPort]));
    Exit;
  end;
  OutputString('Start app');
  FClient.Connect('127.0.0.1', FPort);
  if not FClient.Connected then
  begin
    OutputString('Client connection error');
    OutputString(Format('Create own server on port %d', [FPort]));
    FServer.Start(FPort);
    FClient.Connect('127.0.0.1', FPort);
  end;
  FRestart.OnTimer := RestartTimer;
end;

procedure TMain.RestartApp;
begin
  OutputString('Requested app restart');
  FRestart.Enabled := True;
end;

procedure TMain.StopApp;
begin
  FServer.Stop;
  with FRestart do
  begin
    Enabled := False;
    OnTimer := nil;
  end;
end;

procedure TMain.Identify;
var
  S: string;
begin
  with TJSONObject.Create do
    try
      AddPair('id', Format('me%d', [MeryVer]));
      AddPair('title', Format('Mery %d', [MeryVer]));
      S := ToJSON;
    finally
      Free;
    end;
  FClient.Send('editor-connect', S);
  RefreshLiveStyleFiles;
end;

procedure TMain.SendClientId;
var
  S: string;
begin
  with TJSONObject.Create do
    try
      AddPair('id', 'mery');
      S := ToJSON;
    finally
      Free;
    end;
  FClient.Send('client-id', S);
end;

procedure TMain.PatcherConnect;
var
  S: string;
  Doc: THandle;
begin
  Doc := GetActiveDoc(GetActiveWindow);
  if (Doc > 0) and IsSupportedDoc(Doc, True) then
  begin
    with TJSONObject.ParseJSONValue(GetPayload(Doc)) as TJSONObject do
      try
        S := ToJSON;
      finally
        Free;
      end;
    FClient.Send('initial-content', S);
  end;
end;

procedure TMain.ApplyIncomingUpdates(const Data: string);
var
  S: string;
  P: TJSONObject;
  Doc: THandle;
begin
  S := '';
  P := TJSONObject.ParseJSONValue(Data) as TJSONObject;
  if P <> nil then
    try
      if P.Get('uri') <> nil then
        S := P.Get('uri').JsonValue.Value;
    finally
      P.Free;
    end;
  Doc := GetDocForUri(S);
  if Doc > 0 then
  begin
    S := '';
    P := TJSONObject.ParseJSONValue(Data) as TJSONObject;
    if P <> nil then
      try
        if P.Get('patches') <> nil then
          with TJSONObject.Create do
            try
              AddPair(P.Get('patches').Clone as TJSONPair);
              S := ToJSON;
            finally
              Free;
            end;
      finally
        P.Free;
      end;
    with TJSONObject.ParseJSONValue(GetPayload(Doc, S)) do
      try
        S := ToJSON;
      finally
        Free;
      end;
    FClient.Send('apply-patch', S);
  end;
end;

procedure TMain.HandlePatchRequest(const Data: string);
var
  S: string;
  P: TJSONObject;
  Doc: THandle;
begin
  S := '';
  P := TJSONObject.ParseJSONValue(Data) as TJSONObject;
  if P <> nil then
    try
      if P.Get('uri') <> nil then
        S := P.Get('uri').JsonValue.Value;
    finally
      P.Free;
    end;
  Doc := GetDocForUri(S);
  OutputString('patch');
  if Doc > 0 then
    ReplaceContent(Doc, Data);
end;

procedure TMain.RespondWithDependecyList(const Data: string);
var
  S, T: string;
  I: Integer;
  A: TStringArray;
  P: TJSONObject;
  Q: TJSONArray;
  R: TJSONObject;
begin
  if not FSendUnsavedChanges then
    Exit;
  T := '';
  SetLength(A, 0);
  P := TJSONObject.ParseJSONValue(Data) as TJSONObject;
  if P <> nil then
    try
      if P.Get('files') <> nil then
      begin
        Q := P.Get('files').JsonValue as TJSONArray;
        for I := 0 to Q.Size - 1 do
        begin
          R := Q.Get(I) as TJSONObject;
          if R.Get('uri') <> nil then
          begin
            S := GetFileContents(R.Get('uri').JsonValue.Value);
            if S <> '' then
            begin
              SetLength(A, Length(A) + 1);
              A[Length(A) - 1] := S;
            end;
          end;
        end;
      end;
      if P.Get('token') <> nil then
        T := P.Get('token').JsonValue.Value;
    finally
      P.Free;
    end;
  Q := TJSONArray.Create;
  for S in A do
    Q.AddElement(TJSONObject.ParseJSONValue(S));
  with TJSONObject.Create do
    try
      AddPair('token', T);
      AddPair('files', Q);
      S := ToJSON;
    finally
      Free;
    end;
  FClient.Send('files', S);
end;

procedure TMain.HandleUnsavedChangesRequest(const Data: string);
var
  S: string;
  I: Integer;
  A: TStringArray;
  P: TJSONObject;
  Q: TJSONArray;
  Doc: THandle;
begin
  if not FSendUnsavedChanges then
    Exit;
  SetLength(A, 0);
  P := TJSONObject.ParseJSONValue(Data) as TJSONObject;
  if P <> nil then
    try
      if P.Get('files') <> nil then
      begin
        Q := P.Get('files').JsonValue as TJSONArray;
        SetLength(A, Q.Size);
        for I := 0 to Q.Size - 1 do
          A[I] := Q.Get(I).Value;
      end;
    finally
      P.Free;
    end;
  for S in A do
  begin
    Doc := GetDocForUri(S);
    if (Doc > 0) and (IsModified(Doc)) then
      SendUnsavedChanges(Doc);
  end;
end;

procedure TMain.SendUnsavedChanges(Doc: THandle);
var
  S, T: string;
  N: Boolean;
begin
  S := GetFileNameSub(Doc);
  T := '';
  N := True;
  if S = '' then
    N := False
  else if FileExists2(S) then
  begin
    N := False;
    T := ReadFile(S);
  end;
  if not N then
  begin
    S := '';
    with TJSONObject.Create do
      try
        AddPair(TJSONPair.Create('previous', T));
        S := ToJSON;
      finally
        Free;
      end;
    with TJSONObject.ParseJSONValue(GetPayload(Doc, S)) do
      try
        S := ToJSON;
      finally
        Free;
      end;
    FClient.Send('calculate-diff', S);
  end;
end;

procedure TMain.ReplaceContent(Doc: THandle; const Data: string);
var
  H: THandle;
  I: Integer;
  S, T: string;
  U: array of array [0 .. 2] of string;
  P: TJSONObject;
  Q, R: TJSONArray;
  P1, P2, P3: TPoint;
begin
  if Data = '' then
    Exit;
  Lock(Doc);
  try
    H := GetHandle(Doc);
    S := '';
    T := '';
    SetLength(U, 0);
    P := TJSONObject.ParseJSONValue(Data) as TJSONObject;
    if P <> nil then
      try
        if P.Get('ranges') <> nil then
        begin
          Q := P.Get('ranges').JsonValue as TJSONArray;
          SetLength(U, Q.Size);
          for I := 0 to Q.Size - 1 do
          begin
            R := Q.Get(I) as TJSONArray;
            U[I][0] := R.Get(0).Value;
            U[I][1] := R.Get(1).Value;
            U[I][2] := R.Get(2).Value;
          end;
        end;
        if P.Get('hash') <> nil then
          S := P.Get('hash').JsonValue.Value;
        if P.Get('content') <> nil then
          T := P.Get('content').JsonValue.Value;
      finally
        P.Free;
      end;
    Editor_Info(H, MI_SET_ACTIVE_DOC, Doc);
    if (Length(U) > 0) and (StrToInt64Def(S, 0) = GetDocHash(Doc)) then
    begin
      for I := 0 to Length(U) - 1 do
      begin
        Editor_SerialToLogical(H, StrToInt64Def(U[I][0], 0), @P1);
        Editor_SerialToLogical(H, StrToInt64Def(U[I][1], 0), @P2);
        Editor_SetCaretPos(H, POS_LOGICAL, @P1);
        Editor_SetCaretPosEx(H, POS_LOGICAL, @P2, True);
        Editor_Insert(H, PChar(U[I][2]));
      end;
      Editor_SerialToLogical(H, StrToInt64Def(U[Length(U) - 1][0], 0), @P1);
      Editor_SerialToLogical(H, StrToInt64Def(U[Length(U) - 1][0], 0) + Length(U[Length(U) - 1][2]), @P2);
      Editor_SetCaretPos(H, POS_LOGICAL, @P1);
      Editor_SetCaretPosEx(H, POS_LOGICAL, @P2, True);
    end
    else if T <> '' then
    begin
      Editor_Redraw(H, False);
      try
        Editor_GetSelStart(H, POS_LOGICAL, @P1);
        Editor_GetSelEnd(H, POS_LOGICAL, @P2);
        Editor_GetScrollPos(H, @P3);
        Editor_Convert(H, FLAG_CONVERT_SELECT_ALL);
        Editor_Insert(H, PChar(T));
        Editor_SetCaretPos(H, POS_LOGICAL, @P1);
        Editor_SetCaretPosEx(H, POS_LOGICAL, @P2, True);
        Editor_SetScrollPos(H, @P3);
      finally
        Editor_Redraw(H, True);
      end;
    end;
    if IsSupportedDoc(Doc, True) then
    begin
      with TJSONObject.ParseJSONValue(GetPayload(Doc)) as TJSONObject do
        try
          S := ToJSON;
        finally
          Free;
        end;
      FClient.Send('initial-content', S);
    end;
  finally
    Unlock(Doc);
  end;
end;

(*
 procedure TMain.PushUnsavedChanges(Doc: THandle);
 begin
 if IsSupportedDoc(Doc, True) then
 SendUnsavedChanges(Doc)
 else
 OutputString('Current document is not a valid stylesheet');
 end;
*)

procedure TMain.RestartTimer(Sender: TObject);
begin
  FRestart.Enabled := False;
  StartApp;
end;

procedure TMain.ClientConnect(Sender: TObject);
begin
  OutputString('Client connected');
  FConnAttempts := 0;
  Identify;
  SendClientId;
end;

procedure TMain.ClientDisconnect(Sender: TObject);
begin
  OutputString('Client dropped connection');
  RestartApp;
end;

procedure TMain.ClientMessage(Sender: TObject; const Name, Data: string);
begin
  if Name = 'client-connect' then
    Identify
  else if Name = 'identify-client' then
    SendClientId
  else if Name = 'patcher-connect' then
    PatcherConnect
  else if Name = 'incoming-updates' then
    ApplyIncomingUpdates(Data)
  else if Name = 'patch' then
    HandlePatchRequest(Data)
  else if Name = 'request-files' then
    RespondWithDependecyList(Data)
  else if Name = 'request-unsaved-changes' then
    HandleUnsavedChangesRequest(Data)
  else if Name = 'diff' then
    FDiff.HandleDiffResponse(Data)
  else if Name = 'error' then
    FDiff.HandleErrorResponse(Data);
end;

initialization

finalization

if Assigned(FClient) then
  FreeAndNil(FClient);
if Assigned(FServer) then
  FreeAndNil(FServer);

end.
