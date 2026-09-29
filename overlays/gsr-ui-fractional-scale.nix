# gsr-ui 1.13.5's Wayland overlay is a layer surface created without a target output. Hyprland
# sends wp_fractional_scale_v1.preferred_scale only after the first buffer, so mgl first falls
# back to the highest integer wl_output.scale of any monitor (2 for tarmantria's panel at 1.6
# while HDMI is attached), gsr-ui lays its UI out for that doubled size, and when the real scale
# (1 on HDMI) arrives the buffer shrinks but the layout stays doubled: oversized and clipped.
# Skip that guess whenever the fractional-scale object exists, so the surface starts at scale 1
# and takes the compositor's value when it comes. Drop once upstream waits for preferred_scale.
_final: prev: {
  gpu-screen-recorder-ui = prev.gpu-screen-recorder-ui.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/gsr-ui-fractional-scale.patch ];
  });
}
