unit mServer;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Data.DBXPlatform, Data.DBXJSON,
{$ELSE}
  Windows, Messages, SysUtils, Classes, DBXPlatform, DBXJSON,
{$IFEND}
  sgcWebSocket_Classes, sgcWebSocket;

type
  TServer = class(TObject)
  private
    { Private êÈåæ }
    FClients: TStringList;
    FPatchers: TStringList;
    FEditors: TStringList;
    FServer: TsgcWebSocketHTTPServer;
    function CreateMessage(const AName: string; const AData: string = ''): string;
    procedure RemoveClient(const AClient: string);
    procedure Send(AReceivers: TStrings; const AMessage: string; const AExclude: string = '');
    procedure ServerConnect(Connection: TsgcWSConnection);
    procedure ServerMessage(Connection: TsgcWSConnection; const Text: string);
    procedure ServerDisconnect(Connection: TsgcWSConnection; Code: Integer);
  public
    { Public êÈåæ }
    constructor Create;
    destructor Destroy; override;
    procedure Start(const APort: Integer = 54000);
    procedure Stop;
  end;

implementation

uses
  mUtils, mJSONHelper;

{ TServer }

constructor TServer.Create;
begin
  FClients := TStringList.Create;
  FPatchers := TStringList.Create;
  FEditors := TStringList.Create;
  FServer := TsgcWebSocketHTTPServer.Create(nil);
  with FServer do
  begin
    KeepAlive := True;
    OnConnect := ServerConnect;
    OnDisconnect := ServerDisconnect;
    OnMessage := ServerMessage;
  end;
end;

function TServer.CreateMessage(const AName, AData: string): string;
begin
  with TJSONObject.Create do
    try
      AddPair('name', AName);
      if AData <> '' then
        AddPair('data', TJSONObject.ParseJSONValue(AData));
      Result := ToJSON;
    finally
      Free;
    end;
end;

destructor TServer.Destroy;
begin
  if Assigned(FEditors) then
    FreeAndNil(FEditors);
  if Assigned(FPatchers) then
    FreeAndNil(FPatchers);
  if Assigned(FClients) then
    FreeAndNil(FClients);
  if Assigned(FServer) then
    FreeAndNil(FServer);
  inherited;
end;

procedure TServer.Start(const APort: Integer);
begin
  Stop;
  OutputString(Format('Starting LiveStyle server on port %d', [APort]));
  with FServer do
  begin
    Port := APort;
    Active := True;
  end;
end;

procedure TServer.Stop;
begin
  FServer.DisconnectAll;
  FClients.Clear;
  FPatchers.Clear;
  FEditors.Clear;
  OutputString('Stopping server');
  FServer.Active := False;
end;

procedure TServer.RemoveClient(const AClient: string);
var
  S: string;
  I: Integer;
begin
  I := FClients.IndexOf(AClient);
  if I > -1 then
    FClients.Delete(I);
  I := FPatchers.IndexOf(AClient);
  if I > -1 then
    FPatchers.Delete(I);
  Send(FClients, CreateMessage('client-disconnect'));
  for I := FEditors.Count - 1 downto 0 do
    if FEditors.ValueFromIndex[I] = AClient then
    begin
      with TJSONObject.Create do
        try
          AddPair('id', FEditors.Names[I]);
          S := ToJSON;
        finally
          Free;
        end;
      Send(FClients, CreateMessage('editor-disconnect', S));
      FEditors.Delete(I);
    end;
end;

procedure TServer.Send(AReceivers: TStrings; const AMessage, AExclude: string);
var
  I: Integer;
  R: TStrings;
begin
  R := TStringList.Create;
  try
    R.Assign(AReceivers);
    if AExclude <> '' then
      for I := R.Count - 1 downto 0 do
        if R[I] = AExclude then
          R.Delete(I);
    if R.Count = 0 then
      Debug('Cannot send message, client list empty')
    else
      for I := 0 to R.Count - 1 do
        FServer.WriteData(R[I], AMessage);
  finally
    R.Free;
  end;
end;

procedure TServer.ServerConnect(Connection: TsgcWSConnection);
begin
  Send(FClients, CreateMessage('client-connect'), Connection.Guid);
  FClients.Add(Connection.Guid);
  Debug(Format('Client connected, total clients: %d', [FClients.Count]));
end;

procedure TServer.ServerDisconnect(Connection: TsgcWSConnection; Code: Integer);
begin
  Debug('Client disconnected');
  RemoveClient(Connection.Guid);
end;

procedure TServer.ServerMessage(Connection: TsgcWSConnection;
  const Text: string);
var
  P: TJSONObject;
  R: TStrings;
begin
  P := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  if P <> nil then
  begin
    try
      R := FClients;
      if P.Get('name') <> nil then
      begin
        if P.Get('name').JsonValue.Value = 'editor-connect' then
          FEditors.Values[(P.Get('data').JsonValue as TJSONObject).Get('id').JsonValue.Value] := Connection.Guid
        else if P.Get('name').JsonValue.Value = 'patcher-connect' then
          FPatchers.Add(Connection.Guid)
        else if (P.Get('name').JsonValue.Value = 'calculate-diff') or (P.Get('name').JsonValue.Value = 'apply-patch') then
          R := FPatchers;
      end;
    finally
      P.Free;
    end;
    Send(R, Text, Connection.Guid);
  end
  else
  begin
    OutputString('Error while handling incoming message');
    OutputString(Text);
  end;
end;

end.
