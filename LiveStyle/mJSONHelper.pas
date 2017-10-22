unit mJSONHelper;

interface

uses
{$IF CompilerVersion > 22.9}
  System.SysUtils, Data.DBXJSON;
{$ELSE}
  SysUtils, DBXJSON;
{$IFEND}


type
  TJSONAncestorHelper = class helper for TJSONAncestor
  public
    { Public êÈåæ }
    function ToJSON: string;
  end;

implementation

{ TJSONAncestorHelper }

function TJSONAncestorHelper.ToJSON: string;
var
  LBytes: TBytes;
begin
  SetLength(LBytes, Length(ToString) * 6);
  SetLength(LBytes, ToBytes(LBytes, 0));
  result := TEncoding.Default.GetString(LBytes);
end;

end.
