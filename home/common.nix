{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    history = {
      size = 10000;
      save = 10000;
    };
    autocd = true;
  };

  programs.helix = {
    enable = true;
    languages.language = [{
      name = "nix";
      auto-format = true;
      formatter.command = "nixfmt";
    }];
  };

  programs.git = {
    enable = true;
    userName = "Jeroen Gordijn";
    userEmail = "jeroen.gordijn@gmail.com";

    signing = {
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBSSGbehh9Y6I9DSejnaNUGhXkinx3QT66NLtsUu/H1n";
      signByDefault = true;
      format = "ssh";
    };

    delta = {
      enable = true;
      options = {
        navigate = true;
        light = false;
        diff-so-fancy = true;
      };
    };

    aliases = {
      st = "status";
      ci = "commit";
      br = "branch";
      co = "checkout";
      df = "diff";
      lg = "log -p";
      glog = "log --graph";
      mt = "mergetool";
      ls = ''log --pretty=format:"%C(yellow)%h%Cred%d\\ %Creset%s%Cblue\\ [%cn]" --decorate'';
      ll = ''log --pretty=format:"%C(yellow)%h%Cred%d\\ %Creset%s%Cblue\\ [%cn]" --decorate --numstat'';
      lnc = ''log --pretty=format:"%h\\ %s\\ [%cn]"'';
      lds = ''log --pretty=format:"%C(yellow)%h\\ %ad%Cred%d\\ %Creset%s%Cblue\\ [%cn]" --decorate --date=short'';
      ld = ''log --pretty=format:"%C(yellow)%h\\ %ad%Cred%d\\ %Creset%s%Cblue\\ [%cn]" --decorate --date=relative'';
      le = "log --oneline --decorate";
    };

    extraConfig = {
      credential.username = "jgordijn";
      color = {
        ui = "auto";
        status = "auto";
        branch = "auto";
        diff = "auto";
      };
      "color \"branch\"" = {
        current = "green reverse";
        local = "green";
        remote = "red";
      };
      "color \"diff\"" = {
        meta = "yellow bold";
        frag = "magenta bold";
        old = "red bold";
        new = "green bold";
        whitespace = "red reverse";
      };
      "color \"status\"" = {
        added = "yellow";
        changed = "green";
        untracked = "cyan";
      };
      core = {
        whitespace = "fix,-indent-with-non-tab,trailing-space,cr-at-eol";
        autocrlf = "input";
      };
      push.default = "simple";
      merge.conflictstyle = "diff3";
      diff.colorMoved = "default";
      init.defaultBranch = "main";
      tag.gpgSign = true;
    };

    ignores = [
      # OS generated
      ".DS_Store"
      ".DS_Store?"
      "._*"
      ".Spotlight-V100"
      ".Trashes"
      "Thumbs.db"
      "ehthumbs.db"
      "desktop.ini"
      "*~"

      # Editors
      ".idea/"
      ".idea*"
      "*.iml"
      "*.ipr"
      "*.iws"
      ".vscode"
      "*.code-workspace"

      # Compiled
      "*.com"
      "*.class"
      "*.dll"
      "*.exe"
      "*.o"
      "*.so"

      # Packages
      "*.7z"
      "*.dmg"
      "*.gz"
      "*.iso"
      "*.jar"
      "*.rar"
      "*.tar"
      "*.zip"

      # Logs and databases
      "*.log"
      "*.sqlite"

      # Build
      ".gradle"
      "target/*"
      "*/target/*"
      "build/"
      "dist/*"
      "classes/*"
      "bin"

      # Environment
      ".env"
      ".env-*"
      ".env-localhost"
      "venv"
      ".envrc"

      # Metals / Scala
      ".bloop"
      ".metals"
      "project/metals.sbt"

      # Tools
      ".tool-versions"
      "*.dtmp"
      "*.patch"
      "*.local.md"

      # direnv
      ".direnv"
    ];
  };

  programs.gh = {
    enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.bat.enable = true;

  programs.eza.enable = true;

  programs.fd.enable = true;

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };
}
