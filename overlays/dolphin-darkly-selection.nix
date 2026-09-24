# Dolphin 26.08 paints selected-item text in the normal Text color, because it expects a
# translucent selection highlight. It only draws that highlight itself when the style is
# Breeze; every other style gets PE_PanelItemViewItem, and Darkly fills it with a solid
# Highlight. Under ii's MaterialYouDark that is white text on light purple. Route Darkly
# through Dolphin's Breeze path too. Drop once Darkly draws a translucent selection itself.
_final: prev: {
  kdePackages = prev.kdePackages.overrideScope (
    _kfinal: kprev: {
      dolphin = kprev.dolphin.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace src/kitemviews/kitemlistwidget.cpp \
            --replace-fail 'if (style()->name() == QStringLiteral("breeze")) {' \
                           'if (style()->name() == QStringLiteral("breeze") || style()->name() == QStringLiteral("darkly")) {'
        '';
      });
    }
  );
}
