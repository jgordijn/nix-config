{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    curl
    jq
    nil
    nixd
    nixfmt
    ripgrep
    tailscale
    wget
  ];
}
