program IOTHealthMonitor;

uses
  System.StartUpCopy,
  FMX.Forms,
  untMain in 'untMain.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
