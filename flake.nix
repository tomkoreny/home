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
    nixvim.url = "github:nix-community/nixvim";
    nixvim.inputs.nixpkgs.follows = "nixpkgs";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.1";

      # Optional but recommended to limit the size of your system closure.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin.url = "github:LnL7/nix-darwin";
    darwin.inputs.nixpkgs.follows = "nixpkgs";
    };

    outputs = inputs:
        inputs.snowfall-lib.mkFlake {
            inherit inputs;
            src = ./.;
	    
# Add modules to all NixOS systems.
	    systems.modules.nixos = with inputs; [
      hyprland.nixosModules.default
      stylix.nixosModules.stylix
      lanzaboote.nixosModules.lanzaboote
      home-manager.nixosModules.default
	    ];

# If you wanted to configure a Darwin (macOS) system.
# systems.modules.darwin = with inputs; [
#   my-input.darwinModules.my-module
# ];

# Add a module to a specific host.
	    systems.hosts.nixos.modules = with inputs; [
# my-input.nixosModules.my-module
	    ];

# Add a custom value to `specialArgs`.
	    systems.hosts.nixos.specialArgs = {
		    my-custom-value = "my-value";
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
