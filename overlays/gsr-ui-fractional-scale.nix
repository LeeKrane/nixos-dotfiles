_final: prev: {
  gpu-screen-recorder-ui = prev.gpu-screen-recorder-ui.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ../patches/gsr-ui-fractional-scale.patch ];
  });
}
