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

    # The theme hardcodes an FHS path that plymouth's module doesn't rewrite.
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
