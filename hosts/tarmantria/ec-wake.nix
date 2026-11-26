{ pkgs, ... }:
let
  ssdt = pkgs.writeText "ec-wake.asl" ''
    DefinitionBlock ("", "SSDT", 2, "KRANE", "ECWAKE", 0x00000001)
    {
        External (\_SB.PWRB, DeviceObj)
        External (\_SB.PC00.LPCB.LID0, DeviceObj)

        Scope (\_SB.PWRB)
        {
            Name (_PRW, Package (0x02) { 0x02, 0x04 })
        }

        Scope (\_SB.PC00.LPCB.LID0)
        {
            Name (_PRW, Package (0x02) { 0x02, 0x04 })
        }
    }
  '';

  # The kernel only reads ACPI tables from an uncompressed cpio at the front of the initrd.
  acpiOverride =
    pkgs.runCommand "acpi-ec-wake"
      {
        nativeBuildInputs = [
          pkgs.acpica-tools
          pkgs.cpio
        ];
      }
      ''
        mkdir -p kernel/firmware/acpi
        iasl -p kernel/firmware/acpi/ec-wake ${ssdt}
        mkdir -p $out
        find kernel | cpio -H newc --create --owner 0:0 > $out/initrd
      '';
in
{
  boot.initrd.prepend = [ "${acpiOverride}/initrd" ];
}
