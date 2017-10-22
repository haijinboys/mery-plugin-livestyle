unit mDiff;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Data.DBXPlatform, Data.DBXJSON;
{$ELSE}
  Windows, Messages, SysUtils, Classes, DBXPlatform, DBXJSON;
{$IFEND}


const
  WaitTimeout = 10 * 1000;

type
  TDiff = class(TObject)
  private
    { Private êÈåæ }
    FLockedBy: string;
    FCreated: Cardinal;
    FPending: TStringList;
    procedure NextQueued(Release: Boolean = False);
  public
    { Public êÈåæ }
    constructor Create;
    destructor Destroy; override;
    procedure Diff(Doc: THandle);
    procedure HandleDiffResponse(const Data: string);
    procedure HandleErrorResponse(const Data: string);
  end;

implementation

uses
  mMain, mUtils, mJSONHelper;

{ TDiff }

constructor TDiff.Create;
begin
  FLockedBy := '';
  FCreated := 0;
  FPending := TStringList.Create;
end;

destructor TDiff.Destroy;
begin
  if Assigned(FPending) then
    FreeAndNil(FPending);
  inherited;
end;

procedure TDiff.Diff(Doc: THandle);
var
  S: string;
begin
  S := GetFileName(Doc);
  if FPending.IndexOf(S) < 0 then
  begin
    Debug(Format('Pending patch request for %s', [S]));
    FPending.Add(S);
  end;
  NextQueued;
end;

procedure TDiff.HandleDiffResponse(const Data: string);
var
  S: string;
  P: TJSONObject;
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
  OutputString(Format('Got diff response for %s', [S]));
  if (FLockedBy <> '') and (FLockedBy = S) then
  begin
    Debug('Release diff lock, move to next item');
    NextQueued(True);
  end;
end;

procedure TDiff.HandleErrorResponse(const Data: string);
var
  S, T: string;
  P, Q: TJSONObject;
begin
  S := '';
  T := '';
  P := TJSONObject.ParseJSONValue(Data) as TJSONObject;
  if P <> nil then
    try
      if P.Get('origin') <> nil then
      begin
        Q := P.Get('origin').JsonValue as TJSONObject;
        if Q.Get('name') <> nil then
          S := Q.Get('name').JsonValue.Value;
        if Q.Get('uri') <> nil then
          T := Q.Get('uri').JsonValue.Value;
      end
      else
      begin
        NextQueued(True);
        Exit;
      end;
    finally
      P.Free;
    end
  else
  begin
    NextQueued(True);
    Exit;
  end;
  if (S = 'calculate-diff') and (FLockedBy <> '') and (FLockedBy = T) then
    NextQueued(True);
end;

procedure TDiff.NextQueued(Release: Boolean);
var
  S: string;
  Doc: THandle;
begin
  if Release then
  begin
    Debug('Release diff lock');
    FLockedBy := '';
  end;
  if (FLockedBy <> '') and (FCreated < GetTickCount - WaitTimeout) then
  begin
    Debug('Waiting response is obsolete, reset');
    FLockedBy := '';
  end;
  if (FLockedBy = '') and (FPending.Count > 0) then
  begin
    S := FPending[0];
    FPending.Delete(0);
    Doc := GetDocForUri(S);
    if Doc = 0 then
    begin
      Debug('No view, move to next queued diff item');
      NextQueued;
      Exit;
    end;
    Debug('Send "calculate-diff" message');
    FLockedBy := S;
    FCreated := GetTickCount;
    with TJSONObject.ParseJSONValue(GetPayload(Doc)) as TJSONObject do
      try
        S := ToJSON;
      finally
        Free;
      end;
    FClient.Send('calculate-diff', S);
  end
  else
    Debug('Diff lock, waiting for response');
end;

end.
