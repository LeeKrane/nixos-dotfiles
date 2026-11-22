{
  lib,
  stdenvNoCC,
  androidenv,
  jdk_headless,
  zip,
  writeShellApplication,
  apksigner,
}:
let
  # The Android SDK license is accepted for this package only, not in the flake's nixpkgs config.
  sdk =
    (androidenv.override { licenseAccepted = true; }).composeAndroidPackages {
      platformVersions = [ "35" ];
      buildToolsVersions = [ "35.0.0" ];
      includeEmulator = false;
      includeSystemImages = false;
    };
  root = "${sdk.androidsdk}/libexec/android-sdk";
  bt = "${root}/build-tools/35.0.0";

  # Unsigned, zip-aligned. Signing needs a key that lives outside the repo and the store, so
  # it is a separate step (`sign`, below).
  unsigned = stdenvNoCC.mkDerivation {
    pname = "ani-cli-launcher-unsigned";
    version = "1";
    src = lib.cleanSource ../../android/ani-cli-launcher;
    nativeBuildInputs = [
      jdk_headless
      zip
    ];
    buildPhase = ''
      runHook preBuild
      jar=${root}/platforms/android-35/android.jar
      mkdir -p out/classes
      ${bt}/aapt2 compile --dir res -o out/res.zip
      ${bt}/aapt2 link -I "$jar" --manifest AndroidManifest.xml --min-sdk-version 26 \
        --target-sdk-version 35 --version-code 1 --version-name 1 \
        -o out/base.apk out/res.zip
      javac --release 8 -Xlint:-options -cp "$jar" -d out/classes $(find src -name '*.java')
      ${bt}/d8 --release --min-api 26 --lib "$jar" --output out $(find out/classes -name '*.class')
      zip -qX -j out/base.apk out/classes.dex
      ${bt}/zipalign -P 16 -f 4 out/base.apk out/aligned.apk
      runHook postBuild
    '';
    installPhase = ''
      install -Dm644 out/aligned.apk $out/ani-cli-launcher-unsigned.apk
    '';
  };

  # sign <unsigned.apk> <signed.apk>: signs with a keystore kept in $XDG_DATA_HOME, created on
  # first use. Losing it means the phone must uninstall the app before an update installs.
  sign = writeShellApplication {
    name = "ani-cli-launcher-sign";
    runtimeInputs = [
      apksigner
      jdk_headless
    ];
    text = ''
      dir="''${ANI_CLI_LAUNCHER_KEYDIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/ani-cli-launcher}"
      ks="$dir/keystore.p12"
      pass="$dir/keystore.pass"
      if [ ! -f "$ks" ]; then
        echo "creating signing key in $dir (back this directory up)" >&2
        mkdir -p "$dir"
        chmod 700 "$dir"
        (umask 077; head -c 24 /dev/urandom | base64 > "$pass")
        keytool -genkeypair -keystore "$ks" -storetype PKCS12 -storepass:file "$pass" \
          -alias ani-cli-launcher -keyalg RSA -keysize 3072 -validity 36500 \
          -dname "CN=ani-cli-launcher"
        chmod 600 "$ks"
      fi
      apksigner sign --ks "$ks" --ks-pass "file:$pass" --out "$2" "$1"
      apksigner verify "$2"
    '';
  };
in
unsigned.overrideAttrs (_: {
  passthru = { inherit sign sdk; };
})
