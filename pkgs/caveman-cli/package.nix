# The npm tarball has no dependencies, so it is installed as-is instead of through
# buildNpmPackage.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  nodejs_22,
}:
let
  binaryRelease = "bin-v4.2.0";
  arch =
    {
      x86_64-linux = "amd64";
      aarch64-linux = "arm64";
    }
    .${stdenvNoCC.hostPlatform.system};
  # sha256 from the release's checksums.txt
  binaryHashes = {
    amd64 = {
      caveman-proxy = "sha256-FWdK99I+U6LKqZTf4CEIuM3oH5AQNbRQ9xO7fFwabZ8=";
      caveman-engine = "sha256-iERmg0WwlP9G7mA3qy6EU9/Je5efPpw6m1IMUJve+GA=";
      caveman-mcp = "sha256-JXmZL6qU8saPkaW1RK2Z+qd9h7HKh7PmvGNMqiH7jXM=";
      cavemem = "sha256-PF6viX+gHTXVTVYXXMG+voF4FFcfbTyu7HltsQ83xgc=";
      caveman-shrink = "sha256-hKtPaaGlqKhq8NSe79qQ4HropCXBbhHoiq/AE2DcmvU=";
    };
    arm64 = {
      caveman-proxy = "sha256-MSTvaHE2/ayPYisYYs3FU+YPQjy221HKLyZVCGxJHBU=";
      caveman-engine = "sha256-LhYXViAghj6Od+DL6oV5PZ04J9dHR1JrGgdta/oduEk=";
      caveman-mcp = "sha256-rBbiUsMbkSJBc+pXmS/I/E+h5KtcrMZnJ/QjqMBp2v4=";
      cavemem = "sha256-Z3uSEf6TyS7bF6fv44AMxqR8cguz7XeDWo6UoNhA6ak=";
      caveman-shrink = "sha256-V5XKjd29NTMLC9ZqdbpWkqIjONZIQacZzivVq9RX2MI=";
    };
  };
  goBinaries = lib.mapAttrs (
    name: hash:
    fetchurl {
      url = "https://github.com/JuliusBrussee/caveman/releases/download/${binaryRelease}/${name}_linux_${arch}";
      inherit hash;
    }
  ) binaryHashes.${arch};
in
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

    mkdir -p $out/bin
    ${lib.concatStrings (
      lib.mapAttrsToList (name: src: "install -Dm755 ${src} $out/bin/${name}\n") goBinaries
    )}

    for bin in caveman cave; do
      makeWrapper ${lib.getExe nodejs_22} $out/bin/$bin \
        --add-flags $dest/dist/index.js \
        --set CAVEMAN_TELEMETRY 0 \
        --prefix PATH : $out/bin
    done

    runHook postInstall
  '';

  meta = {
    description = "Caveman CLI: local context compression wrapper for coding agents";
    homepage = "https://github.com/JuliusBrussee/caveman";
    license = lib.licenses.mit;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    mainProgram = "caveman";
  };
})
