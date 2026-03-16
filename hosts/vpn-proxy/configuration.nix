{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Shared library dependencies for Zscaler binaries
  zscalerLibs = with pkgs; [
    zlib openssl nss nspr dbus dbus-glib glib gcc-unwrapped.lib
    gtk3 atk pango cairo gdk-pixbuf
    libX11 libXcomposite libXdamage libXext libXfixes libXrandr libxcb
    libdrm mesa alsa-lib at-spi2-atk at-spi2-core cups expat libxkbcommon
    libpcap curl
  ];

  # Additional Qt5 libs for ZSTray GUI
  zscalerTrayLibs = zscalerLibs ++ (with pkgs.qt5; [
    qtbase qtwebengine qtwebchannel qtwebsockets
  ]);

  zscalerLibPath = lib.makeLibraryPath zscalerLibs + ":/opt/zscaler/lib";
  zscalerTrayLibPath = lib.makeLibraryPath zscalerTrayLibs + ":/opt/zscaler/lib";
in

{
  imports = [
    ./hardware-configuration.nix
    ../../common/packages.nix
  ];

  # Enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Allow insecure Qt5 WebEngine (EOL but required by Zscaler GUI tray)
  nixpkgs.config.permittedInsecurePackages = [
    "qtwebengine-5.15.19"
  ];

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
    firefox
    iptables
    tcpdump
    traceroute
    ethtool

    # Zscaler installer script: download the .deb, then run `install-zscaler <path-to.deb>`
    (pkgs.writeShellScriptBin "install-zscaler" ''
      set -euo pipefail
      if [ $# -ne 1 ] || [ ! -f "$1" ]; then
        echo "Usage: install-zscaler <path-to-zscaler.deb>"
        exit 1
      fi
      tmp=$(mktemp -d)
      ${pkgs.dpkg}/bin/dpkg-deb -x "$1" "$tmp"
      sudo mkdir -p /opt/zscaler
      sudo cp -a "$tmp/opt/zscaler/." /opt/zscaler/
      rm -rf "$tmp"
      echo "Zscaler installed to /opt/zscaler"
      echo "Start it with: sudo systemctl start zscaler"
    '')

    # Interactive shell for Zscaler debugging
    (pkgs.writeShellScriptBin "zscaler-env" ''
      export LD_LIBRARY_PATH="${zscalerLibPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
      exec bash "$@"
    '')
  ];

  # nix-ld provides /lib64/ld-linux-x86-64.so.2 so unpatched binaries can run
  programs.nix-ld.enable = true;

  # Zscaler service daemon (zsaservice)
  systemd.services.zscaler = {
    description = "Zscaler Client Connector (zsaservice)";
    after = [ "network-online.target" "dbus.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      LD_LIBRARY_PATH = zscalerLibPath;
    };
    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = 10;
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'test -x /opt/zscaler/bin/zsaservice'";
      ExecStart = "/opt/zscaler/bin/zsaservice";
    };
  };

  # Zscaler GUI tray (ZSTray) — runs as user for Zscaler authentication
  systemd.services.zscaler-tray = {
    description = "Zscaler Tray (GUI)";
    after = [ "zscaler.service" "display-manager.service" ];
    wants = [ "zscaler.service" ];
    wantedBy = [ "multi-user.target" ];
    environment = {
      DISPLAY = ":0";
      LD_LIBRARY_PATH = zscalerTrayLibPath;
    };
    serviceConfig = {
      Type = "simple";
      User = "jgordijn";
      Restart = "on-failure";
      RestartSec = 10;
      ExecStartPre = "${pkgs.bash}/bin/bash -c 'test -x /opt/zscaler/bin/ZSTray.Deb'";
      ExecStart = "/opt/zscaler/bin/ZSTray.Deb";
    };
  };

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
  };
  services.displayManager.autoLogin = {
    enable = true;
    user = "jgordijn";
  };

  # Disable screen lock (passwordless user)
  services.xserver.xautolock.enable = false;
  programs.xfconf.enable = true;  # needed for xfce settings
  environment.etc."xdg/xfce4/kiosk/kioskrc".text = ''
    [xfce4-session]
    SaveSession=NONE
    [xfce4-power-manager]
    LockScreen=NONE
    [xfce4-screensaver]
    Lock=NONE
  '';
  # Disable light-locker (XFCE's default screen locker)
  environment.etc."xdg/autostart/light-locker.desktop".text = ''
    [Desktop Entry]
    Hidden=true
  '';
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
