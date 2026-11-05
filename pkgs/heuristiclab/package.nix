# HeuristicLab: .NET Framework 4.x (WinForms) optimization environment, run
# under Wine. wine-mono crashes on it and plain Mono breaks its plugin loading,
# so the launcher keeps a dedicated prefix with Microsoft's .NET 4.8 installed
# by winetricks on first start (needs network, a few minutes). The release is
# copied into the prefix so the app sees a normal, writable install folder.
# To bump: set `version` and `hash` from the GitHub release zip.
{
  lib,
  stdenvNoCC,
  fetchurl,
  unzip,
  icoutils,
  writeShellApplication,
  makeDesktopItem,
  copyDesktopItems,
  wineWow64Packages,
  winetricks,
  libnotify,
  coreutils,
}:
let
  pname = "heuristiclab";
  version = "3.3.16";

  release = stdenvNoCC.mkDerivation {
    pname = "${pname}-release";
    inherit version;
    src = fetchurl {
      url = "https://github.com/heal-research/HeuristicLab/releases/download/v${version}/HeuristicLab_${version}.zip";
      hash = "sha256-CuA9hsmGVBJEOSRgASGLzcFOuKgHa6rSoMYIiTZnBrg=";
    };
    nativeBuildInputs = [
      unzip
      icoutils
    ];
    unpackPhase = "unzip -q $src -d app";
    installPhase = ''
      mkdir -p $out
      cp -r app $out/app
      wrestool -x -t14 "app/HeuristicLab 3.3.exe" -o hl.ico
      for size in 16 32 48 64 128; do
        dir=$out/share/icons/hicolor/''${size}x''${size}/apps
        mkdir -p $dir
        icotool -x -w $size hl.ico -o $dir/heuristiclab.png
      done
    '';
  };

  launcher = writeShellApplication {
    name = "heuristiclab";
    runtimeInputs = [
      wineWow64Packages.stable
      winetricks
      libnotify
      coreutils
    ];
    text = ''
      export WINEPREFIX="''${HEURISTICLAB_PREFIX:-''${XDG_DATA_HOME:-$HOME/.local/share}/heuristiclab/prefix}"
      export WINEDEBUG="''${WINEDEBUG:--all}"
      install_dir="$WINEPREFIX/drive_c/HeuristicLab"

      if [ ! -f "$WINEPREFIX/.dotnet48-done" ]; then
        notify-send -a HeuristicLab "HeuristicLab" "First start: installing .NET Framework 4.8 into the Wine prefix. This takes a few minutes." || true
        mkdir -p "$WINEPREFIX"
        WINEDLLOVERRIDES="mscoree=" wineboot -i
        winetricks -q --unattended dotnet48
        wineserver -w
        touch "$WINEPREFIX/.dotnet48-done"
      fi

      if [ "$(cat "$install_dir/.nix-release" 2>/dev/null)" != "${release}" ]; then
        rm -rf "$install_dir"
        cp -r ${release}/app "$install_dir"
        chmod -R u+w "$install_dir"
        echo "${release}" > "$install_dir/.nix-release"
      fi

      cd "$install_dir"
      exec wine "HeuristicLab 3.3.exe" "$@"
    '';
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;
  dontUnpack = true;
  nativeBuildInputs = [ copyDesktopItems ];

  desktopItems = [
    (makeDesktopItem {
      name = "heuristiclab";
      desktopName = "HeuristicLab";
      comment = "Environment for heuristic and evolutionary optimization";
      exec = "heuristiclab";
      icon = "heuristiclab";
      categories = [
        "Science"
        "Education"
      ];
      startupWMClass = "heuristiclab 3.3.exe";
    })
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    ln -s ${lib.getExe launcher} $out/bin/heuristiclab
    cp -r ${release}/share $out/share
    chmod -R u+w $out/share
    runHook postInstall
  '';

  meta = {
    description = "Environment for heuristic and evolutionary optimization (run under Wine)";
    homepage = "https://dev.heuristiclab.com/";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryBytecode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "heuristiclab";
  };
}
