# The npm tarball has no dependencies, so it is installed as-is instead of through
# buildNpmPackage.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  nodejs_22,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "caveman-cli";
  version = "4.2.0";

  src = fetchurl {
    url = "https://registry.npmjs.org/@caveman-ai/cli/-/cli-${finalAttrs.version}.tgz";
    hash = "sha512-hs0q6TvltD/p0w4pkpchmrxD+TUIh6o3s8+Ucf7FWL8zDLsBKknH7r+iowGg5vEolSdrDKbwDfbCEZzDnJaFUw==";
  };

  nativeBuildInputs = [ makeBinaryWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/lib/node_modules/@caveman-ai/cli
    mkdir -p $dest
    cp -r package.json dist $dest/

    for bin in caveman cave; do
      makeWrapper ${lib.getExe nodejs_22} $out/bin/$bin \
        --add-flags $dest/dist/index.js \
        --set CAVEMAN_TELEMETRY 0
    done

    runHook postInstall
  '';

  meta = {
    description = "Caveman CLI: local context compression wrapper for coding agents";
    homepage = "https://github.com/JuliusBrussee/caveman";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "caveman";
  };
})
