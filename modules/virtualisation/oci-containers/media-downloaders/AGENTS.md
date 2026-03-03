# media-downloaders/ — Download Stack

Loaded as a group on the `media` NixOS host. All traffic-generating containers route through Gluetun VPN.

## FILES

| File | Service | Notes |
|------|---------|-------|
| `gluetun.nix` | Gluetun (VPN gateway) | Creates `gluetun-network`; NET_ADMIN + `/dev/net/tun` device |
| `deluge.nix` | Deluge (BitTorrent) | Routes via gluetun-network; `dependsOn = ["gluetun"]` |
| `sabnzbd.nix` | SABnzbd (Usenet) | NZB downloader |
| `shelfmark.nix` | Shelfmark | Book downloader |

## VPN ROUTING PATTERN

Gluetun acts as the network gateway. Downloaders join `gluetun-network` and depend on gluetun:

```nix
virtualisation.oci-containers.containers.my-downloader = {
  dependsOn = [ "gluetun" ];
  networks = [ "gluetun-network" ];
  volumes = [ "gluetun:/pia:ro" ];  # shares gluetun volume for creds if needed
  # ...
};
```

Gluetun network is created in its own `activationScript` using `pkgs.podman`.

## DATA LAYOUT

```
/mnt/deluge/                            # deluge config
/mnt/media/downloads/torrents/
  incomplete/                           # in-progress torrents
  complete/                             # completed torrents
/mnt/media/downloads/                   # usenet/other downloads
```

## ANTI-PATTERNS

- Never expose downloader containers directly without routing through gluetun
- Never skip `dependsOn = ["gluetun"]` on a downloader — it won't have a network path
- Gluetun secret is at `./gluetun/environment.age` (subdir, not flat file)
