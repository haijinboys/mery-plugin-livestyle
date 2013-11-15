unit mUtils;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes;
{$ELSE}
  Windows, Messages, SysUtils, Classes;
{$IFEND}


const
  MaxLineLength = 8000;

resourcestring
  SUntitled = '<untitled:%d>';

type
  THandleArray = array of THandle;
  TStringArray = array of string;

function GetView(Doc: THandle): THandle;
function GetModified(Doc: THandle): Boolean;
function GetContent(Doc: THandle): string;
function GetFileName(Doc: THandle): string;
function GetTempFileName(Doc: THandle): string;
function GetAllDocs: THandleArray;
function GetDocForFile(const Path: string): THandle;
function GetActiveDoc(View: THandle): THandle;
function GetCSSFiles: TStringArray;
function IsCssDoc(Doc: THandle): Boolean;
function EncodeString(const Str: string): string;
procedure OutputString(const Str: string);

implementation

uses
{$IF CompilerVersion > 22.9}
  System.StrUtils,
{$ELSE}
  StrUtils,
{$IFEND}
  mMain, mPlugin, StringBuffer;

function GetView(Doc: THandle): THandle;
var
  I, P, Len: NativeInt;
begin
  for I := 0 to FList.Count - 1 do
  begin
    Result := FList[I].Handle;
    Len := Editor_Info(Result, MI_GET_DOC_COUNT, 0);
    for P := 0 to Len - 1 do
      if Editor_Info(Result, MI_INDEX_TO_DOC, P) = NativeInt(Doc) then
        Exit;
  end;
  Result := 0;
end;

function GetModified(Doc: THandle): Boolean;
var
  View: THandle;
  Idx: NativeInt;
begin
  View := GetView(Doc);
  Idx := Editor_Info(View, MI_DOC_TO_INDEX, Doc);
  Result := Editor_DocGetModified(View, Idx);
end;

function GetContent(Doc: THandle): string;
var
  View: THandle;
  S: array [0 .. MaxLineLength + 1] of Char;
  I, Len, Idx: NativeInt;
  Info: TGetLineInfo;
begin
  View := GetView(Doc);
  with TStringBuffer.Create(0) do
    try
      Clear;
      Idx := Editor_Info(View, MI_DOC_TO_INDEX, Doc);
      Len := Editor_DocGetLines(View, Idx, POS_VIEW);
      Info.flags := MakeLong(FLAG_WITH_CRLF or FLAG_GET_CRLF_BYTE, Idx + 1);
      Info.byteCrLf := FLAG_LF_ONLY;
      Info.cch := Length(S);
      for I := 0 to Len - 1 do
      begin
        Info.yLine := I;
        S[0] := #0;
        Editor_GetLine(View, @Info, S);
        Append(S);
      end;
      Result := GetString;
    finally
      Free;
    end;
end;

function GetFileName(Doc: THandle): string;
var
  View: THandle;
  S: array [0 .. MAX_PATH] of Char;
  Idx: NativeInt;
begin
  Result := '';
  View := GetView(Doc);
  Idx := Editor_Info(View, MI_DOC_TO_INDEX, Doc);
  Editor_DocInfo(View, Idx, MI_GET_FILE_NAME, LPARAM(@S));
  Result := IfThen(S = '', GetTempFileName(Doc), S);
end;

function GetTempFileName(Doc: THandle): string;
begin
  Result := Format(SUntitled, [Doc]);
end;

function GetAllDocs: THandleArray;
var
  View, Doc: THandle;
  I, P, Len: NativeInt;
begin
  SetLength(Result, 0);
  for I := 0 to FList.Count - 1 do
  begin
    View := FList[I].Handle;
    Len := Editor_Info(View, MI_GET_DOC_COUNT, 0);
    for P := 0 to Len - 1 do
    begin
      Doc := Editor_Info(View, MI_INDEX_TO_DOC, P);
      SetLength(Result, Length(Result) + 1);
      Result[Length(Result) - 1] := Doc;
    end;
  end;
end;

function GetDocForFile(const Path: string): THandle;
var
  View: THandle;
  I, P, Len: NativeInt;
begin
  for I := 0 to FList.Count - 1 do
  begin
    View := FList[I].Handle;
    Len := Editor_Info(View, MI_GET_DOC_COUNT, 0);
    for P := 0 to Len - 1 do
    begin
      Result := Editor_Info(View, MI_INDEX_TO_DOC, P);
      if SameText(GetFileName(Result), Path) then
        Exit;
    end;
  end;
  Result := 0;
end;

function GetActiveDoc(View: THandle): THandle;
begin
  Result := Editor_Info(View, MI_GET_ACTIVE_DOC, 0);
end;

function GetCSSFiles: TStringArray;
var
  View, Doc: THandle;
  S: array [0 .. MAX_PATH] of Char;
  I, P, Len: NativeInt;
begin
  SetLength(Result, 0);
  for I := 0 to FList.Count - 1 do
  begin
    View := FList[I].Handle;
    Len := Editor_Info(View, MI_GET_DOC_COUNT, 0);
    for P := 0 to Len - 1 do
    begin
      Doc := Editor_Info(View, MI_INDEX_TO_DOC, P);
      if IsCssDoc(Doc) then
      begin
        Editor_DocInfo(View, P, MI_GET_FILE_NAME, LPARAM(@S));
        SetLength(Result, Length(Result) + 1);
        Result[Length(Result) - 1] := IfThen(S = '', GetTempFileName(Doc), S);
      end;
    end;
  end;
end;

function IsCssDoc(Doc: THandle): Boolean;
var
  View: THandle;
  S: array [0 .. MAX_MODE_NAME - 1] of Char;
  Idx: NativeInt;
begin
  View := GetView(Doc);
  Idx := Editor_Info(View, MI_DOC_TO_INDEX, Doc);
  S[0] := #0;
  Editor_DocGetMode(View, Idx, @S);
  Result := SameText(S, 'CSS');
end;

function EncodeString(const Str: string): string;
  procedure AddStr(const S: string; var D: string; var I: NativeInt); inline;
  begin
    Insert(S, D, I);
    Delete(D, I + 2, 1);
    Inc(I, 2);
  end;
  procedure AddHexStr(const S: string; var D: string; var I: NativeInt); inline;
  begin
    Insert(S, D, I);
    Delete(D, I + 6, 1);
    Inc(I, 6);
  end;

var
  C: Char;
  I, P, Len: NativeInt;
begin
  Result := Str;
  P := 1;
  Len := Length(Str);
  for I := 1 to Len do
  begin
    C := Str[I];
    case C of
      '/', '\', '"':
        begin
          Insert('\', Result, P);
          Inc(P, 2);
        end;
      #8:
        AddStr('\b', Result, P);
      #9:
        AddStr('\t', Result, P);
      #10:
        AddStr('\n', Result, P);
      #12:
        AddStr('\f', Result, P);
      #13:
        AddStr('\r', Result, P);
      #0 .. #7, #11, #14 .. #31:
        AddHexStr('\u' + IntToHex(Word(C), 4), Result, P);
    else
      if Word(C) > 127 then
        AddHexStr('\u' + IntToHex(Word(C), 4), Result, P)
      else
        Inc(P);
    end;
  end;
end;

procedure OutputString(const Str: string);
var
  I: NativeInt;
begin
  if not FDebug then
    Exit;
  for I := 0 to FList.Count - 1 do
    Editor_OutputString(FList[I].Handle, PChar(Format('Emmet LiveStyle: %s', [Str + #13#10])), FLAG_OPEN_OUTPUT);
end;

end.
