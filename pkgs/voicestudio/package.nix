# VoiceStudio: local-first voice cloning, dubbing and transcription (Electron
# UI plus a Python backend it sets up and downloads models for at runtime).
# Wraps the upstream AppImage. To bump: set `version`, then take the hash from
# the release's SHA256SUMS.txt (`nix hash convert --to sri sha256:<hex>`).
{
  lib,
  appimageTools,
  fetchurl,
}:
let
  pname = "voicestudio";
  version = "0.5.7";

  src = fetchurl {
    url = "https://github.com/debpalash/VoiceStudio/releases/download/v${version}/VoiceStudio-${version}-linux-x64.AppImage";
    hash = "sha256-OaPgquI/KpXLKqv0ocpKG5wXkxsZVxF5rOAXmB42RwA=";
  };

  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    install -Dm444 ${contents}/VoiceStudio.desktop $out/share/applications/voicestudio.desktop
    substituteInPlace $out/share/applications/voicestudio.desktop \
      --replace-fail 'Exec=AppRun' 'Exec=voicestudio'
    cp -r ${contents}/usr/share/icons $out/share
  '';

  meta = {
    description = "Local-first voice cloning, dubbing, dictation and transcription studio";
    homepage = "https://github.com/debpalash/VoiceStudio";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "voicestudio";
  };
}
