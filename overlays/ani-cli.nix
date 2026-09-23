# nixpkgs ships ani-cli 5.0, whose anidb.app provider is down (503). Master (5.1.4) moved to
# hianime.at. There is no v5.1.4 tag, so pin the master commit. Drop once nixpkgs has >= 5.1.4.
_final: prev: {
  ani-cli = prev.ani-cli.overrideAttrs (_old: {
    version = "5.1.4-unstable-2026-09-16";
    src = prev.fetchFromGitHub {
      owner = "pystardust";
      repo = "ani-cli";
      rev = "a55a50985923da9b4360ffe341f92bd934b86515";
      hash = "sha256-iO0AY3E2MkAimdc/uEaMIIIWawUKbv1ZLTAAbJkyxXs=";
    };
  });
}
