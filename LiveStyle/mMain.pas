unit mMain;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Data.DBXPlatform, Data.DBXJSON,
{$ELSE}
  Windows, Messages, SysUtils, Classes, DBXPlatform, DBXJSON,
{$IFEND}
  IdBaseComponent, IdComponent, IdCustomTCPServer, IdCustomHTTPServer,
  IdHTTPServer, IdContext, IdTCPConnection, IdIOHandler, IdHashSHA, IdCoderMIME,
  mFrame, mWebSocket, mDiff;

type
  TMain = class(TObject)
  private
    { Private éŒ¾ }
    FPort: NativeInt;
    FUpdateLiveStyle: Boolean;
    FWorkDoc: THandle;
    FWorkThread: THandle;
    FAbortThread: Boolean;
    FQueEvent: THandle;
    FMutex: THandle;
    procedure ReadIni;
    procedure WriteIni;
    procedure IdentifyEditor(Sender: TObject; AContext: TIdContext);
    procedure SendPatches(Sender: TObject; Doc: THandle; P: TJSONArray);
    procedure SendUnsavedFiles(Sender: TObject; Payload: TJSONObject;
      AContext: TIdContext);
    function ReadFile(const FilePath: string): string;
    procedure HandlePatchRequest(Sender: TObject; Payload: TJSONObject;
      AContext: TIdContext);
    procedure ApplyPatchedSource(Sender: TObject; Doc: THandle; Content: TJSONObject);
    procedure ReplaceContent(Doc: THandle; Payload: TJSONObject);
  public
    { Public éŒ¾ }
    constructor Create;
    destructor Destroy; override;
    procedure UpdateFiles;
    procedure RenameFile(Doc: THandle);
    procedure ApplyPatchOnView(Doc: THandle; Patch: TJSONArray);
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
  FList: TFrameList;
  FServer: TMain;
  FSocket: TWebSocket;
  FDiff: TDiff;
  FViewFileNames: TStrings;
  FDebug: Boolean;

implementation

uses
{$IF CompilerVersion > 22.9}
  System.IniFiles,
{$ELSE}
  IniFiles,
{$IFEND}
  NotePadEncoding, mCommon, mUtils, mPlugin;

function WaitMessageLoop(Count: LongWord; var Handles: THandle;
  Milliseconds: DWORD): NativeInt;
var
  Quit: Boolean;
  ExitCode: NativeInt;
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
            ExitCode := NativeInt(Msg.wParam);
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
  Result := NativeInt(WaitResult - WAIT_OBJECT_0);
end;

{ TMain }

procedure TMain.ReadIni;
var
  S: string;
begin
  if not GetIniFileName(S) then
    Exit;
  with TMemIniFile.Create(S, TEncoding.UTF8) do
    try
      FPort := ReadInteger('LiveStyle', 'Port', FPort);
      FDebug := ReadBool('LiveStyle', 'Debug', FDebug);
    finally
      Free;
    end;
end;

procedure TMain.WriteIni;
var
  S: string;
begin
  if FIniFailed or (not GetIniFileName(S)) then
    Exit;
  try
    with TMemIniFile.Create(S, TEncoding.UTF8) do
      try
        WriteInteger('LiveStyle', 'Port', FPort);
        WriteBool('LiveStyle', 'Debug', FDebug);
        UpdateFile;
      finally
        Free;
      end;
  except
    FIniFailed := True;
  end;
end;

procedure TMain.IdentifyEditor(Sender: TObject; AContext: TIdContext);
var
  S: string;
  A: TStringArray;
  Data: TJSONObject;
  Files: TJSONArray;
begin
  with TJSONObject.Create do
    try
      AddPair('action', 'id');
      Data := TJSONObject.Create;
      with Data do
      begin
        AddPair('id', 'Mery');
        AddPair('title', 'Mery');
        AddPair('icon', 'data:image/png;base64,' +
          'iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJ' +
          'bWFnZVJlYWR5ccllPAAAAyJpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdp' +
          'bj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6' +
          'eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuMC1jMDYxIDY0LjE0' +
          'MDk0OSwgMjAxMC8xMi8wNy0xMDo1NzowMSAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJo' +
          'dHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlw' +
          'dGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAv' +
          'IiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RS' +
          'ZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpD' +
          'cmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENTNS4xIFdpbmRvd3MiIHhtcE1NOkluc3RhbmNl' +
          'SUQ9InhtcC5paWQ6RjVBQzI1QjUxNTFGMTFFMzgyNTlFQjExMzFFM0U4QzQiIHhtcE1NOkRvY3Vt' +
          'ZW50SUQ9InhtcC5kaWQ6RjVBQzI1QjYxNTFGMTFFMzgyNTlFQjExMzFFM0U4QzQiPiA8eG1wTU06' +
          'RGVyaXZlZEZyb20gc3RSZWY6aW5zdGFuY2VJRD0ieG1wLmlpZDpGNUFDMjVCMzE1MUYxMUUzODI1' +
          'OUVCMTEzMUUzRThDNCIgc3RSZWY6ZG9jdW1lbnRJRD0ieG1wLmRpZDpGNUFDMjVCNDE1MUYxMUUz' +
          'ODI1OUVCMTEzMUUzRThDNCIvPiA8L3JkZjpEZXNjcmlwdGlvbj4gPC9yZGY6UkRGPiA8L3g6eG1w' +
          'bWV0YT4gPD94cGFja2V0IGVuZD0iciI/PivKQJwAAAGdSURBVHjapFOve8IwEH3dh8AtsjISR+Uc' +
          'kXPUbW7gkJ2bo7g5+BM6x1znJoubTF3dIisP1yl211J+fKwzVPQuyd177+4Sb7fb4ZqvJ7+3980Z' +
          'CrVORZcZFRDNQk9cIe+1+08Po8b5AbYnwbS3NTDbyWx6qaD9ps8L2MId1sFAI36ZH5I7S2iZV6/z' +
          'TubGbv8GkGA5SpIPuLJRoPoK2ldQWrPfrLHfs10lTB7HF8zWfSAlC5KDwjBgAPMYq2wd0xFAus3B' +
          'yVoUUMOsmKlyUHcWoW9gbg2iPIL7DIVkJXxnCgQuDMdH5iKHQ4ZAyRkh27LwIgZ8Xt2nT9qPEg7N' +
          'bk7ne9qwrGD/i2Ctg6UUaaZYHe9pzlNM10d0piCcTA/N0kEAW2roQcwgMZyooD0J95gkrkIt15Pb' +
          '5HnexXhMlFn4oyH6OaBZeqVBli3PgBSrKNXme7k0N113nMglVOaiuW4QFaKA6bkMVfBoSwgaOgF4' +
          'Mikoy0lGyAmoTFNHDUILBrX/llBf5TDW+2YZrn/ICBu2K/u5StvH5F37nH8FGABJ380UnNyMxgAA' +
          'AABJRU5ErkJggg==');
        Files := TJSONArray.Create;
        A := GetCSSFiles;
        for S in A do
          Files.Add(EncodeString(S));
        AddPair('files', Files);
      end;
      AddPair('data', Data);
      FSocket.Send(ToString, AContext);
    finally
      Free;
    end;
end;

procedure TMain.SendPatches(Sender: TObject; Doc: THandle; P: TJSONArray);
var
  Data: TJSONObject;
begin
  if (Doc = 0) or (P = nil) then
    Exit;
  with TJSONObject.Create do
    try
      AddPair('action', 'update');
      Data := TJSONObject.Create;
      with Data do
      begin
        AddPair('editorFile', EncodeString(GetFileName(Doc)));
        AddPair('patch', P);
      end;
      AddPair('data', Data);
      FSocket.Send(ToString);
    finally
      Free;
    end;
end;

function TMain.ReadFile(const FilePath: string): string;
var
  Encoding: TFileEncoding;
  E1, E2: Boolean;
begin
  Encoding := feNone;
  Result := LoadFromFile(FilePath, Encoding, True, E1, E2, feUTF8);
end;

procedure TMain.SendUnsavedFiles(Sender: TObject; Payload: TJSONObject;
  AContext: TIdContext);
var
  I: NativeInt;
  Doc: THandle;
  Files: TJSONArray;
  Content, FileName, Pristine: string;
  Data, Obj: TJSONObject;
  AOut: TJSONArray;
begin
  Files := Payload.Get('files').JsonValue as TJSONArray;
  AOut := TJSONArray.Create;
  try
    for I := 0 to Files.Size - 1 do
    begin
      Doc := GetDocForFile(Files.Get(I).Value);
      if Doc = 0 then
        Continue;
      Content := GetContent(Doc);
      if GetModified(Doc) then
      begin
        FileName := GetFileName(Doc);
        if not FileExists2(FileName) then
          Pristine := ''
        else
          Pristine := ReadFile(FileName);
      end;
      if Pristine <> '' then
      begin
        Obj := TJSONObject.Create;
        with Obj do
        begin
          AddPair('file', EncodeString(Files.Get(I).Value));
          AddPair('pristine', EncodeString(Pristine));
          AddPair('content', EncodeString(Content));
        end;
        AOut.AddElement(Obj);
      end;
    end;
    if AOut.Size > 0 then
    begin
      with TJSONObject.Create do
        try
          AddPair('action', 'unsavedFiles');
          Data := TJSONObject.Create;
          with Data do
            AddPair('files', AOut);
          AddPair('data', Data);
          FSocket.Send(ToString, AContext);
        finally
          Free;
        end;
    end
    else
      OutputString('No unsaved changes');
  finally
    if Assigned(AOut) then
      FreeAndNil(AOut);
  end;
end;

procedure TMain.HandlePatchRequest(Sender: TObject; Payload: TJSONObject;
  AContext: TIdContext);
var
  EditorFile: string;
  Doc: THandle;
  Patch: TJSONArray;
begin
  OutputString('Handle CSS patch request');
  EditorFile := Payload.Get('editorFile').JsonValue.Value;
  if EditorFile = '' then
  begin
    OutputString('No editor file in payload, skip patching');
    Exit;
  end;
  Doc := GetDocForFile(EditorFile);
  if Doc = 0 then
  begin
    OutputString(Format('Unable to find view for %s file', [EditorFile]));
    if EditorFile[1] = '<' then
      Exit;
    Editor_LoadFile(GetView(Doc), True, PChar(EditorFile));
  end;
  Patch := Payload.Get('patch').JsonValue as TJSONArray;
  if not Patch.Null then
    ApplyPatchOnView(GetActiveDoc(GetView(Doc)), TJSONArray(Patch.Clone));
end;

procedure TMain.ApplyPatchedSource(Sender: TObject; Doc: THandle;
  Content: TJSONObject);
begin
  if (Doc = 0) or Content.Null then
    Exit;
  ReplaceContent(Doc, Content);
end;

procedure TMain.ReplaceContent(Doc: THandle; Payload: TJSONObject);
var
  View: THandle;
  P1, P2, P3: TPoint;
  Sels: TJSONArray;
begin
  if Payload.Null then
    Exit;
  View := GetView(Doc);
  Editor_Redraw(View, False);
  try
    Editor_GetSelStart(View, POS_LOGICAL, @P1);
    Editor_GetSelEnd(View, POS_LOGICAL, @P2);
    Editor_GetScrollPos(View, @P3);
    Editor_Convert(View, FLAG_CONVERT_SELECT_ALL);
    Editor_Insert(View, PChar(Payload.Get('content').JsonValue.Value));
    Editor_SetCaretPos(View, POS_LOGICAL, @P1);
    Editor_SetCaretPosEx(View, POS_LOGICAL, @P2, True);
    Editor_SetScrollPos(View, @P3);
    if not Payload.Get('selection').JsonValue.Null then
    begin
      Sels := Payload.Get('selection').JsonValue as TJSONArray;
      Editor_SerialToLogical(View, StrToIntDef(Sels.Get(0).Value, 0), @P1);
      Editor_SerialToLogical(View, StrToIntDef(Sels.Get(1).Value, 0), @P2);
      Editor_SetCaretPos(View, POS_LOGICAL, @P1);
      Editor_SetCaretPosEx(View, POS_LOGICAL, @P2, True);
    end;
  finally
    Editor_Redraw(View, True);
  end;
end;

constructor TMain.Create;
begin
  FSocket := TWebSocket.Create;
  with FSocket do
  begin
    OnHandShake := IdentifyEditor;
    OnUpdate := HandlePatchRequest;
    OnRequestUnsavedFiles := SendUnsavedFiles;
  end;
  FDiff := TDiff.Create;
  with FDiff do
  begin
    OnDiffComplete := SendPatches;
    OnPatchComplete := ApplyPatchedSource;
  end;
  FPort := 54000;
  FDebug := False;
  FUpdateLiveStyle := False;
  FWorkDoc := 0;
  FQueEvent := CreateEvent(nil, True, False, nil);
  FMutex := CreateMutex(nil, False, nil);
  ReadIni;
  FSocket.Open(FPort);
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
  WriteIni;
  if Assigned(FDiff) then
    FreeAndNil(FDiff);
  if Assigned(FSocket) then
    FreeAndNil(FSocket);
  inherited;
end;

procedure TMain.UpdateFiles;
var
  S: string;
  A: TStringArray;
  Data: TJSONArray;
begin
  with TJSONObject.Create do
    try
      AddPair('action', 'updateFiles');
      Data := TJSONArray.Create;
      A := GetCSSFiles;
      for S in A do
        Data.Add(EncodeString(S));
      AddPair('data', Data);
      FSocket.Send(ToString);
    finally
      Free;
    end;
end;

procedure TMain.RenameFile(Doc: THandle);
var
  NewName: string;
  Idx: NativeInt;
  Data: TJSONObject;
begin
  NewName := GetFileName(Doc);
  Idx := FViewFileNames.IndexOfName(IntToStr(Doc));
  if (Idx > -1) and (FViewFileNames.ValueFromIndex[Idx] <> NewName) then
  begin
    with TJSONObject.Create do
      try
        AddPair('action', 'renameFile');
        Data := TJSONObject.Create;
        with Data do
        begin
          AddPair('oldname', EncodeString(FViewFileNames.ValueFromIndex[Idx]));
          AddPair('newname', EncodeString(NewName));
        end;
        AddPair('data', Data);
        FSocket.Send(ToString);
      finally
        Free;
      end;
  end;
end;

procedure TMain.ApplyPatchOnView(Doc: THandle; Patch: TJSONArray);
begin
  if not IsCssDoc(Doc) then
  begin
    OutputString(Format('File %s is not CSS, aborting', [GetFileName(Doc)]));
    Exit;
  end;
  FDiff.Patch(Doc, Patch);
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

initialization

FViewFileNames := TStringList.Create;

finalization

if Assigned(FViewFileNames) then
  FreeAndNil(FViewFileNames);

end.
