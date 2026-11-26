{ pkgs, ... }:
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.General.Experimental = true;
  };

  systemd.services.bluetooth-agent = {
    description = "BlueZ pairing agent (NoInputNoOutput)";
    bindsTo = [ "bluetooth.service" ];
    after = [ "bluetooth.service" ];
    partOf = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.service" ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      ExecStart = "${pkgs.bluez-tools}/bin/bt-agent --capability=NoInputNoOutput";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
