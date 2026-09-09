# Repository Guidelines

## Project Structure & Module Organization
The root `flake.nix` is hand-wired (no Snowfall Lib, no flake-parts — it calls `nixosSystem`/`darwinSystem`/`homeManagerConfiguration` directly); treat it as the entry point for adding new modules or packages. Directories under `modules/<platform>/` are discovered automatically by `autoModules`, but Nix only sees git-tracked files, so `git add` a new module before building. Reusable modules live in `modules/<platform>/<topic>/` (for example `modules/nixos/networking-fixes`), while host manifests sit under `systems/<arch>/<host>/default.nix` next to hardware profiles or assets like `mkcert-ca.pem`. Home Manager profiles mirror that layout in `homes/<arch>/<user@host>/default.nix`, keeping user tweaks separate from system code.

## Build, Test, and Development Commands
- `nix flake show` – confirm the flake evaluates and exposes the expected outputs.
- `nix flake check` – run before every push to catch evaluation or formatting regressions.
- `sudo -n /run/current-system/sw/bin/nixos-rebuild switch --flake .#nixos` – deploys the Linux host, including every `modules/home` profile (Home Manager runs as a NixOS module here; there is no standalone `home-manager` binary). `nixos-rebuild` is allowlisted for passwordless sudo in `systems/x86_64-linux/nixos/default.nix`, so agents can run this themselves; `-n` fails fast instead of prompting if the rule is missing. Add `--show-trace` when diagnosing eval errors.
- `darwin-rebuild switch --flake .#macos` – applies the macOS configuration defined in `systems/aarch64-darwin/macos`; this one still prompts for sudo.

## Coding Style & Naming Conventions
Nix expressions use two-space indentation, trailing semicolons for attribute sets, and multi-line lists with aligned brackets; mirror the style in `systems/x86_64-linux/nixos/default.nix`. Prefer descriptive attribute names (`swapDevices`, `extraHosts`) and hyphenated directories (`networking-fixes`). Keep comments focused on intent, especially when overriding defaults (`lib.mkForce`, cache tweaks). Run `nix fmt` (or `nixpkgs-fmt`) before committing to keep formatting consistent.

## Testing Guidelines
Every change should evaluate with `nix flake check`; add host-specific dry runs (`nixos-rebuild dry-run --flake .#nixos`, `darwin-rebuild check --flake .#macos`) when touching boot-critical paths. For Home Manager edits, `nix eval '.#homeConfigurations."tom@nixos".config.home.file."<path>".source'` checks a single entry without a rebuild. Capture `--show-trace` output for failures and reference affected hosts in review notes.

## Commit & Pull Request Guidelines
Follow the emerging Conventional Commit style (`fix: ...`, `chore: ...`), keeping subjects imperative and under 72 characters. Group related changes per commit and mention the affected host or module (`modules/nixos/networking-fixes: adjust sysctls`). Pull requests should include a concise summary, impacted hosts or profiles, links to related issues, and supporting output when UI or service status changes.

## Security & Configuration Tips
Treat certificates and secrets as sensitive: never commit real private keys, and document any updates to `mkcert-ca.pem`. Keep network overrides (e.g. `pcie_port_pm=off`, dnsmasq tweaks) explained with intent comments so future contributors can validate them. Audit caches and binary substituters when adding new inputs to maintain trusted build roots.
