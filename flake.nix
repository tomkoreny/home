{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    # First rust-overlay revision using the non-deprecated hostPlatform checks.
    # Herdr, OMP, and Lanzaboote otherwise emit stdenv.is* warnings.
    rust-overlay = {
      url = "github:oxalica/rust-overlay/892c035d7c2ff75acd5da10424a47ab454e1f3dc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    herdr = {
      url = "github:herdrdev/herdr/v0.8.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    # Hyprland deliberately does NOT follow our nixpkgs: upstream recommends
    # keeping its dependency pins so the Hyprland Cachix cache hits. Both seats
    # use the new Lua configuration API, so they can follow current main.
    hyprland.url = "github:hyprwm/Hyprland";
    stylix = {
      url = "github:danth/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    omp = {
      url = "github:can1357/oh-my-pi";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    pi2-nvim = {
      url = "github:zgs225/pi2.nvim";
      flake = false;
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";

      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";

    # The Homebrew CLI must be at least as new as the pinned taps: homebrew-core
    # formulae use the InstallSteps DSL (`overwrite:`, `change_dylib_id`,
    # `update_gdk_pixbuf_loaders_cache`), which older brew releases cannot read
    # ("formula is unreadable"). nix-homebrew pins brew itself, so override it
    # and bump this tag whenever homebrew-core/homebrew-cask are updated.
    brew-src = {
      url = "github:Homebrew/brew/6.0.18";
      flake = false;
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
      inputs.brew-src.follows = "brew-src";
    };

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
    sikarugir-tap = {
      url = "github:Sikarugir-App/homebrew-sikarugir";
      flake = false;
    };

    # Browser-enabled Jellyfin MPV Shim pre-release and the dependency versions
    # it requires. Nixpkgs still packages the older cast-only 2.10.0 release.
    jellyfin-mpv-shim-src = {
      url = "github:jellyfin/jellyfin-mpv-shim/v3.0.0pre14";
      flake = false;
    };
    jellyfin-apiclient-python-src = {
      url = "github:jellyfin/jellyfin-apiclient-python/v1.18.0";
      flake = false;
    };
    python-mpv-jsonipc-src = {
      url = "github:iwalton3/python-mpv-jsonipc/v1.3.0";
      flake = false;
    };
    jellyfin-default-shader-pack-src = {
      url = "github:iwalton3/default-shader-pack/v3.0.0";
      flake = false;
    };

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

      # Every directory under modules/<platform>/ is a module; discover them
      # instead of maintaining a list by hand. This is the one convenience
      # Snowfall Lib would have provided, and it does not need Snowfall (or any
      # framework) to get: forgetting to register a new module here used to
      # surface as a baffling "option does not exist" at eval time.
      #
      # NOTE: Nix only sees git-tracked files, so a newly created module still
      # has to be `git add`ed before it is discoverable.
      autoModules =
        dir:
        nixpkgs.lib.mapAttrsToList (name: _: dir + "/${name}") (
          nixpkgs.lib.filterAttrs (_: type: type == "directory") (builtins.readDir dir)
        );

      linuxHome = ./homes/x86_64-linux + "/tom@nixos";
      terkaHome = ./homes/x86_64-linux + "/terka@nixos";
      darwinHome = ./homes/aarch64-darwin + "/tom@macos";

      homeModules = autoModules ./modules/home;

      sharedHomeModules = [
        inputs.mac-app-util.homeManagerModules.default
        inputs.omp.homeManagerModules.default
        inputs.stylix.homeModules.stylix
        inputs.sops-nix.homeManagerModules.sops
        ({ lib, ... }: {
          # Reapplying Stylix's package overlays inside Home Manager is
          # incompatible with useGlobalPkgs and causes standalone HM recursion.
          stylix.overlays.enable = lib.mkForce false;

          # `man home-configuration.nix` builds nixpkgs' options.json, which
          # embeds nixpkgs store paths after unsafeDiscardStringContext (see
          # nixos/lib/make-options-doc/default.nix) and warns on every eval,
          # because Home Manager imports nixos/modules/misc/meta.nix by path and
          # does not rewrite those declarations. Nothing repo-side can fix that,
          # and the same reference lives in the online option search.
          manual.manpages.enable = false;
        })
      ]
      ++ homeModules;

      nixosModules = [
        inputs.hyprland.nixosModules.default
        inputs.stylix.nixosModules.stylix
        ./nixos/lanzaboote-compat.nix
        ({ pkgs, ... }: {
          boot.lanzaboote.package = inputs.lanzaboote.packages.${pkgs.stdenv.hostPlatform.system}.lzbt;
        })
        home-manager.nixosModules.home-manager
        inputs.sops-nix.nixosModules.sops
      ]
      ++ autoModules ./modules/nixos;

      darwinModules = [
        inputs.nix-homebrew.darwinModules.nix-homebrew
        inputs.stylix.darwinModules.stylix
        inputs.mac-app-util.darwinModules.default
        inputs.sops-nix.darwinModules.sops
        home-manager.darwinModules.home-manager
      ]
      ++ autoModules ./modules/darwin;

      mkPkgs =
        system:
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

      mkHome =
        { system, module }:
        let
          pkgs = mkPkgs system;
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          # Stylix constructs overlay modules while the module graph is being
          # evaluated, so standalone profiles need pkgs as a special argument
          # rather than via Home Manager's recursive nixpkgs module.
          extraSpecialArgs = (mkSpecialArgs system) // {
            inherit pkgs;
          };
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
            home-manager.users.terka = import terkaHome;
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
        "terka@nixos" = mkHome {
          system = "x86_64-linux";
          module = terkaHome;
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
