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
