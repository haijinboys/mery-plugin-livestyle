unit mWebSocket;

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
  BroadcastEvents: array [0 .. 0] of string = ('update');

type
  TMessageEvent = procedure(Sender: TObject; const Str: string) of object;
  THandshakeEvent = procedure(Sender: TObject; AContext: TIdContext) of object;
  TUpdateEvent = procedure(Sender: TObject; Payload: TJSONObject; AContext: TIdContext) of object;
  TRequestUnsavedFilesEvent = procedure(Sender: TObject; Payload: TJSONObject; AContext: TIdContext) of object;
  TDiffEvent = procedure(Sender: TObject; Data: TJSONObject) of object;
  TPatchEvent = procedure(Sender: TObject; Data: TJSONObject) of object;

  TWebSocket = class(TObject)
  private
    { Private êÈåæ }
    FClients: TList;
    FHTTPServer: TIdHTTPServer;
    FOnOpen: TNotifyEvent;
    FOnClose: TNotifyEvent;
    FOnMessage: TMessageEvent;
    FOnHandshake: THandshakeEvent;
    FOnUpdate: TUpdateEvent;
    FOnRequestUnsavedFiles: TRequestUnsavedFilesEvent;
    FOnDiff: TDiffEvent;
    FOnPatch: TPatchEvent;
    procedure IdHTTPServerCommandGet(AContext: TIdContext;
      ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
    procedure IdHTTPServerConnect(AContext: TIdContext);
    procedure IdHTTPServerDisconnect(AContext: TIdContext);
    procedure WebSocketMessage(AContext: TIdContext; const Str: string);
    procedure ParseMessage(AContext: TIdContext; const Actn: string;
      Data: TJSONObject);
  public
    { Public êÈåæ }
    constructor Create;
    destructor Destroy; override;
    procedure Open(APort: NativeInt);
    procedure Close;
    procedure Send(const Str: string; AClient: TIdContext = nil;
      AExclude: TIdContext = nil);
    function FindClient(const Str: string): TIdContext;
    property OnOpen: TNotifyEvent read FOnOpen write FOnOpen;
    property OnClose: TNotifyEvent read FOnClose write FOnClose;
    property OnMessage: TMessageEvent read FOnMessage write FOnMessage;
    property OnHandShake: THandshakeEvent read FOnHandshake write FOnHandshake;
    property OnUpdate: TUpdateEvent read FOnUpdate write FOnUpdate;
    property OnRequestUnsavedFiles: TRequestUnsavedFilesEvent read FOnRequestUnsavedFiles write FOnRequestUnsavedFiles;
    property OnDiff: TDiffEvent read FOnDiff write FOnDiff;
    property OnPatch: TPatchEvent read FOnPatch write FOnPatch;
  end;

implementation

uses
  mUtils;

{ TWebSocket }

procedure TWebSocket.IdHTTPServerCommandGet(AContext: TIdContext;
  ARequestInfo: TIdHTTPRequestInfo; AResponseInfo: TIdHTTPResponseInfo);
  function HashKey(Key: string): string;
  var
    SHA1: TIdHashSHA1;
    Hash: TBytes;
    MIME: TIdEncoderMIME;
  begin
    SHA1 := TIdHashSHA1.Create;
    Hash := SHA1.HashString(Key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11');
    SHA1.Free;
    MIME := TIdEncoderMIME.Create(nil);
    Result := MIME.EncodeBytes(Hash);
    MIME.Free;
  end;

var
  S, RawHeader, SocketKey, SocketHash: string;
  I: NativeInt;
  WebSocket: Boolean;
  Payload: UTF8String;
  Extload: Int64;
  RawPayload: array of Byte;
  Opcode, PayloadLen: Byte;
  Mask: array [0 .. 3] of Byte;
  AConnection: TIdTCPConnection;
  AHandler: TIdIOHandler;
begin
  WebSocket := False;
  for I := 0 to ARequestInfo.RawHeaders.Count - 1 do
  begin
    RawHeader := ARequestInfo.RawHeaders[I];
    if Pos('sec-websocket-key:', Lowercase(RawHeader)) = 1 then
    begin
      WebSocket := True;
      SocketKey := Trim(Copy(RawHeader, 19, 99));
      SocketHash := HashKey(SocketKey);
      Break;
    end;
  end;
  if WebSocket then
  begin
    with AResponseInfo do
    begin
      ResponseNo := 101;
      ResponseText := 'Switching Protocols';
      ContentType := 'text/html';
      CharSet := 'utf-8';
      ContentLength := 0;
      CloseConnection := False;
      Connection := 'Upgrade';
      CustomHeaders.AddValue('Upgrade', 'websocket');
      CustomHeaders.AddValue('Sec-WebSocket-Accept', SocketHash);
      WriteHeader;
    end;
    AConnection := AContext.Connection;
    AHandler := AConnection.IOHandler;
    while AConnection.Connected do
    begin
      Opcode := AHandler.ReadByte;
      Opcode := Opcode and $0F;
      PayloadLen := AHandler.ReadByte;
      if PayloadLen and $80 = 0 then
        Break;
      PayloadLen := PayloadLen and $7F;
      if PayloadLen = 126 then
        Extload := AHandler.ReadWord(True)
      else
        if PayloadLen = 127 then
        Extload := AHandler.ReadInt64(True)
      else
        Extload := PayloadLen;
      for I := 0 to 3 do
        Mask[I] := AHandler.ReadByte;
      SetLength(RawPayload, Extload);
      for I := 0 to Extload - 1 do
        RawPayload[I] := AHandler.ReadByte xor Mask[I mod 4];
      if Opcode = 1 then
      begin
        SetString(Payload, PAnsiChar(@RawPayload[0]), Extload);
        WebSocketMessage(AContext, string(Payload));
      end
      else
      begin
        S := '';
        for I := 0 to Length(RawPayload) - 1 do
          S := S + IntToHex(RawPayload[I], 2) + ' ';
        if S <> '' then
            ;
      end;
      if Opcode = 8 then
        Break;
    end;
    AResponseInfo.CloseConnection := True;
  end
  else
  begin
    with AResponseInfo do
    begin
      ContentType := 'text/html';
      CharSet := 'utf-8';
      ContentText := 'LiveStyle websockets server is up and running';
    end;
  end;
end;

procedure TWebSocket.IdHTTPServerConnect(AContext: TIdContext);
begin
  OutputString('Client connected');
  if Assigned(FOnOpen) then
    FOnOpen(Self);
  FClients.Add(AContext);
end;

procedure TWebSocket.IdHTTPServerDisconnect(AContext: TIdContext);
begin
  // OutputString('Client disconnected');
  if Assigned(FOnClose) then
    FOnClose(Self);
  FClients.Remove(AContext);
end;

procedure TWebSocket.Send(const Str: string; AClient: TIdContext = nil;
  AExclude: TIdContext = nil);
  procedure WriteMessage(AContext: TIdContext; const S: string);
  var
    Len: NativeInt;
  begin
    Len := Length(UTF8String(S));
    with AContext.Connection.IOHandler do
    begin
      WriteBufferOpen;
      Write(Byte($81));
      if Len < 126 then
        Write(Byte(Len))
      else if Len < 65536 then
      begin
        Write(Byte(126));
        Write(Word(Len));
      end
      else
      begin
        Write(Byte(127));
        Write(Int64(Len));
      end;
      Write(S, TEncoding.UTF8);
      WriteBufferClose;
    end;
  end;

var
  I: NativeInt;
begin
  if AClient = nil then
  begin
    with FClients do
      if Count > 0 then
      begin
        OutputString(Format('Sending ws message %s', [EncodeString(Str)]));
        for I := 0 to Count - 1 do
          if Items[I] <> AExclude then
            WriteMessage(Items[I], Str);
      end
      else
        OutputString('Cannot send message, client list empty');
  end
  else
    WriteMessage(AClient, Str);
end;

function TWebSocket.FindClient(const Str: string): TIdContext;
var
  I, P: NativeInt;
  A: TJSONArray;
begin
  with FClients do
    for I := 0 to Count - 1 do
    begin
      Result := TIdContext(Items[I]);
      with Result do
        if Assigned(Data) then
        begin
          A := TJSONObject(Data).Get('supports').JsonValue as TJSONArray;
          for P := 0 to A.Size - 1 do
            if A.Get(P).Value = Str then
              Exit;
        end;
      Exit;
    end;
  Result := nil;
end;

procedure TWebSocket.WebSocketMessage(AContext: TIdContext; const Str: string);
var
  S: string;
  Actn: string;
  Data: TJSONObject;
begin
  OutputString(EncodeString(Str));
  if Assigned(FOnMessage) then
    FOnMessage(Self, Str);
  try
    with TJSONObject.ParseJSONValue(Str) as TJSONObject do
      try
        Actn := Get('action').JsonValue.Value;
        Data := Get('data').JsonValue as TJSONObject;
        ParseMessage(AContext, Actn, Data);
        for S in BroadcastEvents do
          if S = Actn then
            Send(Str, AContext);
        if Actn = 'handshake' then
          AContext.Data := Data.Clone
        else if Actn = 'error' then
          OutputString(Format('[Client] %s', [Data.Get('message').JsonValue.Value]));
      finally
        Free;
      end;
  except
    //
  end;
end;

procedure TWebSocket.ParseMessage(AContext: TIdContext; const Actn: string;
  Data: TJSONObject);
begin
  if Actn = 'handshake' then
  begin
    if Assigned(FOnHandshake) then
      FOnHandshake(Self, AContext);
  end
  else if Actn = 'update' then
  begin
    if Assigned(FOnUpdate) then
      FOnUpdate(Self, Data, AContext);
  end
  else if Actn = 'requestUnsavedFiles' then
  begin
    if Assigned(FOnRequestUnsavedFiles) then
      FOnRequestUnsavedFiles(Self, Data, AContext);
  end
  else if Actn = 'diff' then
  begin
    if Assigned(FOnDiff) then
      FOnDiff(Self, Data);
  end
  else if Actn = 'patch' then
  begin
    if Assigned(FOnPatch) then
      FOnPatch(Self, Data);
  end;
end;

constructor TWebSocket.Create;
begin
  FClients := TList.Create;
  FHTTPServer := TIdHTTPServer.Create(nil);
  with FHTTPServer do
  begin
    OnCommandGet := IdHTTPServerCommandGet;
    OnConnect := IdHTTPServerConnect;
    OnDisconnect := IdHTTPServerDisconnect;
    KeepAlive := True;
  end;
end;

destructor TWebSocket.Destroy;
begin
  Close;
  if Assigned(FHTTPServer) then
    FreeAndNil(FHTTPServer);
  if Assigned(FClients) then
    FreeAndNil(FClients);
  inherited;
end;

procedure TWebSocket.Open(APort: NativeInt);
begin
  with FHTTPServer do
  begin
    with Bindings.Add do
    begin
      IP := '127.0.0.1';
      Port := APort;
    end;
    DefaultPort := APort;
    Active := True;
  end;
end;

procedure TWebSocket.Close;
begin
  FHTTPServer.Active := False;
  FClients.Clear;
end;

end.
