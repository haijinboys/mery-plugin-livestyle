unit mDiff;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Data.DBXPlatform, Data.DBXJSON,
{$ELSE}
  Windows, Messages, SysUtils, Classes, DBXPlatform, DBXJSON,
{$IFEND}
  IdBaseComponent, IdComponent, IdCustomTCPServer, IdCustomHTTPServer,
  IdHTTPServer, IdContext, IdTCPConnection, IdIOHandler, IdHashSHA, IdCoderMIME;

const
  LockTimeout = 15 * 1000;

type
  TPatchItem = class(TCollectionItem)
  private
    { Private éŒ¾ }
    FFileName: string;
    FSelectors: string;
    FName: string;
    FData: string;
  protected
    { Protected éŒ¾ }
    function GetDisplayName: string; override;
  public
    { Public éŒ¾ }
    constructor Create(Collection: TCollection); override;
    destructor Destroy; override;
    procedure Assign(Source: TPersistent); override;
  published
    { Published éŒ¾ }
    property FileName: string read FFileName write FFileName;
    property Selectors: string read FSelectors write FSelectors;
    property Name: string read FName write FName;
    property Data: string read FData write FData;
  end;

  TPatchItems = class;

  TPatchItemsEnumerator = class
  private
    { Private éŒ¾ }
    FIndex: NativeInt;
    FCollection: TPatchItems;
  public
    { Public éŒ¾ }
    constructor Create(ACollection: TPatchItems);
    function GetCurrent: TPatchItem;
    function MoveNext: Boolean;
    property Current: TPatchItem read GetCurrent;
  end;

  TPatchItems = class(TCollection)
  private
    { Private éŒ¾ }
    function GetItem(Index: NativeInt): TPatchItem;
    procedure SetItem(Index: NativeInt; Value: TPatchItem);
  public
    { Public éŒ¾ }
    constructor Create;
    function Add: TPatchItem;
    function GetEnumerator: TPatchItemsEnumerator;
    property Items[Index: NativeInt]: TPatchItem read GetItem write SetItem; default;
  end;

  TState = class
  private
    { Private éŒ¾ }
    FHandle: THandle;
    FRunning: Boolean;
    FStartTime: NativeUInt;
  public
    { Public éŒ¾ }
    constructor Create; overload;
    constructor Create(H: THandle); overload;
    destructor Destroy; override;
    property Handle: THandle read FHandle write FHandle;
    property Running: Boolean read FRunning write FRunning;
    property StartTime: NativeUInt read FStartTime write FStartTime;
  end;

  TStateList = class(TList)
  private
    { Private éŒ¾ }
    function Get(Index: Integer): TState; inline;
  public
    { Public éŒ¾ }
    destructor Destroy; override;
    procedure Clear; override;
    procedure Delete(Index: Integer);
    function Find(H: THandle): TState;
    function IndexOf(H: THandle): NativeInt;
    property Items[Index: Integer]: TState read Get; default;
  end;

  TDiffState = class(TState)
  private
    { Private éŒ¾ }
    FRequired: Boolean;
    FContent: string;
  public
    { Public éŒ¾ }
    constructor Create; overload;
    constructor Create(H: THandle); overload;
    destructor Destroy; override;
    property Required: Boolean read FRequired write FRequired;
    property Content: string read FContent write FContent;
  end;

  TPatchState = class(TState)
  private
    { Private éŒ¾ }
    FPatches: TJSONArray;
  public
    { Public éŒ¾ }
    constructor Create; overload;
    constructor Create(H: THandle); overload;
    destructor Destroy; override;
    property Patches: TJSONArray read FPatches write FPatches;
  end;

  TDiffCompleteEvent = procedure(Sender: TObject; Doc: THandle; P: TJSONArray) of object;
  TPatchCompleteEvent = procedure(Sender: TObject; Doc: THandle; Content: TJSONObject) of object;

  TDiff = class(TObject)
  private
    { Private éŒ¾ }
    FDiffStates: TStateList;
    FPatchStates: TStateList;
    FOnDiffComplete: TDiffCompleteEvent;
    FOnPatchComplete: TPatchCompleteEvent;
    function GetSyntax(Doc: THandle): string;
    procedure LockState(State: TState);
    procedure UnlockState(State: TState; const Str: string = '');
    function IsLocked(State: TState): Boolean;
    procedure DiffEditorSources(Sender: TObject; Data: TJSONObject);
    procedure DiffComplete(Doc: THandle; Patches: TJSONArray; const Content: string);
    procedure PatchEditorSources(Sender: TObject; Data: TJSONObject);
    procedure PatchComplete(ID: THandle; Content: TJSONObject);
    function IsValidPatch(Content: TJSONObject): Boolean;
    function StringifySelectors(Patch: TJSONArray): string;
  public
    { Public éŒ¾ }
    constructor Create;
    destructor Destroy; override;
    procedure PrepareDiff(Doc: THandle);
    procedure Diff(Doc: THandle);
    procedure StartDiff(Doc: THandle);
    procedure Patch(Doc: THandle; Patches: TJSONArray);
    procedure StartPatch(Doc: THandle; Patch: TJSONArray);
    procedure ParsePatch(Data: TJSONObject; const AName: string);
    property OnDiffComplete: TDiffCompleteEvent read FOnDiffComplete write FOnDiffComplete;
    property OnPatchComplete: TPatchCompleteEvent read FOnPatchComplete write FOnPatchComplete;
  end;

var
  FPatches: TPatchItems;

implementation

uses
  mMain, mUtils, mPlugin;

{ TPatchItem }

constructor TPatchItem.Create(Collection: TCollection);
begin
  inherited;
  FFileName := '';
  FSelectors := '';
  FName := '';
  FData := '';
end;

destructor TPatchItem.Destroy;
begin
  //
  inherited;
end;

procedure TPatchItem.Assign(Source: TPersistent);
begin
  if Source is TPatchItem then
    with TPatchItem(Source) do
    begin
      Self.FFileName := FileName;
      Self.FSelectors := Selectors;
      Self.FName := Name;
      Self.FData := Data;
    end
  else
    inherited;
end;

function TPatchItem.GetDisplayName: string;
begin
  Result := FFileName;
end;

{ TPatchItemsEnumerator }

constructor TPatchItemsEnumerator.Create(ACollection: TPatchItems);
begin
  inherited Create;
  FIndex := -1;
  FCollection := ACollection;
end;

function TPatchItemsEnumerator.GetCurrent: TPatchItem;
begin
  Result := FCollection[FIndex];
end;

function TPatchItemsEnumerator.MoveNext: Boolean;
begin
  Result := FIndex < FCollection.Count - 1;
  if Result then
    Inc(FIndex);
end;

{ TPatchItems }

function TPatchItems.Add: TPatchItem;
begin
  Result := TPatchItem( inherited Add);
end;

constructor TPatchItems.Create;
begin
  inherited Create(TPatchItem);
end;

function TPatchItems.GetEnumerator: TPatchItemsEnumerator;
begin
  Result := TPatchItemsEnumerator.Create(Self);
end;

function TPatchItems.GetItem(Index: NativeInt): TPatchItem;
begin
  Result := TPatchItem( inherited GetItem(Index));
end;

procedure TPatchItems.SetItem(Index: NativeInt; Value: TPatchItem);
begin
  inherited SetItem(Index, Value);
end;

{ TState }

constructor TState.Create;
begin
  Create(0);
end;

constructor TState.Create(H: THandle);
begin
  FHandle := H;
  FRunning := False;
  FStartTime := 0;
end;

destructor TState.Destroy;
begin
  //
  inherited;
end;

{ TStateList }

destructor TStateList.Destroy;
begin
  Clear;
  inherited;
end;

function TStateList.Find(H: THandle): TState;
var
  I: NativeInt;
begin
  for I := 0 to Count - 1 do
  begin
    Result := TDiffState( inherited Get(I));
    with Result do
      if (Handle > 0) and (Handle = H) then
        Exit;
  end;
  Result := nil;
end;

procedure TStateList.Clear;
var
  I: NativeInt;
begin
  for I := 0 to Count - 1 do
    Items[I].Free;
  inherited;
end;

procedure TStateList.Delete(Index: Integer);
begin
  Items[Index].Free;
  inherited Delete(Index);
end;

function TStateList.Get(Index: Integer): TState;
begin
  Result := TDiffState( inherited Items[Index]);
end;

function TStateList.IndexOf(H: THandle): NativeInt;
begin
  for Result := 0 to Count - 1 do
    if Items[Result].Handle = H then
      Exit;
  Result := -1;
end;

{ TDiffState }

constructor TDiffState.Create;
begin
  inherited;
  FRequired := False;
  FContent := '';
end;

constructor TDiffState.Create(H: THandle);
begin
  inherited;
end;

destructor TDiffState.Destroy;
begin
  //
  inherited;
end;

{ TPatchState }

constructor TPatchState.Create;
begin
  inherited;
  FPatches := TJSONArray.Create;
end;

constructor TPatchState.Create(H: THandle);
begin
  inherited;
end;

destructor TPatchState.Destroy;
begin
  if Assigned(FPatches) then
    FreeAndNil(FPatches);
  inherited;
end;

{ TDiff }

function TDiff.GetSyntax(Doc: THandle): string;
var
  View: THandle;
  Idx: NativeInt;
  S: array [0 .. MAX_MODE_NAME - 1] of Char;
begin
  View := GetView(Doc);
  Idx := Editor_Info(View, MI_DOC_TO_INDEX, Doc);
  S[0] := #0;
  Editor_DocGetMode(View, Idx, @S);
  Result := LowerCase(S);
end;

procedure TDiff.LockState(State: TState);
begin
  with State do
  begin
    Running := True;
    StartTime := GetTickCount;
  end;
end;

procedure TDiff.UnlockState(State: TState; const Str: string = '');
begin
  State.Running := False;
  if Str <> '' then
    OutputString(Format(Str, [GetTickCount - State.StartTime]));
end;

function TDiff.IsLocked(State: TState): Boolean;
begin
  with State do
    if Running then
      Result := (GetTickCount - StartTime) < LockTimeOut
    else
      Result := False;
end;

procedure TDiff.DiffEditorSources(Sender: TObject; Data: TJSONObject);
var
  R: TJSONObject;
begin
  OutputString(Format('Received diff sources response: %s', [EncodeString(Data.ToString)]));
  if Data.Get('success').JsonValue is TJSONFalse then
  begin
    OutputString(Format('[FSocket] %s', [Data.Get('result').JsonValue.Value]));
    DiffComplete(StrToIntDef(Data.Get('file').JsonValue.Value, 0), nil, '');
  end
  else
  begin
    R := Data.Get('result').JsonValue as TJSONObject;
    DiffComplete(StrToIntDef(Data.Get('file').JsonValue.Value, 0),
      TJSONArray(R.Get('patches').JsonValue.Clone),
      R.Get('source').JsonValue.Value);
  end;
end;

procedure TDiff.DiffComplete(Doc: THandle; Patches: TJSONArray;
  const Content: string);
var
  State: TState;
begin
  if Assigned(FOnDiffComplete) then
    FOnDiffComplete(Self, Doc, Patches);
  State := FDiffStates.Find(Doc);
  if Assigned(State) then
  begin
    UnlockState(State, 'Diff performed in %dms');
    if not Patches.Null then
      TDiffState(State).Content := Content;
    if TDiffState(State).Required then
      Diff(Doc);
  end;
end;

procedure TDiff.PatchEditorSources(Sender: TObject; Data: TJSONObject);
var
  R: TJSONObject;
begin
  OutputString(Format('Received patched source: %s', [EncodeString(Data.ToString)]));
  if Data.Get('success').JsonValue is TJSONFalse then
  begin
    OutputString(Format('[FSocket] %s', [Data.Get('result').JsonValue.Value]));
    PatchComplete(StrToIntDef(Data.Get('file').JsonValue.Value, 0), nil);
  end
  else
  begin
    R := Data.Get('result').JsonValue as TJSONObject;
    PatchComplete(StrToIntDef(Data.Get('file').JsonValue.Value, 0), R);
  end;
end;

procedure TDiff.PatchComplete(ID: THandle; Content: TJSONObject);
var
  State: TState;
begin
  if Assigned(FOnPatchComplete) then
    FOnPatchComplete(Self, ID, Content);
  State := FPatchStates.Find(ID);
  if Assigned(State) then
  begin
    UnlockState(State, 'Patch performed in %dms');
    with TPatchState(State) do
      if Patches <> nil then
      begin
        Patch(ID, Patches);
        Patches.SetElements(nil);
      end;
  end;
end;

function TDiff.IsValidPatch(Content: TJSONObject): Boolean;
begin
  try
    with Content do
      Result := Get('id').JsonValue.Value = 'livestyle';
  except
    Result := False;
  end;
end;

function TDiff.StringifySelectors(Patch: TJSONArray): string;
var
  I: NativeInt;
  Data: TJSONObject;
  Path: TJSONArray;
begin
  Result := '';
  for I := 0 to Patch.Size - 1 do
  begin
    if Patch.Get(I).Null then
      Continue;
    Data := Patch.Get(I) as TJSONObject;
    if Data.Get('action').JsonValue.Value = 'remove' then
      Continue;
    Path := Data.Get('path').JsonValue as TJSONArray;
    if (Path.Size > 0) and ((Path.Get(0) as TJSONArray).Size > 0) then
      Result := Result + (Path.Get(0) as TJSONArray).Get(0).Value + ', ';
  end;
  Delete(Result, Length(Result) - 1, 2);
end;

constructor TDiff.Create;
begin
  FDiffStates := TStateList.Create;
  FPatchStates := TStateList.Create;
  with FSocket do
  begin
    OnDiff := DiffEditorSources;
    OnPatch := PatchEditorSources;
  end;
end;

destructor TDiff.Destroy;
begin
  if Assigned(FPatchStates) then
    FreeAndNil(FPatchStates);
  if Assigned(FDiffStates) then
    FreeAndNil(FDiffStates);
  inherited;
end;

procedure TDiff.PrepareDiff(Doc: THandle);
var
  State: TState;
begin
  with FDiffStates do
  begin
    if IndexOf(Doc) < 0 then
      Add(TDiffState.Create(Doc));
    State := Find(Doc);
  end;
  if Assigned(State) then
    TDiffState(State).Content := GetContent(Doc);
end;

procedure TDiff.Diff(Doc: THandle);
var
  State: TState;
begin
  if FDiffStates.IndexOf(Doc) < 0 then
  begin
    OutputString('Prepare buffer');
    PrepareDiff(Doc);
  end;
  State := FDiffStates.Find(Doc);
  if Assigned(State) then
  begin
    if IsLocked(State) then
      TDiffState(State).Required := True
    else
      StartDiff(Doc);
  end;
end;

procedure TDiff.StartDiff(Doc: THandle);
var
  State: TState;
  Content, PrevContent: string;
  Syntax: string;
  Client: TIdContext;
  Data: TJSONObject;
begin
  State := FDiffStates.Find(Doc);
  if not Assigned(State) then
    Exit;
  PrevContent := TDiffState(State).Content;
  Content := GetContent(Doc);
  Syntax := GetSyntax(Doc);
  TDiffState(State).Required := False;
  Client := FSocket.FindClient('css');
  if Assigned(Client) then
  begin
    with Client do
      if Assigned(Data) then
        OutputString(Format('Use connected "%s" client for diff', [TJSONObject(Data).Get('id').JsonValue.Value]));
    LockState(State);
    with TJSONObject.Create do
      try
        AddPair('action', 'diff');
        Data := TJSONObject.Create;
        with Data do
        begin
          AddPair('file', IntToStr(Doc));
          AddPair('syntax', Syntax);
          AddPair('source1', EncodeString(PrevContent));
          AddPair('source2', EncodeString(Content));
        end;
        AddPair('data', Data);
        FSocket.Send(ToString);
      finally
        Free;
      end;
  end
  else
    OutputString('No suitable client for diff');
end;

procedure TDiff.Patch(Doc: THandle; Patches: TJSONArray);
var
  I: NativeInt;
  State: TState;
begin
  OutputString('Request patching');
  with FPatchStates do
  begin
    if IndexOf(Doc) < 0 then
      Add(TPatchState.Create(Doc));
    State := Find(Doc);
  end;
  if Assigned(State) then
  begin
    if IsLocked(State) then
    begin
      OutputString('Batch patches');
      for I := 0 to Patches.Size - 1 do
        TPatchState(State).Patches.Add(Patches.Get(I).Value);
    end
    else
    begin
      OutputString('Start patching');
      StartPatch(Doc, Patches);
    end;
  end;
end;

procedure TDiff.StartPatch(Doc: THandle; Patch: TJSONArray);
var
  State: TState;
  Content: string;
  Syntax: string;
  Client: TIdContext;
  Data: TJSONObject;
begin
  State := FPatchStates.Find(Doc);
  if not Assigned(State) then
    Exit;
  Content := GetContent(Doc);
  Syntax := GetSyntax(Doc);
  Client := FSocket.FindClient('css');
  if Assigned(Client) then
  begin
    with Client do
      if Assigned(Data) then
        OutputString(Format('Use connected "%s" client for patching', [TJSONObject(Data).Get('id').JsonValue.Value]));
    LockState(State);
    with TJSONObject.Create do
      try
        AddPair('action', 'patch');
        Data := TJSONObject.Create;
        with Data do
        begin
          AddPair('file', IntToStr(Doc));
          AddPair('syntax', Syntax);
          AddPair('patches', Patch);
          AddPair('source', EncodeString(Content));
        end;
        AddPair('data', Data);
        FSocket.Send(ToString, Client);
      finally
        Free;
      end;
  end
  else
    OutputString('No suitable client for patching');
end;

procedure TDiff.ParsePatch(Data: TJSONObject; const AName: string);
var
  Files: TJSONObject;
  I: NativeInt;
begin
  if not IsValidPatch(Data) then
    Exit;
  with Data do
  begin
    Files := Get('files').JsonValue as TJSONObject;
    for I := 0 to Files.Size - 1 do
    begin
      with FPatches.Add do
      begin
        FileName := Files.Get(I).JsonString.Value;
        Selectors := StringifySelectors(Files.Get(I).JsonValue as TJSONArray);
        Name := AName;
        Data := Files.Get(I).JsonValue.ToString;
      end;
    end;
  end;
end;

initialization

FPatches := TPatchItems.Create;

finalization

FPatches.Free;

end.
