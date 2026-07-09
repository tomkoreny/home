{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

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
    inputs@{
      nixpkgs,
      home-manager,
      darwin,
      ...
    }:
    let
      namespace = "tomkoreny";
      linuxHome = ./homes/x86_64-linux + "/tom@nixos";
      darwinHome = ./homes/aarch64-darwin + "/tom@macos";

      homeModules = [
        ./modules/home/betterbird
        ./modules/home/bun
        ./modules/home/git
        ./modules/home/helium
        ./modules/home/hyprland
        ./modules/home/jetbrains
        ./modules/home/k9s
        ./modules/home/kubeconfig
        ./modules/home/lanmouse
        ./modules/home/mako
        ./modules/home/multiviewer
        ./modules/home/nh
        ./modules/home/nixvim
        ./modules/home/packages
        ./modules/home/shell
        ./modules/home/ssh
        ./modules/home/stylix
        ./modules/home/waybar
      ];

      sharedHomeModules = [
        inputs.mac-app-util.homeManagerModules.default
        inputs.stylix.homeModules.stylix
        inputs.sops-nix.homeManagerModules.sops
      ] ++ homeModules;

      nixosModules = [
        inputs.hyprland.nixosModules.default
        inputs.stylix.nixosModules.stylix
        ./nixos/lanzaboote-compat.nix
        ({ pkgs, ... }: {
          boot.lanzaboote.package =
            inputs.lanzaboote.packages.${pkgs.stdenv.hostPlatform.system}.lzbt;
        })
        home-manager.nixosModules.home-manager
        inputs.sops-nix.nixosModules.sops
        ./modules/nixos/clawdbot-node
        ./modules/nixos/hyprland
        ./modules/nixos/networking-fixes
        ./modules/nixos/openfortivpn
        ./modules/nixos/stylix
      ];

      darwinModules = [
        inputs.nix-homebrew.darwinModules.nix-homebrew
        inputs.stylix.darwinModules.stylix
        inputs.mac-app-util.darwinModules.default
        inputs.sops-nix.darwinModules.sops
        home-manager.darwinModules.home-manager
        ./modules/darwin/auto-upgrade
        ./modules/darwin/stylix
        ./modules/darwin/vpn
      ];

      mkPkgs = system:
        import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

      mkSpecialArgs = system: {
        inherit inputs namespace system;
        target = system;
        format = if nixpkgs.lib.hasSuffix "-darwin" system then "darwin" else "linux";
        virtual = false;
        systems = { };
      };

      mkHome = { system, module }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = mkPkgs system;
          extraSpecialArgs = mkSpecialArgs system;
          modules = sharedHomeModules ++ [ module ];
        };

      homeManagerSystemConfig = system: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = mkSpecialArgs system;
          sharedModules = sharedHomeModules;
        };
      };
    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = mkSpecialArgs "x86_64-linux";
        modules = nixosModules ++ [
          (homeManagerSystemConfig "x86_64-linux")
          {
            nixpkgs.config.allowUnfree = true;
            home-manager.users.tom = import linuxHome;
          }
          ./systems/x86_64-linux/nixos
        ];
      };

      darwinConfigurations.macos = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        specialArgs = mkSpecialArgs "aarch64-darwin";
        modules = darwinModules ++ [
          (homeManagerSystemConfig "aarch64-darwin")
          {
            nixpkgs.config.allowUnfree = true;
            home-manager.users.tom = import darwinHome;
          }
          ./systems/aarch64-darwin/macos
        ];
      };

      homeConfigurations = {
        "tom@nixos" = mkHome {
          system = "x86_64-linux";
          module = linuxHome;
        };
        "tom@macos" = mkHome {
          system = "aarch64-darwin";
          module = darwinHome;
        };
      };

      formatter = {
        x86_64-linux = (mkPkgs "x86_64-linux").nixfmt;
        aarch64-darwin = (mkPkgs "aarch64-darwin").nixfmt;
      };
    };
}
