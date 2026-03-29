# OpenClaw Node Module for NixOS

This module runs an OpenClaw node service that connects to your gateway.

## What it does

- Installs Node.js 22 + pnpm
- Installs openclaw via pnpm (auto-updates on service start)
- Runs `openclaw node run` as a systemd user service
- Connects to the gateway at clawdbot.home.tomkoreny.com:443 (TLS) by default

## Usage

Add to your NixOS system config:

```nix
{
  tomkoreny.nixos.clawdbot-node = {
    enable = true;
    displayName = "NixOS Desktop";
    # Defaults: gatewayHost = "clawdbot.home.tomkoreny.com", gatewayPort = 443, tls = true
  };
}
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake .#nixos
```

## After first deploy

1. The node will attempt to connect to the gateway
2. On the gateway, approve the pairing request:
   ```bash
   openclaw nodes pending
   openclaw nodes approve <requestId>
   ```
3. Check status:
   ```bash
   openclaw nodes status
   ```

## Managing the service

```bash
# Check status (user service)
systemctl --user status openclaw-node

# View logs
journalctl --user -u openclaw-node -f

# Restart
systemctl --user restart openclaw-node
```

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `enable` | false | Enable the node service |
| `gatewayHost` | `clawdbot.home.tomkoreny.com` | Gateway hostname |
| `gatewayPort` | 443 | Gateway port |
| `tls` | true | Use TLS |
| `tlsFingerprint` | "" | Pin TLS cert fingerprint |
| `displayName` | "NixOS Desktop" | Name shown in gateway |
| `user` | (from common) | User to run as |
| `autoUpdate` | true | Update openclaw on start |
| `extraFlags` | [] | Additional CLI flags |
