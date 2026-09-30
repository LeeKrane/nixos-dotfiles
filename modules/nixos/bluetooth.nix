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
  # supplies it: bt-agent runs as root and is set as the default agent, bound
  # to bluetooth.service so it comes back whenever bluetoothd restarts.
  # Under systemd its stdin is /dev/null, so it rejects every PIN, passkey,
  # confirmation and authorization request it is asked about. That is
  # deliberate: there is no `-p` pin file, because a "* *" wildcard entry
  # would hand every legacy RequestPinCode the literal PIN `*` and let an
  # unprompted remote device bond. Pairings bluetoothd completes on its own,
  # such as a Just Works pairing started from ii, still succeed, and
  # AuthorizeService still accepts profiles from devices already paired.
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
