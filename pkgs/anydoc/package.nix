# Firecrawl's anydoc CLI: converts office documents, EPUB, CSV and PDF to
# Markdown. The npm package is a JS wrapper around a prebuilt napi-rs addon
# shipped as a per-platform package; the addon is copied next to index.js,
# which loads it from there before trying node_modules. To bump: set
# `version`, then take each hash from
# `npm view @firecrawl/anydoc[-linux-x64-gnu]@<version> dist.integrity`.
{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  nodejs_22,
}:
let
  native =
    {
      x86_64-linux = {
        target = "linux-x64-gnu";
        hash = "sha512-yfvx+iGo2CvZH0TB9MeyNjkrd5/psNFEuxkl2Jah/VNFesPRASqjjCkDRY7tKw7fPij1u/UyFVxI6bsu6Iow9Q==";
      };
      aarch64-linux = {
        target = "linux-arm64-gnu";
        hash = "sha512-gRrrjluTfQCjOO6wBefEP1QumYlUcGWKP7secVIO+ly8U/+DDQ70bOHW2lOGu19hA/23j7bc7bb3oLPAaBY82A==";
      };
    }
    .${stdenvNoCC.hostPlatform.system}
      or (throw "anydoc: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "anydoc";
  version = "0.2.4";

  src = fetchurl {
    url = "https://registry.npmjs.org/@firecrawl/anydoc/-/anydoc-${finalAttrs.version}.tgz";
    hash = "sha512-rfJxa5L+nhoqR5yodcRZoGDLaSfxMTpBuhVj1gSacfW4ZGjBt4cjfErXwaKjPYrpWRTPIBye2sh36UhqgOP1Og==";
  };

  addon = fetchurl {
    url = "https://registry.npmjs.org/@firecrawl/anydoc-${native.target}/-/anydoc-${native.target}-${finalAttrs.version}.tgz";
    inherit (native) hash;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeBinaryWrapper
  ];

  # libgcc_s for the addon
  buildInputs = [ stdenv.cc.cc.lib ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/lib/node_modules/@firecrawl/anydoc
    mkdir -p $dest
    cp -r *.js *.d.ts package.json $dest/
    tar xzf $addon --strip-components=1 -C $dest package/anydoc.${native.target}.node

    makeWrapper ${lib.getExe nodejs_22} $out/bin/anydoc \
      --add-flags $dest/cli.js

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    printf 'a,b\n1,2\n' | $out/bin/anydoc - --format csv | grep -q '| a | b |'
    runHook postInstallCheck
  '';

  meta = {
    description = "Convert Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV and PDF files to Markdown";
    homepage = "https://github.com/firecrawl/anydoc";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "anydoc";
  };
})
