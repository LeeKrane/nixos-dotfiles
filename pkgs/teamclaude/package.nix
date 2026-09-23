# teamclaude, the multi-account Claude proxy that ~/.claude's settings.json
# points ANTHROPIC_BASE_URL at (localhost:3456). Pinned to the release
# ~/.claude/SETUP.md names. The npm tarball has no dependencies, so it is
# installed as-is instead of through buildNpmPackage. To bump: set
# `version`, then take `hash` from
# `npm view @karpeleslab/teamclaude@<version> dist.integrity`.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  nodejs_22,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "teamclaude";
  version = "1.1.21";

  src = fetchurl {
    url = "https://registry.npmjs.org/@karpeleslab/teamclaude/-/teamclaude-${finalAttrs.version}.tgz";
    hash = "sha512-VvEZAh5elmzkidZV9fggNA7qsEb+7wmUZ3H32O+JJzJ3fqR7o+4jAxBehhG4VH9rsXoTEw0P9fofM+Wa+lG1hA==";
  };

  nativeBuildInputs = [ makeBinaryWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    dest=$out/lib/node_modules/@karpeleslab/teamclaude
    mkdir -p $dest
    cp -r package.json src $dest/

    # The store is read-only, so its self-updater could never succeed.
    # Disabling it also stops the daily registry check, the reason SETUP.md
    # sets "autoUpdate": false.
    makeWrapper ${lib.getExe nodejs_22} $out/bin/teamclaude \
      --add-flags $dest/src/index.js \
      --set TEAMCLAUDE_DISABLE_AUTOUPDATE 1

    runHook postInstall
  '';

  meta = {
    description = "Multi-account proxy for Claude Code that rotates Team/Enterprise seats on quota";
    homepage = "https://github.com/KarpelesLab/teamclaude";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "teamclaude";
  };
})
