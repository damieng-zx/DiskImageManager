{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit DIMComponents;

{$warn 5023 off : no warning about unused units}
interface

uses
  DiskMap, DIMUtils, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('DiskMap', @DiskMap.Register);
end;

initialization
  RegisterPackage('DIMComponents', @Register);
end.
