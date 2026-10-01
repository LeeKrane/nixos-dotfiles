# The FX707VV4's display MUX, through the kernel's asus-armoury firmware attribute. Hybrid (1)
# wires the panel to the Intel iGPU and makes Hyprland composite there, so a game rendered on
# the dGPU is copied across PCIe every frame, twice for HDMI-A-1, which hangs off the dGPU in
# both modes. dgpu (0) wires the panel to the NVIDIA dGPU too: no copies, but the dGPU never
# sleeps, which costs battery. The firmware applies a new mode only at the next boot.
{ pkgs, ... }:
let
  gpuMux = pkgs.writeShellApplication {
    name = "gpu-mux";
    text = ''
      attr=/sys/class/firmware-attributes/asus-armoury/attributes/gpu_mux_mode/current_value
      case "''${1:-}" in
        "")
          case "$(cat "$attr")" in
            0) echo dgpu ;;
            1) echo hybrid ;;
            *) echo "unknown: $(cat "$attr")" ;;
          esac
          ;;
        dgpu) echo 0 | sudo tee "$attr" >/dev/null && echo "MUX set to dgpu. Reboot to apply." ;;
        hybrid) echo 1 | sudo tee "$attr" >/dev/null && echo "MUX set to hybrid. Reboot to apply." ;;
        *)
          echo "usage: gpu-mux [dgpu|hybrid]" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ gpuMux ];
}
