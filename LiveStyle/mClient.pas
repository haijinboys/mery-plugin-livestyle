unit mClient;

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
  TMessageEvent = procedure(Sender: TObject; const Name, Data: string) of object;

  TClient = class(TObject)
  private
    { Private êÈåæ }
    FClient: TsgcWebSocketClient;
    FOnConnect: TNotifyEvent;
    FOnDisconnect: TNotifyEvent;
    FOnMessage: TMessageEvent;
    function GetConnected: Boolean;
    procedure ClientConnect(Connection: TsgcWSConnection);
    procedure ClientDisconnect(Connection: TsgcWSConnection; Code: Integer);
    procedure ClientMessage(Connection: TsgcWSConnection; const Text: string);
  public
    { Public êÈåæ }
    constructor Create;
    destructor Destroy; override;
    procedure Connect(const AHost: string = '127.0.0.1';
      const APort: Integer = 54000; const AEndPoint: string = '/livestyle');
    procedure Send(const AName: string; const AData: string = '');
    property Connected: Boolean read GetConnected;
    property OnConnect: TNotifyEvent read FOnConnect write FOnConnect;
    property OnDisconnect: TNotifyEvent read FOnDisconnect write FOnDisconnect;
    property OnMessage: TMessageEvent read FOnMessage write FOnMessage;
  end;

implementation

uses
  mUtils, mJSONHelper;

{ TClient }

constructor TClient.Create;
begin
  FClient := TsgcWebSocketClient.Create(nil);
  with FClient do
  begin
    OnConnect := ClientConnect;
    OnDisconnect := ClientDisconnect;
    OnMessage := ClientMessage;
  end;
end;

destructor TClient.Destroy;
begin
  if Assigned(FClient) then
    FreeAndNil(FClient);
  inherited;
end;

procedure TClient.Connect(const AHost: string; const APort: Integer;
  const AEndPoint: string);
begin
  if Connected then
  begin
    Debug('Client already connected');
    Exit;
  end;
  with FClient do
  begin
    Host := AHost;
    Port := APort;
    Options.Parameters := AEndPoint;
    Active := True;
  end;
end;

procedure TClient.Send(const AName, AData: string);
var
  S: string;
begin
  with TJSONObject.Create do
    try
      AddPair('name', AName);
      AddPair('data', TJSONObject.ParseJSONValue(AData) as TJSONObject);
      S := ToJSON;
    finally
      Free;
    end;
  OutputString(Format('Sending message "%s"', [AName]));
  FClient.WriteData(S);
end;

function TClient.GetConnected: Boolean;
begin
  Result := FClient.Active;
end;

procedure TClient.ClientConnect(Connection: TsgcWSConnection);
begin
  with FClient do
    Debug(Format('Connected to server at ws://%s:%d%s', [Host, Port, Options.Parameters]));
  if Assigned(FOnConnect) then
    FOnConnect(Self);
end;

procedure TClient.ClientDisconnect(Connection: TsgcWSConnection; Code: Integer);
begin
  Debug('Disconnected from server');
  if Assigned(FOnDisconnect) then
    FOnDisconnect(Self);
end;

procedure TClient.ClientMessage(Connection: TsgcWSConnection;
  const Text: string);
var
  Name, Data: string;
  P: TJSONObject;
begin
  Name := '';
  Data := '';
  P := TJSONObject.ParseJSONValue(Text) as TJSONObject;
  if P <> nil then
    try
      if P.Get('name') <> nil then
        Name := P.Get('name').JsonValue.Value;
      if P.Get('data') <> nil then
        Data := (P.Get('data').JsonValue as TJSONObject).ToJSON;
    finally
      P.Free;
    end;
  Debug(Format('Received message "%s"', [Name]));
  if Assigned(FOnMessage) then
    FOnMessage(Self, Name, Data);
end;

end.
