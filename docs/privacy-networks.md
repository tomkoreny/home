# I2P and Yggdrasil

Both hosts run:

- **i2pd**, with its web console and local HTTP/SOCKS proxies bound only to
  loopback.
- **Yggdrasil**, with a distinct Ed25519 identity per host. The private keys are
  encrypted under `secrets/yggdrasil/` and decrypted by sops-nix.

The configured public Yggdrasil peers are community-operated. Check the current
list at <https://publicpeers.neilalexander.dev/> if either peer stops working.
Override `yggdrasilPeers` in the relevant host configuration to replace them:

```nix
tomkoreny.nixos.privacy-networks.yggdrasilPeers = [
  "tls://peer.example:12345"
];

# Use tomkoreny.darwin.privacy-networks.yggdrasilPeers on macOS.
```

## Deploy

Commit the new modules and encrypted secrets before deploying from a Git flake;
untracked files are excluded from `.#host` evaluations.

On NixOS:

```console
sudo nixos-rebuild switch --flake .#nixos
```

On macOS:

```console
darwin-rebuild switch --flake .#macos
```

The first I2P bootstrap can take several minutes while i2pd reseeds and builds
its network view.

## Use I2P

Open the local i2pd console:

- <http://127.0.0.1:7070/>

Configure an application with either local proxy:

- HTTP proxy: `127.0.0.1:4444`
- SOCKS proxy: `127.0.0.1:4447`

For command-line SOCKS clients, use `socks5h` rather than `socks5` so hostname
resolution also goes through i2pd:

```console
curl --proxy http://127.0.0.1:4444 http://i2pd.i2p/
curl --proxy socks5h://127.0.0.1:4447 http://i2pd.i2p/
```

Do not configure these proxies as public listeners. They intentionally bind to
localhost only.

## Use Yggdrasil

Inspect this node and its direct peers.

On NixOS:

```console
sudo yggdrasilctl -endpoint=unix:///run/yggdrasil/yggdrasil.sock getSelf
sudo yggdrasilctl -endpoint=unix:///run/yggdrasil/yggdrasil.sock getPeers
```

On macOS:

```console
sudo yggdrasilctl -endpoint=unix:///var/run/yggdrasil.sock getSelf
sudo yggdrasilctl -endpoint=unix:///var/run/yggdrasil.sock getPeers
```

`getSelf` reports the stable `200::/7` Yggdrasil address. Use that IPv6 address
to connect between the two hosts or to other Yggdrasil nodes. Host services must
still listen on IPv6, and the local firewall must permit their ports.

## Service status and logs

NixOS:

```console
systemctl status i2pd yggdrasil
journalctl -u i2pd -u yggdrasil -f
```

macOS:

```console
launchctl print gui/$(id -u)/org.nixos.i2pd
sudo launchctl print system/org.nixos.yggdrasil
tail -f ~/Library/Logs/i2pd.log
sudo tail -f /var/log/yggdrasil.log
```

The macOS i2pd state is stored in
`~/Library/Application Support/i2pd`. NixOS stores it in `/var/lib/i2pd`.

## Rotate a Yggdrasil identity

Each host must have its own private key. Never reuse one key on simultaneously
running nodes, and never commit an unencrypted PEM file.

To rotate a key, generate an Ed25519 key in a protected temporary location,
encrypt it with the repository's `.sops.yaml` recipients, replace only the
matching host file, and rebuild that host. Rotation changes its Yggdrasil IPv6
address.
