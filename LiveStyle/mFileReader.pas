unit mFileReader;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Data.DBXPlatform, Data.DBXJSON, System.Generics.Collections;
{$ELSE}
  Windows, Messages, SysUtils, Classes, DBXPlatform, DBXJSON,
  Generics.Collections;
{$IFEND}


const
  ReadTimeout = 20 * 1000;

type
  TFileCacheEntity = class(TObject)
  private
    { Private êÈåæ }
    FUri: string;
    FLastRead: Cardinal;
    FLastAccess: Cardinal;
    FContent: string;
    class constructor Create;
    class destructor Destroy;
    function IsValid: Boolean;
  public
    { Public êÈåæ }
    function GetContent: string;
    constructor Create(const AUri: string);
    destructor Destroy; override;
  end;

function GetFileContents(const Uri: string): string;
function ReadFile(const Path: string): string;

var
  FFileCache: TObjectDictionary<string, TFileCacheEntity>;

implementation

uses
  NotePadEncoding, mCommon, mUtils, mJSONHelper;

function GetFileContents(const Uri: string): string;
begin
  Result := '';
  if not FFileCache.ContainsKey(Uri) then
    if FileExists2(Uri) then
      FFileCache.Add(Uri, TFileCacheEntity.Create(Uri))
    else
      Exit;
  if FFileCache.ContainsKey(Uri) then
    Result := FFileCache[Uri].GetContent;
  if Result = '' then
    if FFileCache.ContainsKey(Uri) then
      FFileCache.Remove(Uri);
end;

function ReadFile(const Path: string): string;
var
  E: TFileEncoding;
  E1, E2: Boolean;
begin
  E := feNone;
  Result := LoadFromFile(Path, E, True, E1, E2);
end;

{ TFileCacheEntity }

class constructor TFileCacheEntity.Create;
begin

end;

class destructor TFileCacheEntity.Destroy;
begin

end;

constructor TFileCacheEntity.Create(const AUri: string);
begin
  FUri := AUri;
  FLastRead := 0;
  FLastAccess := 0;
  FContent := '';
end;

destructor TFileCacheEntity.Destroy;
begin
  //
  inherited;
end;

function TFileCacheEntity.GetContent: string;
var
  S: string;
begin
  Result := '';
  if (FContent <> '') and IsValid then
    FContent := '';
  if FContent = '' then
  begin
    FLastRead := GetTickCount;
    S := ReadFile(FUri);
    if S = '' then
      Exit;
    with TJSONObject.Create do
      try
        AddPair('uri', FUri);
        AddPair('content', S);
        AddPair('hash', IntToStr(Hash(S)));
        FContent := ToJSON;
      finally
        Free;
      end;
  end;
  FLastAccess := GetTickCount;
  Result := FContent;
end;

function TFileCacheEntity.IsValid: Boolean;
begin
  Result := FLastRead < GetTickCount + ReadTimeout;
end;

initialization

FFileCache := TObjectDictionary<string, TFileCacheEntity>.Create([doOwnsValues]);

finalization

if Assigned(FFileCache) then
  FreeAndNil(FFileCache);

end.
