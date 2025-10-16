# Repository Guidelines

## Project Structure & Module Organization
The root `flake.nix` wires Snowfall Lib with the flake inputs; treat it as the entry point for adding new modules or packages. Reusable modules live in `modules/<platform>/<topic>/` (for example `modules/nixos/caddy`), while host manifests sit under `systems/<arch>/<host>/default.nix` next to hardware profiles or assets like `mkcert-ca.pem`. Home Manager profiles mirror that layout in `homes/<arch>/<user@host>/default.nix`, keeping user tweaks separate from system code.

## Build, Test, and Development Commands
- `nix flake show` – confirm the flake evaluates and exposes the expected outputs.
- `nix flake check` – run before every push to catch evaluation or formatting regressions.
- `sudo nixos-rebuild switch --flake .#nixos` – deploys the Linux host; add `--show-trace` when diagnosing eval errors.
- `darwin-rebuild switch --flake .#macos` – applies the macOS configuration defined in `systems/aarch64-darwin/macos`.
- `home-manager switch --flake ".#tom@nixos"` – refreshes the Home Manager profile without touching the system configuration.

## Coding Style & Naming Conventions
Nix expressions use two-space indentation, trailing semicolons for attribute sets, and multi-line lists with aligned brackets; mirror the style in `systems/x86_64-linux/nixos/default.nix`. Prefer descriptive attribute names (`swapDevices`, `extraHosts`) and hyphenated directories (`networking-fixes`). Keep comments focused on intent, especially when overriding defaults (`lib.mkForce`, cache tweaks). Run `nix fmt` (or `nixpkgs-fmt`) before committing to keep formatting consistent.

## Testing Guidelines
Every change should evaluate with `nix flake check`; add host-specific dry runs (`nixos-rebuild dry-run --flake .#nixos`, `darwin-rebuild check --flake .#macos`) when touching boot-critical paths. For Home Manager edits, use `home-manager switch --flake` with `--dry-run` to verify activations. Capture `--show-trace` output for failures and reference affected hosts in review notes.

## Commit & Pull Request Guidelines
Follow the emerging Conventional Commit style (`fix: ...`, `chore: ...`), keeping subjects imperative and under 72 characters. Group related changes per commit and mention the affected host or module (`modules/nixos/caddy: enable metrics`). Pull requests should include a concise summary, impacted hosts or profiles, links to related issues, and supporting output when UI or service status changes.

## Security & Configuration Tips
Treat certificates and secrets as sensitive: never commit real private keys, and document any updates to `mkcert-ca.pem`. Keep network overrides (e.g. `pcie_port_pm=off`, dnsmasq tweaks) explained with intent comments so future contributors can validate them. Audit caches and binary substituters when adding new inputs to maintain trusted build roots.
