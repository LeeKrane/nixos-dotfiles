{ pkgs, ... }:
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # Needed by headset/battery profiles the ii widgets poll.
    settings.General.Experimental = true;
  };

  # ii's sidebar registers no BlueZ agent, so bluetoothd rejects pairing with
  # "Authentication attempt without agent" the moment a PIN/passkey or a service
  # authorization is needed. A NoInputNoOutput agent in every session answers those
  # requests automatically (auto-accept, no PIN prompt), which is enough for the headset/
  # controller pairing ii's UI drives. Not always-pairable/discoverable: those stay off,
  # this only supplies the agent bluetoothd already expects to find.
  systemd.user.services.bluetooth-agent = {
    description = "BlueZ pairing agent (NoInputNoOutput)";
    partOf = [ "graphical-session.target" ];
    wantedBy = [ "graphical-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.bluez-tools}/bin/bt-agent --capability=NoInputNoOutput";
      Restart = "on-failure";
    };
  };
}
