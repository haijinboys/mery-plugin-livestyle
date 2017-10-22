{== D6DLLSynchronizer =================================================}
{: This unit handles the D6 synchronize problem in DLLs
@author Dr. Peter Below
@desc   Version 1.0 created 3 November 2001<BR>
        Current revision 1.0<BR>
        Last modified       3 November 2001<P>
Usage: <BR>
Just add this unit to the DLL project, make sure you do not modify
the WakeMainThread global event yourself elsewhere. }
{======================================================================}
Unit D6DLLSynchronizer;

Interface

Implementation
Uses Windows, Messages, classes;

Type
  TSyncHelper = Class
  Private
    wnd: HWND;
    Procedure MsgProc( Var msg: TMessage );
    Procedure Wakeup( sender: TObject );
  Public
    Constructor Create;
    Destructor Destroy; override;
  End;

Var
  helper: TSyncHelper = nil;

{ TSyncHelper }

Constructor TSyncHelper.Create;
Begin
  inherited;
  wnd:= AllocateHWnd( msgproc );
  WakeMainThread := Wakeup;
End;

Destructor TSyncHelper.Destroy;
Begin
  WakeMainThread := nil;
  DeallocateHWnd( wnd );
  inherited;
End;

Procedure TSyncHelper.MsgProc(Var msg: TMessage);
Begin
  If msg.Msg = WM_USER Then
    CheckSynchronize
  Else
    msg.result := DefWindowProc( wnd, msg.msg, msg.WParam, msg.LParam );
End;

Procedure TSyncHelper.Wakeup(sender: TObject);
Begin
  PostMessage( wnd, WM_USER, 0, 0 );
End;

Initialization
  helper:= TSyncHelper.Create;
Finalization
  helper.free;
End.
