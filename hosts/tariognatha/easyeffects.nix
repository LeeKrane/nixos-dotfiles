# Mic chain for the Razer Seiren V2 Pro (replaces Vesktop's noise suppression and input
# sensitivity): high-pass, DeepFilterNet, RNNoise voice detection as a speech gate, level gate,
# compressor, EQ, limiter. Tuned in the EasyEffects GUI, then exported here.
# EasyEffects itself is started by ii's hyprland/execs.lua on every host; this only ships the
# preset and an autoload entry that applies it whenever the Seiren is the input device.
# The preset is a read-only store symlink: to retune, change it in the GUI, "Save as" a new
# name, and copy that file over easyeffects/RazorSeirenV2Pro.json.
{ lib, pkgs, ... }:
let
  preset = "RazorSeirenV2Pro";
  # EasyEffects names autoload files <PipeWire node name>:<route description>.json, the
  # description of the device's active route (analog-input-mic here), not its name.
  node = "alsa_input.usb-Razer_Inc_Razer_Seiren_V2_Pro_UC2410L04200310-00.mono-fallback";
  route = "Microphone";
in
{
  # DeepFilterNet works in its own thread, which EasyEffects starts at the default priority. Under
  # full CPU load (CS2 shader compiles) it falls behind, and the queued audio never drains: the
  # mic stays about a second late until EasyEffects restarts. Every EasyEffects thread inherits
  # this nice value, the same one PipeWire runs at. Needs the nice limit in default.nix; without
  # it, nice prints a warning and starts EasyEffects at the default priority.
  home.packages = [
    (lib.hiPrio (
      pkgs.writeShellScriptBin "easyeffects" ''exec nice -n -11 ${pkgs.easyeffects}/bin/easyeffects "$@"''
    ))
  ];

  xdg.dataFile = {
    "easyeffects/input/${preset}.json".source = ./easyeffects/${preset}.json;
    "easyeffects/autoload/input/${node}:${route}.json".text = builtins.toJSON {
      device = node;
      device-description = "Razer Seiren V2 Pro Mono";
      device-profile = route;
      preset-name = preset;
    };
  };
}
