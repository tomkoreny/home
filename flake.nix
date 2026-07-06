{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    # hyprland deliberately does NOT follow our nixpkgs: upstream recommends
    # keeping their pin so the Hyprland Cachix cache hits.
    hyprland.url = "github:hyprwm/Hyprland";
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";

      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

    # Optional: Declarative tap management
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    # Note: no `inputs.nixpkgs.follows` here — building lan-mouse against
    # nixpkgs-unstable breaks (appstream link failure on darwin) and defeats
    # the lan-mouse.cachix.org binary cache, which is keyed to upstream's pin.
    lan-mouse.url = "github:feschber/lan-mouse";
    # Note: no `inputs.nixpkgs.follows` here — mac-app-util is Common Lisp and
    # breaks with SBCL >= 2.6 from unstable (hraban/mac-app-util#42); upstream
    # deliberately pins nixos-26.05.
    mac-app-util.url = "github:hraban/mac-app-util";
    puma-rails.url = "github:puma/homebrew-puma";
    puma-rails.flake = false;

    # San Francisco Fonts | Apple Fonts
    apple-fonts.url = "github:Lyndeno/apple-fonts.nix";
    apple-fonts.inputs.nixpkgs.follows = "nixpkgs";

    # Fast-moving AI CLIs (claude-code, codex, *-acp) as native binaries,
    # auto-updated daily and served from Numtide's binary cache.
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    nix-ai-tools.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;
      src = ./.;
      systems = {
        # Add modules to all NixOS systems.
        modules.nixos = with inputs; [
          hyprland.nixosModules.default
          stylix.nixosModules.stylix
          ./nixos/lanzaboote-compat.nix
          ({ pkgs, ... }: {
            boot.lanzaboote.package =
              lanzaboote.packages.${pkgs.stdenv.hostPlatform.system}.lzbt;
          })
          home-manager.nixosModules.default
          sops-nix.nixosModules.sops
        ];

        # If you wanted to configure a Darwin (macOS) system.
        modules.darwin = with inputs; [
          nix-homebrew.darwinModules.nix-homebrew
          stylix.darwinModules.stylix
          mac-app-util.darwinModules.default
          sops-nix.darwinModules.sops
        ];

      };
      homes.modules = [
        inputs.mac-app-util.homeManagerModules.default
        inputs.stylix.homeModules.stylix
        inputs.sops-nix.homeManagerModules.sops
      ];
      outputs-builder = channels: {
        formatter = channels.nixpkgs.nixfmt;
      };

      channels-config = {
        # Allow unfree packages.
        allowUnfree = true;
      };
      # Configure Snowfall Lib, all of these settings are optional.
      snowfall = {
        root = ./.;

        # Choose a namespace to use for your flake's packages, library,
        # and overlays.
        namespace = "tomkoreny";

        # Add flake metadata that can be processed by tools like Snowfall Frost.
        meta = {
          # A slug to use in documentation when displaying things like file paths.
          name = "tomk-dots";

          # A title to show for your flake, typically the name.
          title = "Tom Koreny's NixOS config";
        };
      };
    };
}
