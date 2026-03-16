{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../common/packages.nix
  ];

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Bootloader (EFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;


  networking.hostName = "vpn-proxy";

  time.timeZone = "Europe/Amsterdam";

  users.mutableUsers = false;

  users.users.jgordijn = {
    isNormalUser = true;
    extraGroups = [ "wheel" "nopasswdlogin" ];
    shell = pkgs.zsh;
    initialPassword = "changeme";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBSSGbehh9Y6I9DSejnaNUGhXkinx3QT66NLtsUu/H1n"
    ];
  };

  # Auto-login group for LightDM
  users.groups.nopasswdlogin = { };

  # Allow wheel group to sudo without password
  security.sudo.wheelNeedsPassword = false;

  # Terminal colors
  environment.variables.COLORTERM = "truecolor";

  # System packages
  environment.systemPackages = with pkgs; [
    coreutils
    findutils
    gnugrep
    gnused
    vim
    iptables
    tcpdump
    traceroute
    ethtool

    # FHS environment for running Zscaler Client Connector
    # Zscaler is proprietary and not in nixpkgs.
    # After installing the .deb, run `zscaler-env` to enter the sandbox.
    (buildFHSEnv {
      name = "zscaler-env";
      targetPkgs = pkgs: with pkgs; [
        zlib
        openssl
        nss
        nspr
        dbus
        glib
        gtk3
        atk
        pango
        cairo
        gdk-pixbuf
        libX11
        libXcomposite
        libXdamage
        libXext
        libXfixes
        libXrandr
        libxcb
        libdrm
        mesa
        alsa-lib
        at-spi2-atk
        at-spi2-core
        cups
        expat
        libxkbcommon
      ];
      runScript = "bash";
    })
  ];

  programs.zsh.enable = true;

  # ---------- Home-manager ----------
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.users.jgordijn = import ../../home/nixos.nix;

  # ---------- SSH ----------
  services.openssh.enable = true;

  # ---------- Proxmox integration ----------
  services.qemuGuest.enable = true;    # clean shutdown, IP display, memory ballooning, snapshots
  services.fstrim.enable = true;       # trim support for LVM thinpool disk with Discard

  # ---------- mDNS (hostname resolution) ----------
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  # ---------- Desktop Environment (required for Zscaler GUI auth) ----------
  services.xserver = {
    enable = true;
    desktopManager.xfce.enable = true;
    displayManager.lightdm = {
      enable = true;
      autoLogin = {
        enable = true;
        user = "jgordijn";
        timeout = 0;
      };
    };
  };

  # ---------- IP Forwarding ----------
  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
  };

  # ---------- Tailscale (subnet router) ----------
  #
  # This machine advertises Zscaler's corporate routes to the tailnet.
  # Other devices accept these routes and traffic flows:
  #   Client → tailscale0 → zcctun0 (Zscaler) → Corporate resources
  #
  # After first boot, run:
  #   sudo tailscale up \
  #     --accept-dns=false \
  #     --advertise-exit-node \
  #     --advertise-connector \
  #     --advertise-routes=100.64.0.0/16,10.72.0.0/16,10.82.0.0/16,10.83.0.0/16,10.232.0.0/16,45.135.56.0/22,195.114.30.0/24,141.93.181.0/24 \
  #     --netfilter-mode=off
  #
  # Then approve the routes in the Tailscale Admin Console.
  #
  # On client devices:
  #   sudo tailscale up --accept-routes
  #
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    extraUpFlags = [
      "--accept-dns=false"
      "--advertise-exit-node"
      "--advertise-connector"
      "--advertise-routes=100.64.0.0/16,10.72.0.0/16,10.82.0.0/16,10.83.0.0/16,10.232.0.0/16,45.135.56.0/22,195.114.30.0/24,141.93.181.0/24"
      "--netfilter-mode=off"
    ];
  };
  # ---------- iptables: NAT & Forwarding (tailscale0 ↔ zcctun0) ----------
  #
  # These rules forward corporate traffic from Tailscale into Zscaler's tunnel.
  # They are applied after zcctun0 appears (i.e., after Zscaler connects).
  #
  networking.firewall.enable = false; # We manage iptables manually due to --netfilter-mode=off

  systemd.services.vpn-proxy-iptables = {
    description = "iptables rules for Tailscale ↔ Zscaler forwarding";
    after = [ "network.target" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];

    # Retry until zcctun0 comes up (Zscaler may start later)
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "vpn-proxy-iptables-up" ''
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -o zcctun0 -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -A FORWARD -i tailscale0 -o zcctun0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -A FORWARD -i zcctun0 -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT
      '';
      ExecStop = pkgs.writeShellScript "vpn-proxy-iptables-down" ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -o zcctun0 -j MASQUERADE
        ${pkgs.iptables}/bin/iptables -D FORWARD -i tailscale0 -o zcctun0 -j ACCEPT
        ${pkgs.iptables}/bin/iptables -D FORWARD -i zcctun0 -o tailscale0 -m state --state RELATED,ESTABLISHED -j ACCEPT
      '';
    };
  };

  # ---------- UDP GRO Optimization ----------
  systemd.services.tailscale-udp-gro = {
    description = "Enable UDP GRO forwarding for Tailscale performance";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "tailscale-udp-gro" ''
        iface=$(${pkgs.iproute2}/bin/ip -o route get 1.1.1.1 | ${pkgs.gawk}/bin/awk '{print $5; exit}')
        if [ -n "$iface" ]; then
          ${pkgs.ethtool}/bin/ethtool -K "$iface" rx-udp-gro-forwarding on rx-gro-list off || true
        fi
      '';
    };
  };
  system.stateVersion = "25.11";
}
