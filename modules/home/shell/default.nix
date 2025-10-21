{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  inputs,
  # Additional metadata is provided by Snowfall Lib.
  namespace, # The namespace used for your flake, defaulting to "internal" if not set.
  system, # The system architecture for this host (eg. `x86_64-linux`).
  target, # The Snowfall Lib target for this system (eg. `x86_64-iso`).
  format, # A normalized name for the system target (eg. `iso`).
  virtual, # A boolean to determine whether this system is a virtual target using nixos-generators.
  systems, # An attribute map of your defined hosts.
  # All other arguments come from the system system.
  config,
  ...
}: {
  home.shellAliases = {
    v = "nvim";
#    ssh = "kitten ssh";
    vi = "nvim";
    conf = "nvim ~/nixos2";
    sw = if lib.strings.hasInfix "darwin" system then "nh darwin switch" else "nh os switch";
    dcu = "docker compose up -d";
    dcd = "docker compose down";
    dc = "docker compose";
    dev = "npm run dev";
    start = "npm run start";
  };
  programs.bash.enable = true;
  programs.bash.initExtra = lib.mkAfter ''
    ksecret() {
      if [ -z "$1" ]; then
        echo "usage: ksecret <cluster>" >&2
        return 1
      fi

      local secrets_dir="$HOME/nixos2/secrets/kubeconfig"
      local secret_file="$secrets_dir/$1.json"

      if [ ! -f "$secret_file" ]; then
        echo "secret file not found: $secret_file" >&2
        return 1
      fi

      SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt" \
        ${pkgs.sops}/bin/sops "$secret_file"
    }
  '';
  programs.starship.enable = true;
}
