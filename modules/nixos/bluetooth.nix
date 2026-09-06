{ ... }:
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # Needed by headset/battery profiles the ii widgets poll.
    settings.General.Experimental = true;
  };
}
