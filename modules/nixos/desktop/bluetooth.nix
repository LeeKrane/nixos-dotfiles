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
  # prompt hits EOF. RequestConfirmation/RequestAuthorization see an empty
  # answer from scanf and cleanly reject (agent-helper.c falls through to
  # its "Passkey does not match"/"Pairing rejected" dbus-error branch).
  # RequestPinCode does not: on EOF its `ret` stays NULL but the code still
  # builds the reply with g_variant_new("(s)", NULL), a GLib critical since
  # that format needs a non-null string; the D-Bus reply is then missing or
  # malformed, so bluetoothd fails the pairing either way - nothing is
  # accepted. With capability=NoInputNoOutput, BlueZ never asks
  # RequestPasskey for SSP, so that path never triggers. There is
  # deliberately no `-p` pin file: a "* *" wildcard would hand every
  # legacy RequestPinCode the literal PIN `*`. Pairings bluetoothd
  # completes itself, e.g. Just Works started from ii, still succeed, and
  # AuthorizeService still accepts already-paired devices.
  #
  # startLimitIntervalSec = 0 disables systemd's start-rate limit for this
  # unit, so Restart = "always" keeps restarting bt-agent even if repeated
  # legacy PIN attempts crash it via the RequestPinCode critical above;
  # without it, enough crashes in quick succession would hit the default
  # start limit and leave the agent dead (and pairing refused) until a
  # manual restart.
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
