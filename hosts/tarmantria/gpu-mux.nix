# The FX707VV4's display MUX, through the kernel's asus-armoury firmware attribute. Hybrid (1)
# wires the panel to the Intel iGPU and makes Hyprland composite there, so a game rendered on
# the dGPU is copied across PCIe every frame, twice for HDMI-A-1, which hangs off the dGPU in
# both modes. dgpu (0) wires the panel to the NVIDIA dGPU too: no copies, but the dGPU never
# sleeps, which costs battery. The firmware applies a new mode only at the next boot.
#
# gpu-mux-auto sets the mode for the next boot from the power state: dgpu on external power,
# hybrid on battery. It runs at boot and on every plug or unplug, so a manual `gpu-mux` choice
# lasts only until the power state next changes.
{ pkgs, ... }:
let
  attr = "/sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value";

  gpuMux = pkgs.writeShellApplication {
    name = "gpu-mux";
    text = ''
      name() {
        case "$1" in
          0) echo dgpu ;;
          1) echo hybrid ;;
          *) echo "unknown ($1)" ;;
        esac
      }
      case "''${1:-}" in
        "")
          # The dGPU is the boot VGA device only while the firmware runs in dgpu mode.
          active=1
          [ "$(cat /sys/bus/pci/devices/0000:01:00.0/boot_vga)" = 1 ] && active=0
          echo "active: $(name "$active"), next boot: $(name "$(cat ${attr})")"
          ;;
        dgpu) echo 0 | sudo tee ${attr} >/dev/null && echo "MUX set to dgpu. Reboot to apply." ;;
        hybrid) echo 1 | sudo tee ${attr} >/dev/null && echo "MUX set to hybrid. Reboot to apply." ;;
        *)
          echo "usage: gpu-mux [dgpu|hybrid]" >&2
          exit 1
          ;;
      esac
    '';
  };

  gpuMuxAuto = pkgs.writeShellScript "gpu-mux-auto" ''
    # External power is the barrel adapter (Mains) or a USB-C PD source.
    ac=0
    for s in /sys/class/power_supply/*; do
      case "$(${pkgs.coreutils}/bin/cat "$s/type")" in
        Mains | USB) [ "$(${pkgs.coreutils}/bin/cat "$s/online" 2>/dev/null)" = 1 ] && ac=1 ;;
      esac
    done
    want=1
    [ "$ac" = 1 ] && want=0
    # Write only on a change, to leave the firmware setting alone otherwise.
    if [ "$(${pkgs.coreutils}/bin/cat ${attr})" != "$want" ]; then
      echo "$want" > ${attr}
      echo "MUX for next boot: $want (external power: $ac)"
    fi
  '';
in
{
  environment.systemPackages = [ gpuMux ];

  systemd.services.gpu-mux-auto = {
    description = "Set the display MUX for the next boot from the power state";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = gpuMuxAuto;
    };
  };

  # SYSTEMD_WANTS fires only on add, so start the unit by hand on change events too. Not on
  # battery events: BAT0 sends one with every capacity update.
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", ACTION=="change", ATTR{type}!="Battery", RUN+="${pkgs.systemd}/bin/systemctl start --no-block gpu-mux-auto.service"
  '';
}
