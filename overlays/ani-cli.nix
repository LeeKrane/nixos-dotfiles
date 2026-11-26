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
