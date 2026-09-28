# Sound BlasterX G6 mic fix, tarmantria only (the G6 is only used here).
{ config, pkgs, ... }:
let
  acpPaths = "${config.services.pipewire.package}/share/alsa-card-profile/mixer/paths";

  # Stock ACP mic path only knows the "Mic" and "Mic-In/Mic Array" items of
  # "PCM Capture Source". The G6 names its mic input "External Mic", so ACP
  # exposes only a Line In port and forces the capture source to Line In.
  # ACP checks /etc/alsa-card-profile/mixer/paths before its own data dir,
  # per file, so this copy shadows only analog-input-mic.conf. Relative
  # .include lines resolve against the including file, so point them back at
  # the stock directory.
  micPath = pkgs.runCommand "analog-input-mic.conf" { } ''
    sed \
      -e 's|^\.include \(.*\)$|.include ${acpPaths}/\1|' \
      -e '/^\[Option PCM Capture Source:Mic-In\/Mic Array\]$/i [Option PCM Capture Source:External Mic]\nname = analog-input-microphone\nrequired-any = any\n' \
      ${acpPaths}/analog-input-mic.conf > $out
    grep -q '^\[Option PCM Capture Source:External Mic\]$' $out
  '';
in
{
  environment.etc."alsa-card-profile/mixer/paths/analog-input-mic.conf".source = micPath;
}
