# Boot menu entry for the portable Windows 11 install on a Samsung T7 USB SSD.
{ pkgs, ... }:
{
  # systemd-boot can't chainload from another disk, and
  # the shell's fsN/HDn handles shift with port and other attached drives, so a dedicated EDK2
  # shell runs startup.nsh (searched next to shell.efi) and boots whichever filesystem carries
  # the marker file put on the T7's ESP.
  boot.loader.systemd-boot = {
    extraFiles = {
      "efi/t7-win11/shell.efi" = "${pkgs.edk2-uefi-shell}/shell.efi";
      "efi/t7-win11/startup.nsh" = pkgs.writeText "startup.nsh" ''
        @echo -off
        for %i in fs0 fs1 fs2 fs3 fs4 fs5 fs6 fs7 fs8 fs9 fs10 fs11 fs12 fs13 fs14 fs15
          if exist %i:\EFI\t7-win11-portable.marker then
            %i:\EFI\Microsoft\Boot\bootmgfw.efi
            exit
          endif
        endfor
        echo "Windows 11 Portable (T7) not found. Is the T7 plugged in?"
        pause
        exit
      '';
    };
    extraEntries."t7-win11.conf" = ''
      title Windows 11 Portable (T7)
      efi /efi/t7-win11/shell.efi
      options -nointerrupt -nomap -noversion -delay 0
    '';
  };
}
