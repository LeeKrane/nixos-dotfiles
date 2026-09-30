{ pkgs, ... }:
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # Needed by headset/battery profiles the ii widgets poll.
    settings.General.Experimental = true;
  };

  # ii registers no BlueZ agent, so bluetoothd refuses pairing with
  # "Authentication attempt without agent" until one exists. This service
  # supplies it: bt-agent runs as root, the default agent, bound to
  # bluetooth.service so it returns whenever bluetoothd restarts. Without
  # `-d` it prompts on stdin, which systemd points at /dev/null: every
  # prompt hits EOF, so RequestPinCode replies with a NULL pin (rejected)
  # and RequestConfirmation/RequestAuthorization see an empty answer and
  # reject too. With capability=NoInputNoOutput, BlueZ never asks
  # RequestPasskey for SSP, so that EOF path never triggers. There is
  # deliberately no `-p` pin file: a "* *" wildcard would hand every
  # legacy RequestPinCode the literal PIN `*`. Pairings bluetoothd
  # completes itself, e.g. Just Works started from ii, still succeed, and
  # AuthorizeService still accepts already-paired devices.
  systemd.services.bluetooth-agent = {
    description = "BlueZ pairing agent (NoInputNoOutput)";
    bindsTo = [ "bluetooth.service" ];
    after = [ "bluetooth.service" ];
    partOf = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.bluez-tools}/bin/bt-agent --capability=NoInputNoOutput";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
