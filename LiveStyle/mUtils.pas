unit mUtils;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  System.Generics.Collections;
{$ELSE}
  Windows, Messages, SysUtils, Classes, Generics.Collections;
{$IFEND}


const
  SupportedSyntaxes: array [0 .. 2] of string = ('css', 'less', 'scss');
  MaxLineLength = 8000;

resourcestring
  SUntitled = '[untitled:%d]';

type
  THandleArray = array of THandle;
  TStringArray = array of string;

function Hash(const S: string): Cardinal;
function GetHandle(Doc: THandle): THandle;
function GetActiveDoc(H: THandle): THandle;
function GetActiveWindow: THandle;
function IsModified(Doc: THandle): Boolean;
function GetContent(Doc: THandle): string;
function GetFileName(Doc: THandle): string;
function GetFileNameSub(Doc: THandle): string;
function GetTempFileName(Doc: THandle): string;
function GetAllDocs: THandleArray;
function GetDocForUri(const Path: string): THandle;
function GetDocHash(Doc: THandle): Cardinal;
function GetSupportedFiles: TStringArray;
function IsSupportedDoc(Doc: THandle; AStrict: Boolean; out ASyntax: string): Boolean;
function GetDocSyntax(Doc: THandle): string;
function GetPayload(Doc: THandle; const AData: string = ''): string;
procedure Lock(Doc: THandle);
procedure Unlock(Doc: THandle);
function IsLocked(Doc: THandle): Boolean;
procedure OutputString(const S: string);
procedure Debug(const S: string);

var
  FLocks: TDictionary<THandle, TObject>;

implementation

uses
{$IF CompilerVersion > 22.9}
  System.StrUtils, System.RegularExpressions, Data.DBXPlatform, Data.DBXJSON,
{$ELSE}
  StrUtils, RegularExpressions, DBXPlatform, DBXJSON,
{$IFEND}
  IdHashCRC, StringBuffer, mMain, mCommon, mPlugin, mJSONHelper;

function Hash(const S: string): Cardinal;
begin
  with TIdHashCRC32.Create do
    try
      Result := HashValue(S);
    finally
      Free;
    end;
end;

function GetHandle(Doc: THandle): THandle;
var
  I, J, L: Integer;
begin
  for I := 0 to FList.Count - 1 do
  begin
    Result := FList[I].Handle;
    L := Editor_Info(Result, MI_GET_DOC_COUNT, 0);
    for J := 0 to L - 1 do
      if THandle(Editor_Info(Result, MI_INDEX_TO_DOC, J)) = Doc then
        Exit;
  end;
  Result := 0;
end;

function GetActiveDoc(H: THandle): THandle;
begin
  if H > 0 then
    Result := Editor_Info(H, MI_GET_ACTIVE_DOC, 0)
  else
    Result := 0;
end;

function GetActiveWindow: THandle;
var
  I: Integer;
  H: THandle;
begin
  Result := 0;
  H := GetAncestor(GetFocus, GA_ROOTOWNER);
  for I := 0 to FList.Count - 1 do
  begin
    Result := FList[I].Handle;
    if Result = H then
      Exit;
  end;
end;

function IsModified(Doc: THandle): Boolean;
var
  H: THandle;
  N: Integer;
begin
  H := GetHandle(Doc);
  N := Editor_Info(H, MI_DOC_TO_INDEX, Doc);
  Result := Editor_DocGetModified(H, N);
end;

function GetSupportedFiles: TStringArray;
var
  H, Doc: THandle;
  S: array [0 .. MAX_PATH] of Char;
  T: string;
  I, J, L: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to FList.Count - 1 do
  begin
    H := FList[I].Handle;
    L := Editor_Info(H, MI_GET_DOC_COUNT, 0);
    for J := 0 to L - 1 do
    begin
      Doc := Editor_Info(H, MI_INDEX_TO_DOC, J);
      if IsSupportedDoc(Doc, False, T) then
      begin
        Editor_DocInfo(H, J, MI_GET_FILE_NAME, LPARAM(@S));
        SetLength(Result, Length(Result) + 1);
        Result[Length(Result) - 1] := IfThen(S = '', GetTempFileName(Doc), S);
      end;
    end;
  end;
end;

function GetContent(Doc: THandle): string;
var
  H: THandle;
  S: array [0 .. MaxLineLength + 1] of Char;
  I, L: Integer;
  N: Integer;
  G: TGetLineInfo;
begin
  H := GetHandle(Doc);
  with TStringBuffer.Create(0) do
    try
      Clear;
      N := Editor_Info(H, MI_DOC_TO_INDEX, Doc);
      L := Editor_DocGetLines(H, N, POS_VIEW);
      G.flags := MakeLong(FLAG_WITH_CRLF or FLAG_GET_CRLF_BYTE, N + 1);
      G.byteCrLf := FLAG_LF_ONLY;
      G.cch := Length(S);
      for I := 0 to L - 1 do
      begin
        G.yLine := I;
        S[0] := #0;
        Editor_GetLine(H, @G, S);
        Append(S);
      end;
      Result := GetString;
    finally
      Free;
    end;
end;

function GetFileName(Doc: THandle): string;
begin
  Result := GetFileNameSub(Doc);
  Result := IfThen(Result = '', GetTempFileName(Doc), Result);
end;

function GetFileNameSub(Doc: THandle): string;
var
  H: THandle;
  S: array [0 .. MAX_PATH] of Char;
  P: Integer;
begin
  H := GetHandle(Doc);
  P := Editor_Info(H, MI_DOC_TO_INDEX, Doc);
  S[0] := #0;
  Editor_DocInfo(H, P, MI_GET_FILE_NAME, LPARAM(@S));
  Result := S;
end;

function GetTempFileName(Doc: THandle): string;
begin
  Result := Format(SUntitled, [Doc]);
end;

function GetAllDocs: THandleArray;
var
  H, Doc: THandle;
  I, J, L: Integer;
begin
  SetLength(Result, 0);
  for I := 0 to FList.Count - 1 do
  begin
    H := FList[I].Handle;
    L := Editor_Info(H, MI_GET_DOC_COUNT, 0);
    for J := 0 to L - 1 do
    begin
      Doc := Editor_Info(H, MI_INDEX_TO_DOC, J);
      SetLength(Result, Length(Result) + 1);
      Result[Length(Result) - 1] := Doc;
    end;
  end;
end;

function GetDocForUri(const Path: string): THandle;
var
  H: THandle;
  I, J, L: Integer;
begin
  for I := 0 to FList.Count - 1 do
  begin
    H := FList[I].Handle;
    L := Editor_Info(H, MI_GET_DOC_COUNT, 0);
    for J := 0 to L - 1 do
    begin
      Result := Editor_Info(H, MI_INDEX_TO_DOC, J);
      if SameFileName(GetFileName(Result), Path) then
        Exit;
    end;
  end;
  Result := 0;
end;

function GetDocHash(Doc: THandle): Cardinal;
begin
  Result := Hash(GetContent(Doc));
end;

function IsSupportedDoc(Doc: THandle; AStrict: Boolean;
  out ASyntax: string): Boolean;
var
  S: string;
  M: TMatch;
  H: THandle;
  N: Integer;
  Mode: array [0 .. MAX_MODE_NAME - 1] of Char;
  Name: array [0 .. MAX_PATH] of Char;
begin
  M := TRegEx.Match(GetFileName(Doc), '(?i)\.(css|less|scss)$');
  ASyntax := '';
  if M.Success then
    ASyntax := M.Groups[1].Value
  else
  begin
    H := GetHandle(Doc);
    N := Editor_Info(H, MI_DOC_TO_INDEX, Doc);
    Mode[0] := #0;
    Editor_DocGetMode(H, N, @Mode);
    Name[0] := #0;
    Editor_DocInfo(H, N, MI_GET_FILE_NAME, LPARAM(@Name));
    for S in SupportedSyntaxes do
      if ((Name = '') and (not AStrict)) or SameText(S, Mode) then
      begin
        ASyntax := S;
        Break;
      end;
  end;
  Result := ASyntax <> '';
end;

function GetDocSyntax(Doc: THandle): string;
var
  S: string;
begin
  if IsSupportedDoc(Doc, False, S) then
    Result := LowerCase(S)
  else
    Result := 'css';
end;

function GetPayload(Doc: THandle; const AData: string = ''): string;
var
  S, Syntax: string;
  I: Integer;
  P: TJSONObject;
begin
  S := GetContent(Doc);
  Syntax := GetDocSyntax(Doc);
  with TJSONObject.Create do
    try
      AddPair('uri', GetFileName(Doc));
      AddPair('syntax', Syntax);
      AddPair(TJSONPair.Create('content', S));
      AddPair('hash', IntToStr(Hash(S)));
      if AData <> '' then
      begin
        P := TJSONObject.ParseJSONValue(AData) as TJSONObject;
        if P <> nil then
          try
            for I := 0 to P.Size - 1 do
              AddPair(P.Get(I).Clone as TJSONPair);
          finally
            P.Free;
          end;
      end;
      Result := ToJSON;
    finally
      Free;
    end;
end;

procedure Lock(Doc: THandle);
begin
  if not FLocks.ContainsKey(Doc) then
    FLocks.Add(Doc, nil);
end;

procedure Unlock(Doc: THandle);
begin
  if FLocks.ContainsKey(Doc) then
    FLocks.Remove(Doc);
end;

function IsLocked(Doc: THandle): Boolean;
begin
  Result := FLocks.ContainsKey(Doc);
end;

procedure OutputString(const S: string);
var
  I: Integer;
begin
  for I := 0 to FList.Count - 1 do
    Editor_OutputString(FList[I].Handle, PChar(Format('LiveStyle: %s', [S + #13#10])), 0);
end;

procedure Debug(const S: string);
begin
  if FDebug then
    OutputString(S);
end;

initialization

FLocks := TDictionary<THandle, TObject>.Create;

finalization

if Assigned(FLocks) then
  FreeAndNil(FLocks);

end.
