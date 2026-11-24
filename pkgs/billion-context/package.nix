# billion-context (`bili`), a local compression proxy/launcher for coding agents, run here as
# `bili claude` in front of the teamclaude proxy (modules/nixos/common/claude.nix). Pinned to
# the audited npm release. The tarball is fully bundled (dependencies inlined in dist/), so it
# is installed as-is instead of through buildNpmPackage. To bump: re-audit the new tarball,
# set `version`, then take `hash` from `npm view billion-context@<version> dist.integrity`.
#
# The wrapper hardens the package with --set (not --set-default), so no user env can undo it:
# - ACP_AUTO_UPDATE, BILI_ADVISORY_CHECK, BILI_RELEASE_NOTES_CHECK: no self-update or remote
#   notice channel. The advisory channel can force-install even with autoUpdate=false, and the
#   store is read-only anyway.
# - BILI_SQLITE_AUTO_DOWNLOAD: never fetch a SQLite binary, node:sqlite (node >= 22.13) is used.
# - BILI_MITM, BILI_UPSTREAM_PROXY_MODE: no HTTPS interception, no outbound proxy, direct only.
# - BILI_SESSION_GC: prune old session data. BILI_CACHE_KEEPALIVE: no synthetic cache pings.
{
  lib,
  stdenvNoCC,
  fetchurl,
  makeBinaryWrapper,
  nodejs_22,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "billion-context";
  version = "0.1.216";

  src = fetchurl {
    url = "https://registry.npmjs.org/billion-context/-/billion-context-${finalAttrs.version}.tgz";
    hash = "sha512-98Q5eSqk0LyemCJ45OrYmZvEd0qpzBjLokthZlQ4yA7yvgUlzuM7fp6iq9dPAJ4N4vaplnvZeld0JxM4S7Ti1A==";
  };

  nativeBuildInputs = [ makeBinaryWrapper ];

  dontBuild = true;

  # Copies everything: dist only mentions docs/ in user-facing messages, but the
  # tarball is small and the wrapper does not depend on that staying true.
  installPhase = ''
    runHook preInstall

    dest=$out/lib/node_modules/billion-context
    mkdir -p $dest
    cp -r . $dest/

    for bin in bili bili-proxy; do
      makeWrapper ${lib.getExe nodejs_22} $out/bin/$bin \
        --add-flags $dest/dist/index.js \
        --set ACP_AUTO_UPDATE 0 \
        --set BILI_ADVISORY_CHECK 0 \
        --set BILI_RELEASE_NOTES_CHECK 0 \
        --set BILI_SQLITE_AUTO_DOWNLOAD 0 \
        --set BILI_MITM 0 \
        --set BILI_UPSTREAM_PROXY_MODE direct \
        --set BILI_SESSION_GC 1 \
        --set BILI_CACHE_KEEPALIVE 0
    done

    runHook postInstall
  '';

  meta = {
    description = "Context-compression proxy and launcher for coding agents (bili)";
    homepage = "https://www.npmjs.com/package/billion-context";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "bili";
  };
})
