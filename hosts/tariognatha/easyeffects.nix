# Mic chain for the Razer Seiren V2 Pro (replaces Vesktop's noise suppression and input
# sensitivity): high-pass, RNNoise voice detection as a speech gate, level gate, compressor, EQ,
# limiter. DeepFilterNet was dropped: under game load it fell behind and delayed the mic.
# Tuned in the EasyEffects GUI, then exported here.
# The preset is a read-only store symlink: to retune, change it in the GUI, "Save as" a new
# name, and copy that file over easyeffects/RazorSeirenV2Pro.json.
{ lib, pkgs, ... }:
let
  preset = "RazorSeirenV2Pro";
  node = "alsa_input.usb-Razer_Inc_Razer_Seiren_V2_Pro_UC2410L04200310-00.mono-fallback";
  route = "Microphone";
in
{
  home.packages = [
    (lib.hiPrio (
      pkgs.writeShellScriptBin "easyeffects" ''exec nice -n -11 ${pkgs.easyeffects}/bin/easyeffects "$@"''
    ))
  ];

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
