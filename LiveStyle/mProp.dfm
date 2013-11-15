object PropForm: TPropForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = #12497#12483#12481#12398#36969#29992
  ClientHeight = 297
  ClientWidth = 449
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object Bevel: TBevel
    Left = 0
    Top = 256
    Width = 449
    Height = 9
    Shape = bsTopLine
  end
  object ListView: TListView
    Left = 8
    Top = 8
    Width = 433
    Height = 241
    Columns = <
      item
        Caption = #12501#12449#12452#12523#21517
        Width = 160
      end
      item
        Caption = #12475#12524#12463#12479
        Width = 80
      end
      item
        Caption = #12477#12540#12473
        Width = 160
      end>
    ColumnClick = False
    HideSelection = False
    OwnerData = True
    ReadOnly = True
    RowSelect = True
    TabOrder = 2
    ViewStyle = vsReport
    OnClick = ListViewClick
    OnData = ListViewData
    OnSelectItem = ListViewSelectItem
  end
  object OKButton: TButton
    Left = 272
    Top = 264
    Width = 81
    Height = 25
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 0
  end
  object CancelButton: TButton
    Left = 360
    Top = 264
    Width = 81
    Height = 25
    Cancel = True
    Caption = #12461#12515#12531#12475#12523
    ModalResult = 2
    TabOrder = 1
  end
end
