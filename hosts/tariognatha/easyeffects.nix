# Mic chain for the Razer Seiren V2 Pro: high-pass, RNNoise voice detection as a speech gate,
# level gate, compressor, EQ, limiter.
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
  # Under full CPU load (shader compiles) EasyEffects' worker threads fall behind at the default
  # priority. Every EasyEffects thread inherits this nice value, the same one PipeWire runs at.
  # Needs the nice limit in default.nix; without it nice warns and EasyEffects runs at default priority.
  home.packages = [
    (lib.hiPrio (
      pkgs.writeShellScriptBin "easyeffects" ''exec nice -n -11 ${pkgs.easyeffects}/bin/easyeffects "$@"''
    ))
  ];

  # EasyEffects rewrites easyeffectsrc itself, so set single keys instead of owning the file.
  # processAllOutputs: playback skips EasyEffects (it has no output effects), so a CPU-starved
  # EasyEffects can't crackle game or music audio. listenToMic: monitoring the mic joins the mic
  # and Bluetooth graphs; the mic then drives the A2DP sink, which plays silence.
  home.activation.easyeffectsSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rc="$HOME/.config/easyeffects/db/easyeffectsrc"
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file "$rc" --group EffectsPipelines --key processAllOutputs false
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file "$rc" --group StreamInputs --key listenToMic false
  '';

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
