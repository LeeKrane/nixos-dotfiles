{ stdenvNoCC, lib }:

stdenvNoCC.mkDerivation {
  pname = "plymouth-lone";
  version = "0-unstable";

  src = ./theme;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/plymouth/themes/lone
    cp -r . $out/share/plymouth/themes/lone/

    # plymouth's module doesn't rewrite this theme's hardcoded FHS path,
    # so substitute it here at build time.
    substituteInPlace $out/share/plymouth/themes/lone/lone.plymouth \
      --replace-fail /usr/share/plymouth/themes/lone $out/share/plymouth/themes/lone

    runHook postInstall
  '';

  meta = with lib; {
    description = "Lone particle-animation Plymouth boot theme (Aditya Shakya / adi1090x)";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
  };
}
