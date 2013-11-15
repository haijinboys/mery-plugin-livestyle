unit mProp;

interface

uses
{$IF CompilerVersion > 22.9}
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
{$ELSE}
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, ComCtrls,
{$IFEND}
  MeryCtrls, mDiff;

type
  TPropForm = class(TForm)
    ListView: TListView;
    Bevel: TBevel;
    OKButton: TButton;
    CancelButton: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ListViewClick(Sender: TObject);
    procedure ListViewData(Sender: TObject; Item: TListItem);
    procedure ListViewSelectItem(Sender: TObject; Item: TListItem;
      Selected: Boolean);
  private
    { Private éŒ¾ }
    procedure ReadIni;
    procedure UpdateStatus;
  public
    { Public éŒ¾ }
  end;

function Prop(AOwner: TComponent; var AIndex: NativeInt): Boolean;

var
  PropForm: TPropForm;
  FFontName: string;
  FFontSize: NativeInt;

implementation

{$R *.dfm}


uses
{$IF CompilerVersion > 22.9}
  System.Math, System.IniFiles,
{$ELSE}
  Math, IniFiles,
{$IFEND}
  mCommon;

function Prop(AOwner: TComponent; var AIndex: NativeInt): Boolean;
begin
  with TPropForm.Create(AOwner) do
    try
      with ListView do
      begin
        Items.Count := FPatches.Count;
        if Items.Count > 0 then
          ItemIndex := 0;
        Refresh;
      end;
      Result := ShowModal = mrOk;
      if Result then
        AIndex := ListView.ItemIndex;
    finally
      Release;
    end;
end;

procedure TPropForm.FormCreate(Sender: TObject);
begin
  if Win32MajorVersion < 6 then
    with Font do
    begin
      Name := 'Tahoma';
      Size := 8;
    end;
  ReadIni;
  with Font do
  begin
    ChangeScale(FFontSize, Size);
    Name := FFontName;
    Size := FFontSize;
  end;
end;

procedure TPropForm.FormDestroy(Sender: TObject);
begin
  //
end;

procedure TPropForm.FormShow(Sender: TObject);
begin
  //
end;

procedure TPropForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  //
end;

procedure TPropForm.ListViewClick(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TPropForm.ListViewData(Sender: TObject; Item: TListItem);
begin
  if InRange(Item.Index, 0, FPatches.Count - 1) then
  begin
    Item.Caption := FPatches[Item.Index].FileName;
    Item.SubItems.Add(FPatches[Item.Index].Selectors);
    Item.SubItems.Add(FPatches[Item.Index].Name);
  end;
end;

procedure TPropForm.ListViewSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  if Selected then
    UpdateStatus;
end;

procedure TPropForm.ReadIni;
var
  S: string;
begin
  if not GetIniFileName(S) then
    Exit;
  with TMemIniFile.Create(S, TEncoding.UTF8) do
    try
      FFontName := ReadString('MainForm', 'FontName', Font.Name);
      FFontSize := ReadInteger('MainForm', 'FontSize', Font.Size);
    finally
      Free;
    end;
end;

procedure TPropForm.UpdateStatus;
begin
  with ListView do
    OKButton.Enabled := (Items.Count > 0) and (ItemIndex >= 0);
end;

end.
