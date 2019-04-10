object PropForm: TPropForm
  Left = 0
  Top = 0
  BorderStyle = bsDialog
  Caption = 'LiveStyle'
  ClientHeight = 137
  ClientWidth = 257
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnClose = FormClose
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object PortLabel: TLabel
    Left = 8
    Top = 12
    Width = 46
    Height = 13
    Caption = #12509#12540#12488'(&P):'
  end
  object Bevel: TBevel
    Left = 0
    Top = 96
    Width = 257
    Height = 9
    Shape = bsTopLine
  end
  object PortSpinEdit: TSpinEditEx
    Left = 64
    Top = 8
    Width = 65
    Height = 22
    MaxLength = 5
    MaxValue = 65535
    MinValue = 1024
    NumbersOnly = True
    TabOrder = 2
    Value = 1024
  end
  object DebugCheckBox: TCheckBox
    Left = 8
    Top = 40
    Width = 241
    Height = 17
    Caption = #12487#12496#12483#12464'(&D)'
    TabOrder = 3
  end
  object SendUnsavedChangesCheckBox: TCheckBox
    Left = 8
    Top = 64
    Width = 241
    Height = 17
    Caption = #20877#35501#12415#36796#12415#26178#12395#22793#26356#12434#33258#21205#30340#12395#36865#20449'(&S)'
    TabOrder = 4
  end
  object OKButton: TButton
    Left = 80
    Top = 104
    Width = 81
    Height = 25
    Caption = 'OK'
    Default = True
    ModalResult = 1
    TabOrder = 0
  end
  object CancelButton: TButton
    Left = 168
    Top = 104
    Width = 81
    Height = 25
    Cancel = True
    Caption = #12461#12515#12531#12475#12523
    ModalResult = 2
    TabOrder = 1
  end
end
