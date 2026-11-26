# Sound BlasterX G6 mic fix.
{ config, pkgs, ... }:
let
  acpPaths = "${config.services.pipewire.package}/share/alsa-card-profile/mixer/paths";

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
