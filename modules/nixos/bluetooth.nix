{ pkgs, ... }:
let
  # bt-agent's pin file: "<device> <pin>" per line, "*" as either field is a
  # wildcard (src/lib/agent-helper.c: _find_device_pin falls back to the "*"
  # key, and both RequestConfirmation and RequestPinCode/RequestPasskey treat
  # a "*" value as matching any passkey/pincode without comparing it). "* *"
  # therefore means: any device, any PIN/passkey, always accept.
  btAgentPins = pkgs.writeText "bt-agent-pins" "* *\n";
in
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # Needed by headset/battery profiles the ii widgets poll.
    settings.General.Experimental = true;
  };

  # ii's sidebar registers no BlueZ agent, so bluetoothd rejects pairing with
  # "Authentication attempt without agent" the moment a PIN/passkey or a service
  # authorization is needed. A NoInputNoOutput agent answers those requests, but
  # bt-agent (src/lib/agent-helper.c) only auto-accepts when it can find a PIN
  # for the device in its `-p` file: without one, RequestConfirmation and
  # RequestPinCode fall through to an interactive stdin prompt that immediately
  # hits EOF (stdin is /dev/null under systemd) and rejects the request, or
  # returns a NULL pin code. `-p <btAgentPins>`, with its "* *" wildcard entry,
  # makes bt-agent find a match for every device and accept without ever
  # touching stdin, so the daemonizing `-d` flag (which forks, closes stdio and
  # just silences the same console prompts) buys nothing here and is skipped.
  # Runs as a system service (root), not per user session, so it registers
  # itself as the default agent for everyone and can bind to bluetooth.service:
  # BindsTo/PartOf/After plus Restart=always make it come back with bluetoothd
  # whenever that restarts (or exits 0 on a Release), instead of silently
  # disappearing until the next login. Not always-pairable/discoverable: those
  # stay off, this only supplies the agent bluetoothd already expects to find.
  systemd.services.bluetooth-agent = {
    description = "BlueZ pairing agent (NoInputNoOutput, auto-accept)";
    bindsTo = [ "bluetooth.service" ];
    after = [ "bluetooth.service" ];
    partOf = [ "bluetooth.service" ];
    wantedBy = [ "bluetooth.service" ];
    serviceConfig = {
      ExecStart = "${pkgs.bluez-tools}/bin/bt-agent --capability=NoInputNoOutput -p ${btAgentPins}";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
