# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is Tom Koreny's NixOS/Darwin configuration repository using Nix flakes and Snowfall Lib. It manages system configurations for both NixOS (Linux) and macOS (Darwin) systems.

## Essential Commands

### System Rebuild
- **Primary command**: `sw` (shell alias)
  - On macOS: executes `nh darwin switch`
  - On NixOS: executes `nh os switch`
- The `nh` tool automatically uses the correct flake path:
  - macOS: `/Users/tom/home`
  - Linux: `/home/tom/nixos2`

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
Always run `sw` after making changes to apply the new configuration. The `nh` tool will show build progress and automatically clean up old generations.

### Git Workflow
- git-crypt is configured for secrets management
- Standard git workflow applies for version control