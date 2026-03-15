{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./common/packages.nix
  ];

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # LXC container - no bootloader
  boot.loader.systemd-boot.enable = false;
  boot.loader.grub.enable = false;
  boot.loader.grub.devices = [ ];
  boot.isContainer = true;

  networking.hostName = "nixos";

  time.timeZone = "Europe/Amsterdam";

  users.mutableUsers = false;
  users.allowNoPasswordLogin = true;

  users.users.jgordijn = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
  };

  # Allow wheel group to sudo without password
  security.sudo.wheelNeedsPassword = false;

  # Terminal colors
  environment.variables.COLORTERM = "truecolor";

  # NixOS-only system packages
  environment.systemPackages = with pkgs; [
    coreutils
    findutils
    gnugrep
    gnused
    vim
  ];

  programs.zsh.enable = true;
  programs.zsh.ohMyZsh = {
    enable = true;
    plugins = [
      "git"
      "sudo"
      "docker"
    ];
    theme = "robbyrussell";
  };

  # Home-manager settings
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.jgordijn = import ./home/nixos.nix;

  # Enable Tailscale service
  services.tailscale.enable = true;

  services.openssh.enable = true;

  system.stateVersion = "25.11";
}
