program DiskImageManager;

{$MODE Delphi}

uses
  Forms, Interfaces,
  Main in 'Main.pas' {frmMain};

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'Disk Image Manager';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
