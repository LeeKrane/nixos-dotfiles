# The FX707VV4's display MUX, through the kernel's asus-armoury firmware attribute. Hybrid (1)
# wires the panel to the Intel iGPU and makes Hyprland composite there, so a game rendered on
# the dGPU is copied across PCIe every frame, twice for HDMI-A-1, which hangs off the dGPU in
# both modes. dgpu (0) wires the panel to the NVIDIA dGPU too: no copies, but the dGPU never
# sleeps, which costs battery. The firmware applies a new mode only at the next boot.
#
# Reading the attribute returns the active mode, not the one written for the next boot; the
# firmware only flags that a change is waiting (attributes/pending_reboot). So every write also
# records its value in /run/gpu-mux/next, which a reboot clears along with the pending change.
#
# gpu-mux-auto sets the mode for the next boot from the power state: dgpu on external power,
# hybrid on battery. It runs at boot and on every plug or unplug, so a manual `gpu-mux` choice
# lasts only until the power state next changes.
{ pkgs, ... }:
let
  attr = "/sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value";
  next = "/run/gpu-mux/next";

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
      set_mode() {
        echo "$1" | sudo tee ${attr} ${next} >/dev/null
        echo "MUX set to $(name "$1"). Reboot to apply."
      }
      case "''${1:-}" in
        "")
          active=$(cat ${attr})
          upcoming=$active
          [ -f ${next} ] && upcoming=$(cat ${next})
          echo "active: $(name "$active"), next boot: $(name "$upcoming")"
          ;;
        dgpu) set_mode 0 ;;
        hybrid) set_mode 1 ;;
        *)
          echo "usage: gpu-mux [dgpu|hybrid]" >&2
          exit 1
          ;;
      esac
    '';
  };

  gpuMuxAuto = pkgs.writeShellScript "gpu-mux-auto" ''
    PATH=${pkgs.coreutils}/bin
    # External power is the barrel adapter (Mains) or a USB-C PD source.
    ac=0
    for s in /sys/class/power_supply/*; do
      case "$(cat "$s/type")" in
        Mains | USB) [ "$(cat "$s/online" 2>/dev/null)" = 1 ] && ac=1 ;;
      esac
    done
    want=1
    [ "$ac" = 1 ] && want=0
    # Without a write since boot, the next boot keeps the active mode.
    upcoming=$(cat ${attr})
    [ -f ${next} ] && upcoming=$(cat ${next})
    # Write only on a change, to leave the firmware setting alone otherwise.
    if [ "$upcoming" != "$want" ]; then
      echo "$want" | tee ${attr} ${next} >/dev/null
      echo "MUX for next boot: $want (external power: $ac)"
    fi
  '';
in
{
  environment.systemPackages = [ gpuMux ];

  systemd.tmpfiles.rules = [ "d /run/gpu-mux 0755 root root -" ];

  systemd.services.gpu-mux-auto = {
    description = "Set the display MUX for the next boot from the power state";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
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
