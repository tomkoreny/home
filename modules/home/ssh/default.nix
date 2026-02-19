{ config, lib, pkgs, ... }:

{
  programs.ssh = {
    enable = true;
    
    matchBlocks = {
      "proxmox" = {
        hostname = "192.168.1.2";
        user = "root";
      };
      
      "docker-host" = {
        hostname = "192.168.1.93";
        user = "root";
      };
      
      "nixos-desktop" = {
        hostname = "192.168.5.201";
        user = "tom";
      };
      
      "lempls" = {
        hostname = "lempls.com";
        user = "puma";
      };
      
      "teplice-ec2" = {
        hostname = "ec2-35-159-178-203.eu-central-1.compute.amazonaws.com";
        user = "ec2-user";
        identityFile = "~/Downloads/tom-mac.pem";
      };
      
      "hbc-server" = {
        hostname = "185.156.39.202";
        user = "tech1";
        port = 33894;
      };
    };
    
    extraConfig = ''
      ControlMaster auto
      ControlPath ~/.ssh/sockets/ssh_mux_%h_%p_%r
      ControlPersist 600
      
      Compression yes
      ServerAliveInterval 60
      ServerAliveCountMax 10
      
      Include ~/.orbstack/ssh/config
    '';
  };
  
  home.file.".ssh/sockets/.keep" = {
    text = "";
  };
}
