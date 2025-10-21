{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    hyprland.url = "github:hyprwm/Hyprland";
    stylix.url = "github:danth/stylix";
    nvf.url = "github:notashelf/nvf";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";

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
    zen-browser.url = "github:0xc000022070/zen-browser-flake";
    lan-mouse.url = "github:feschber/lan-mouse";
    mac-app-util.url = "github:hraban/mac-app-util";
    puma-rails.url = "github:puma/homebrew-puma";
    puma-rails.flake = false;

    # San Francisco Fonts | Apple Fonts
    apple-fonts.url= "github:Lyndeno/apple-fonts.nix";
    apple-fonts.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs:
    inputs.snowfall-lib.mkFlake {
      inherit inputs;
      src = ./.;
      systems = {
        # Add modules to all NixOS systems.
        modules.nixos = with inputs; [
          hyprland.nixosModules.default
          stylix.nixosModules.stylix
          lanzaboote.nixosModules.lanzaboote
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

        # Add a module to a specific host.
        # hosts.nixos.modules = with inputs; [
        #   # my-input.nixosModules.my-module
        # ];
        #
        # Add a custom value to `specialArgs`.
        hosts.nixos.specialArgs = {
          my-custom-value = "my-value";
        };
      };
      home-manager.sharedModules = [
        inputs.mac-app-util.homeManagerModules.default
        inputs.stylix.homeManagerModules.stylix
        inputs.sops-nix.homeManagerModules.sops
      ];

      channels-config = {
        # Allow unfree packages.
        allowUnfree = true;
      };
      # Configure Snowfall Lib, all of these settings are optional.
      snowfall = {
        # Tell Snowfall Lib to look in the `./nix/` directory for your
        # Nix files.
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
