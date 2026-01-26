# Clawdbot Node Module for NixOS

This module runs a Clawdbot node service that connects to your gateway.

## What it does

- Installs Node.js 22 + pnpm
- Installs clawdbot via pnpm (auto-updates on service start)
- Runs `clawdbot node run` as a systemd user service
- Connects to the gateway at 192.168.1.93:18789 by default

## Usage

Add to your NixOS system config:

```nix
{
  imports = [
    ../../../modules/nixos/clawdbot-node
  ];

  tomkoreny.nixos.clawdbot-node = {
    enable = true;
    displayName = "NixOS Desktop";
    # Optional overrides:
    # gatewayHost = "192.168.1.93";
    # gatewayPort = 18789;
    # extraFlags = [ "--tls" ];
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
   clawdbot nodes pending
   clawdbot nodes approve <requestId>
   ```
3. Check status:
   ```bash
   clawdbot nodes status
   ```

## Managing the service

```bash
# Check status
systemctl --user status clawdbot-node

# View logs
journalctl --user -u clawdbot-node -f

# Restart
systemctl --user restart clawdbot-node
```

## Exposed capabilities

The headless node exposes:
- `system.run` - execute commands on the NixOS machine
- `system.which` - check if binaries exist
- `system.execApprovals.get/set` - manage exec allowlist

## Security

Exec commands are gated by `~/.clawdbot/exec-approvals.json`. 
Add allowlist entries from the gateway:

```bash
clawdbot approvals allowlist add --node "NixOS Desktop" "/usr/bin/ls"
clawdbot approvals allowlist add --node "NixOS Desktop" "/run/current-system/sw/bin/*"
```
