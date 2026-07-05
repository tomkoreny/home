# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is Tom Koreny's NixOS/Darwin configuration repository using Nix flakes and Snowfall Lib. It manages system configurations for both NixOS (Linux) and macOS (Darwin) systems.

## Essential Commands

### System Rebuild
- **Primary command**: `sw` (script in PATH)
  - On macOS: executes `nh darwin switch` (flake path `/Users/tom/home`)
  - On NixOS: executes `sudo nixos-rebuild switch --flake /home/tom/nixos2#nixos`
    (not nh: the restricted NOPASSWD sudoers rule can't match nh's
    `sudo env ...` wrapper)

### Flake Management
- `nix flake update` - Update all flake inputs
- `nix flake check` - Validate the flake configuration
- `nix build` - Build flake outputs
- `nix develop` - Enter development shell

### Configuration Editing
- `conf` - Opens the config in nvim (alias for `nvim ~/nixos2`)

## Architecture & Structure

### Directory Layout
```
├── flake.nix          # Main flake configuration
├── flake.lock         # Locked dependencies
├── homes/             # Home-manager configurations
│   ├── aarch64-darwin/# macOS (Apple Silicon) home configs
│   └── x86_64-linux/  # Linux home configs
├── modules/           # Reusable Nix modules
│   ├── darwin/        # macOS-specific modules
│   ├── home/          # Home-manager modules (packages, shell, etc.)
│   └── nixos/         # NixOS-specific modules
└── systems/           # System configurations
    ├── aarch64-darwin/# macOS system config
    └── x86_64-linux/  # NixOS system config
```

### Key Concepts
- **Snowfall Lib**: The framework organizing this flake, providing conventions for module organization
- **Multi-platform**: Supports both NixOS and macOS through unified configuration
- **Namespace**: `tomkoreny` - custom namespace for the project
- **Home-manager**: Integrated into system configurations for user-level settings

### Platform-Specific Features
- **macOS**: Uses nix-darwin with Homebrew integration for casks
- **NixOS**: Includes Hyprland window manager, Secure Boot via lanzaboote, rootless Docker
- **Both**: Tailscale VPN, Stylix theming, development tools

### Keyboard Layout (important for keybinds)
The primary keyboard is a **Miryoku** ergonomic split board running **Colemak-DH**
in QMK firmware (the OS layout stays `us`/QWERTY; the remap is firmware-side).
Consequences when adding or changing keybinds:
- Modifiers are **home-row holds**: Super/GUI, Alt, Ctrl, Shift. Right Alt is a
  hold-mod (the `I` key) and is **not tappable**, so Compose-key workflows do not
  work here.
- Numbers and symbols live on **thumb-activated layers** (Num/Sym/Fun), so the
  number row and chorded mods (e.g. `Super+Shift+<n>`) are awkward to press.
- Prefer **single-mod binds**, ideally `Super + <letter on the opposite hand>`.
- **Czech diacritics**: direct per-key typing is handled in the **QMK firmware**
  (a dedicated layer on the board), not the OS layout — OS-side compose/group
  tricks don't fit Miryoku's held mods. `Super+D` runs the `diacritics-fix`
  script (AI rewrite of the selection) for whole phrases. See `docs/reference.html`.

### Module Organization
- Shell configuration: `modules/home/shell/default.nix`
- Package definitions: `modules/home/packages/default.nix`
- Platform-specific system settings: `systems/<platform>/<hostname>/default.nix`

## Development Considerations

### Adding Packages
- User packages: Edit `modules/home/packages/default.nix`
- System packages: Edit the relevant system configuration in `systems/`
- macOS casks: Add to `brews` list in `systems/aarch64-darwin/macos/default.nix`

### Testing Changes
Always run `sw` after making changes to apply the new configuration. The `nh` tool shows build progress; old generations are cleaned by nh's scheduled clean (`programs.nh.clean`).

### Git Workflow
- Secrets are managed with **sops-nix** (age keys, rules in `.sops.yaml`); everything under `secrets/` must be sops-encrypted — there is no git-crypt filter, so a plaintext file committed there stays plaintext
- Standard git workflow applies for version control