# Wake from suspend by power button or lid. The FX707VV4 firmware hides its embedded
# controller (EC0._STA returns 0, no ECDT) and routes every EC event, power button and lid
# included, through GPE 0x02 to its own _L02 handler. No device lists GPE 0x02 in a _PRW,
# so Linux disables it for s2idle and S3 alike and only the RTC alarm (GPE 0x72) could wake
# the machine: suspend entered fine, then nothing woke it (power LED blinking).
#
# This SSDT, loaded from the initrd (CONFIG_ACPI_TABLE_UPGRADE), gives PWRB and LID0 a _PRW
# on GPE 0x02, so the button driver arms it as a wake GPE. Any EC event can now wake the
# machine, battery and AC changes too.
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
  acpiOverride = pkgs.runCommand "acpi-ec-wake" { nativeBuildInputs = [ pkgs.acpica-tools pkgs.cpio ]; } ''
    mkdir -p kernel/firmware/acpi
    iasl -p kernel/firmware/acpi/ec-wake ${ssdt}
    mkdir -p $out
    find kernel | cpio -H newc --create --owner 0:0 > $out/initrd
  '';
in
{
  boot.initrd.prepend = [ "${acpiOverride}/initrd" ];
}
