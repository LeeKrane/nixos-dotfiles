# WireGuard on servers, from the peer table in lib/wireguard.nix.
#   hub (taragarmr): wg0 server for every peer, forwarding between them; wg1 for the Fika/SPT
#     players, defined but never started at boot (`systemctl start wg-quick-wg1`).
#   spoke (any other host in the table): wg0 client of the hub.
#
# Backend: networking.wg-quick for both interfaces, not systemd-networkd netdevs. wg1 must not
# autostart and only wg-quick has `autostart = false`; networkd netdevs come up whenever their
# .netdev file exists. One mechanism for both interfaces also matches the desktops' wg0
# (modules/nixos/desktop/networking.nix), and a wg-quick unit can retry when the hub's
# hostname does not resolve yet at boot, which a networkd netdev does not. networkd leaves
# the interfaces alone: its only .network matches en*/eth* (networking.nix).
#
# Private keys come from sops (secrets/<host>.yaml, section `wireguard`: wg0-private-key and,
# on the hub, wg1-private-key), declared only when that section exists. Without it no
# interface is configured, so the config evaluates before the host's secrets are created.
{
  config,
  lib,
  pkgs,
  hostName,
  ...
}:
let
  cfg = config.krane.wireguard;
  table = import ../../../lib/wireguard.nix;
  inherit (table) wg0 wg1;
  hostSecrets = import ../../../lib/host-secrets.nix { inherit lib hostName; };
  hasKeys = hostSecrets.hasSection "wireguard";

  isHub = hostName == wg0.hub.name;
  isSpoke = wg0.peers ? ${hostName};

  secretPath = name: config.sops.secrets."wireguard/${name}".path;
  iptables = lib.getExe' pkgs.iptables "iptables";
  # The old host's whole forwarding policy: accept everything in and out of the interface, no NAT.
  forwardRules = action: iface: ''
    ${iptables} -${action} FORWARD -i ${iface} -j ACCEPT
    ${iptables} -${action} FORWARD -o ${iface} -j ACCEPT
  '';
  hubPeers =
    net:
    lib.mapAttrsToList (_: peer: {
      inherit (peer) publicKey;
      allowedIPs = [ "${peer.ip}/32" ];
    }) net.peers;
  # Hosts without wg0 DNS at boot: keep retrying instead of failing once.
  retry = {
    unitConfig.StartLimitIntervalSec = 0;
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
in
{
  options.krane.wireguard = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = isHub || isSpoke;
      defaultText = lib.literalExpression "true when the host is in lib/wireguard.nix";
      description = "Configure wg0 (and wg1 on the hub) from the peer table in lib/wireguard.nix.";
    };
    wg0PrivateKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if hasKeys then secretPath "wg0-private-key" else null;
      defaultText = lib.literalExpression "the sops secret wireguard/wg0-private-key, if the host's secrets have a wireguard section";
      description = "Path of wg0's private key. wg0 is not configured while this is null.";
    };
    wg1PrivateKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if hasKeys then secretPath "wg1-private-key" else null;
      defaultText = lib.literalExpression "the sops secret wireguard/wg1-private-key, if the host's secrets have a wireguard section";
      description = "Path of wg1's private key (hub only). wg1 is not configured while this is null.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = isHub || isSpoke;
            message = "krane.wireguard.enable: host ${hostName} is not in lib/wireguard.nix";
          }
        ];
      }

      (lib.mkIf hasKeys {
        sops.secrets = {
          "wireguard/wg0-private-key" = {
            owner = "root";
            mode = "0400";
          };
        }
        // lib.optionalAttrs isHub {
          "wireguard/wg1-private-key" = {
            owner = "root";
            mode = "0400";
          };
        };
      })

      (lib.mkIf (cfg.wg0PrivateKeyFile != null) {
        networking.wg-quick.interfaces.${wg0.interface} =
          if isHub then
            {
              address = [ "${wg0.hub.ip}/${toString wg0.prefixLength}" ];
              inherit (wg0.hub) listenPort;
              privateKeyFile = cfg.wg0PrivateKeyFile;
              peers = hubPeers wg0;
              postUp = forwardRules "I" wg0.interface;
              postDown = forwardRules "D" wg0.interface;
            }
          else
            {
              address = [ "${wg0.peers.${hostName}.ip}/${toString wg0.prefixLength}" ];
              privateKeyFile = cfg.wg0PrivateKeyFile;
              peers = [
                {
                  inherit (wg0.hub) publicKey;
                  inherit (wg0) endpoint;
                  allowedIPs = [ wg0.network ];
                  persistentKeepalive = 25;
                }
              ];
            };
        systemd.services."wg-quick-${wg0.interface}" = retry;
      })

      (lib.mkIf isHub {
        # The hub forwards between its peers. The rules sit in wg0's PostUp (above) rather
        # than in networking.firewall: docker sets the FORWARD policy to DROP, and a rule
        # inserted at the top of the chain is independent of start order with it.
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
        networking.firewall = {
          allowedUDPPorts = [
            wg0.hub.listenPort
            # Open while wg1 is down; nothing listens then.
            wg1.hub.listenPort
          ];
          # Peers may reach every port on the hub, as on the old host.
          trustedInterfaces = [ wg0.interface ];
        };
      })

      (lib.mkIf (isHub && cfg.wg1PrivateKeyFile != null) {
        networking.wg-quick.interfaces.${wg1.interface} = {
          autostart = false;
          address = [ "${wg1.hub.ip}/${toString wg1.prefixLength}" ];
          inherit (wg1.hub) listenPort;
          privateKeyFile = cfg.wg1PrivateKeyFile;
          peers = hubPeers wg1;
        };
      })
    ]
  );
}
