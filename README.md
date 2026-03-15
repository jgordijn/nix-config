# NixOS Configuration

Declarative NixOS setup using flakes and home-manager.

## Structure

```
/etc/nixos/
├── flake.nix                  # Entry point — defines inputs (nixpkgs, home-manager) + hosts
├── flake.lock                 # Pinned versions — ensures reproducible builds
├── configuration.nix          # NixOS system config for this LXC container
├── hardware-configuration.nix # Auto-generated hardware config
├── common/
│   └── packages.nix           # System packages shared across all machines (NixOS + macOS)
└── home/
    ├── common.nix             # User tools shared everywhere (helix, git, fzf, zoxide, etc.)
    ├── nixos.nix              # NixOS-specific user config → imports common.nix
    └── darwin.nix             # macOS-specific user config → imports common.nix
```

## Daily Usage

### Rebuild after editing config

```bash
sudo nixos-rebuild switch --flake /etc/nixos#nixos-lxc
```

### Update all packages (nixpkgs + home-manager)

```bash
cd /etc/nixos
sudo nix flake update
sudo nixos-rebuild switch --flake .#nixos-lxc
sudo git add -A && sudo git commit -m "Update flake inputs"
```

### Garbage collect old generations

```bash
sudo nix-collect-garbage -d
```

## Bootstrapping a New NixOS LXC Container

### 1. Create the container in Proxmox

Create an LXC container from the NixOS minimal template.

### 2. Configure the container on the Proxmox host

```bash
cat >> /etc/pve/lxc/<id>.conf <<'CONF'
lxc.environment: PATH=/run/wrappers/bin:/root/.nix-profile/bin:/nix/profile/bin:/root/.local/state/nix/profile/bin:/etc/profiles/per-user/root/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/sbin:/bin:/usr/sbin:/usr/bin
lxc.cgroup2.devices.allow: c 10:200 rwm
lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file
CONF
```

- **PATH**: NixOS puts binaries in `/run/current-system/sw/bin`, not the standard `/usr/bin`. Without this, `pct enter` has no working commands.
- **cgroup + tun**: Required for Tailscale to create its network tunnel device.

Reboot the container after changing the config:

```bash
pct reboot <id>
```

### 3. Bootstrap from the Proxmox host

```bash
# Enter the container
pct exec <id> -- /run/current-system/sw/bin/bash -l

# Inside the container:

# Clone this config repo
nix --extra-experimental-features "nix-command flakes" shell nixpkgs#git -c \
  git clone <repo-url> /etc/nixos

# Generate hardware config for this specific machine
nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix

# Mark the repo as safe for root
git config --global --add safe.directory /etc/nixos

# Rebuild
nixos-rebuild switch --flake /etc/nixos#nixos-lxc
```

### 4. Set up Tailscale

```bash
tailscale up
# Open the URL it prints in your browser to authenticate
tailscale set --ssh --accept-risk=lose-ssh
```

You can now SSH in via Tailscale: `ssh jgordijn@<hostname>`

## Adding a New Host

### 1. Add to `flake.nix`

```nix
nixosConfigurations = {
  nixos-lxc = nixpkgs.lib.nixosSystem { ... };  # existing

  new-host = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      ./hosts/new-host/configuration.nix
      home-manager.nixosModules.home-manager
    ];
  };
};
```

### 2. Create host-specific config

```bash
mkdir -p hosts/new-host
# Create configuration.nix for the new host, importing shared modules:
#   imports = [
#     ./hardware-configuration.nix
#     ../../common/packages.nix
#   ];
```

### 3. Rebuild targeting the new host

```bash
sudo nixos-rebuild switch --flake /etc/nixos#new-host
```

## Key Concepts

| Layer | Scope | Examples |
|-------|-------|---------|
| `common/packages.nix` | System-wide, all machines | curl, jq, ripgrep, nil, nixfmt |
| `configuration.nix` | System-wide, this machine | boot, users, services, openssh |
| `home/common.nix` | Per-user, all machines | helix, git, fzf, zoxide, bat, eza |
| `home/nixos.nix` | Per-user, NixOS only | NixOS-specific user config |
| `home/darwin.nix` | Per-user, macOS only | macOS-specific user config |

### System packages vs Home-manager

- **System packages** (`environment.systemPackages`): Available to all users. Use for tools without per-user config.
- **Home-manager** (`programs.*.enable`): Per-user. Use for tools that have config (helix, git, fzf) — gives you shell integration and declarative config for free.

### NixOS LXC Specifics

- `boot.isContainer = true;` — disables kernel/bootloader management
- `boot.loader.grub.enable = false;` — no bootloader in containers
- Exit code 4 from `nixos-rebuild switch` is normal — it's `sys-kernel-debug.mount` failing, which is expected in LXC
