{ config, pkgs, lib, inputs, localSettings, duckeAccount, ... }:

let
  chatgpt = pkgs.callPackage ./pkgs/chatgpt.nix {};
  grok-bot = pkgs.callPackage ./pkgs/grok-bot.nix {};
  winbox = pkgs.callPackage ./pkgs/winbox.nix {};
  mysql-workbench = pkgs.callPackage ./pkgs/mysql-workbench.nix {};
  # O tarball oficial é en-US. O seletor de idioma do Nightly não baixa o
  # pacote de língua porque o atualizador interno fica desligado. O pacote
  # correspondente à versão travada é instalado pela política do Firefox.
  firefoxNightlyBin = inputs.firefox-nightly.packages.${pkgs.stdenv.hostPlatform.system}.firefox-nightly-bin;
  firefoxLocale =
    let
      code = lib.head (lib.splitString "." localSettings.locale);
    in
    lib.replaceStrings [ "_" ] [ "-" ] code;
  firefoxMozSystem = {
    "x86_64-linux" = "linux-x86_64";
    "aarch64-linux" = "linux-aarch64";
  }.${pkgs.stdenv.hostPlatform.system};
  firefoxNeedsLangpack = !builtins.elem firefoxLocale [ "en-US" "en" "C" "POSIX" ];
  firefox-nightly = firefoxNightlyBin.override {
    extraPolicies = {
      DisableAppUpdate = true;
      RequestedLocales = [ firefoxLocale ];
    } // lib.optionalAttrs firefoxNeedsLangpack {
      ExtensionSettings = {
        "langpack-${firefoxLocale}@firefox.mozilla.org" = {
          installation_mode = "force_installed";
          install_url = "https://archive.mozilla.org/pub/firefox/nightly/latest-mozilla-central-l10n/${firefoxMozSystem}/xpi/firefox-${firefoxNightlyBin.version}.${firefoxLocale}.langpack.xpi";
        };
      };
    };
    extraPrefs = ''
      pref("intl.locale.requested", "${firefoxLocale}");
    '';
  };
in
{
  imports = [
    ./modules/spotify-inactivity-watcher.nix
  ];

  systemd.user.services.agent-proxy = {
    Unit = {
      Description = "Agent Proxy";
      After = [ "network.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "agent-proxy-service-runner" ''
        if [ -f "$HOME/Documents/projetos/pessoal/agent-proxy/src/server.js" ]; then
          exec ${pkgs.nodejs}/bin/node "$HOME/Documents/projetos/pessoal/agent-proxy/src/server.js"
        else
          exec ${pkgs.nodejs}/bin/node ${inputs.agent-proxy}/src/server.js
        fi
      '';
      Restart = "always";
      RestartSec = 3;
      Environment = [
        "NODE_ENV=production"
        "AGENT_PROXY_PORT=8080"
      ];
    };
    Install.WantedBy = [ "default.target" ];
  };

  home.stateVersion = "26.05";

  # Pacotes da área de trabalho. O mesmo conjunto vale para cada conta declarada.
  # duckeAccount.excludePackages usa estas chaves, por exemplo "spotify".
  home.packages =
    let
      basePackages = {
        chatgpt = chatgpt;
        grok-bot = grok-bot;
        mission-center = pkgs.mission-center;
        nwg-displays = pkgs.nwg-displays;
        firefox = firefox-nightly;
        google-chrome = pkgs.google-chrome;
        keepassxc = pkgs.keepassxc;
        vscode = pkgs.vscode;
        code-cursor = pkgs.code-cursor;
        syncthing = pkgs.syncthing;
        lmstudio = pkgs.lmstudio;
        spotify = pkgs.spotify;
        zapzap = pkgs.zapzap;
        telegram-desktop = pkgs.telegram-desktop;
        papirus-icon-theme = pkgs.papirus-icon-theme;
        papirus-folders = pkgs.papirus-folders;
        kora-icon-theme = pkgs.kora-icon-theme;
        whitesur-icon-theme = pkgs.whitesur-icon-theme;
        libreoffice-stable = pkgs.libreoffice-stable;
        hunspell = pkgs.hunspell;
        hunspell-pt-BR = pkgs.hunspellDicts.pt_BR;
        mysql-workbench = mysql-workbench;
        mongodb-compass = pkgs.mongodb-compass;
        postman = pkgs.postman;
        dolphin = pkgs.kdePackages.dolphin;
        breeze = pkgs.kdePackages.breeze;
        breeze-icons = pkgs.kdePackages.breeze-icons;
        qqc2-desktop-style = pkgs.kdePackages.qqc2-desktop-style;
        qtsvg = pkgs.kdePackages.qtsvg;
        kimageformats = pkgs.kdePackages.kimageformats;
        kio-extras = pkgs.kdePackages.kio-extras;
        kio-admin = pkgs.kdePackages.kio-admin;
        kdegraphics-thumbnailers = pkgs.kdePackages.kdegraphics-thumbnailers;
        ffmpegthumbs = pkgs.kdePackages.ffmpegthumbs;
        ark = pkgs.kdePackages.ark;
        gwenview = pkgs.kdePackages.gwenview;
        okular = pkgs.kdePackages.okular;
        mpv = pkgs.mpv;
        adw-gtk3 = pkgs.adw-gtk3;
        libnotify = pkgs.libnotify;
        nmap = pkgs.nmap;
        nodejs = pkgs.nodejs;
        pnpm = pkgs.pnpm;
        yarn = pkgs.yarn;
        bun = pkgs.bun;
        moonlight-qt = pkgs.moonlight-qt;
        rustdesk-flutter = pkgs.rustdesk-flutter;
        scrcpy = pkgs.scrcpy;
        winbox = winbox;
        socat = pkgs.socat;
        agent-proxy-server = pkgs.writeShellScriptBin "agent-proxy-server" ''
          if [ -f "$HOME/Documents/projetos/pessoal/agent-proxy/src/server.js" ]; then
            exec ${pkgs.nodejs}/bin/node "$HOME/Documents/projetos/pessoal/agent-proxy/src/server.js" "$@"
          else
            exec ${pkgs.nodejs}/bin/node ${inputs.agent-proxy}/src/server.js "$@"
          fi
        '';
        agent-proxy = pkgs.writeShellScriptBin "agent-proxy" ''
          if [ -f "$HOME/Documents/projetos/pessoal/agent-proxy/bin/agent-proxy" ]; then
            exec ${pkgs.bash}/bin/bash "$HOME/Documents/projetos/pessoal/agent-proxy/bin/agent-proxy" "$@"
          else
            exec ${pkgs.bash}/bin/bash ${inputs.agent-proxy}/bin/agent-proxy "$@"
          fi
        '';
        jq = pkgs.jq;
        xdg-user-dirs = pkgs.xdg-user-dirs;
        cliphist = pkgs.cliphist;
        wl-clipboard = pkgs.wl-clipboard;
        fuzzel = pkgs.fuzzel;
        libsecret = pkgs.libsecret;
      };
    in
    let
      accountChoices = import ./modules/account-choices.nix;
      missingChoices = lib.filter (name: !builtins.hasAttr name basePackages) accountChoices.excludePackages;
      unknownExcluded = lib.filter (name: !builtins.hasAttr name basePackages) duckeAccount.excludePackages;
    in
    if missingChoices != [ ] then
      throw "modules/account-choices.nix cita pacotes ausentes em home.nix: ${lib.concatStringsSep ", " missingChoices}"
    else if unknownExcluded != [ ] then
      throw "excludePackages desconhecido: ${lib.concatStringsSep ", " unknownExcluded}"
    else
      lib.attrValues (builtins.removeAttrs basePackages duckeAccount.excludePackages)
      ++ duckeAccount.extraPackages;

  xdg.desktopEntries.nwg-displays = {
    name = "Monitores";
    genericName = "Configuração de monitores";
    comment = "Ajuste a posição, resolução, escala e orientação das telas";
    exec = "${pkgs.nwg-displays}/bin/nwg-displays";
    icon = "nwg-displays";
    terminal = false;
    categories = [ "Settings" "HardwareSettings" ];
    settings.Keywords = "monitores;telas;resolução;escala;displays;monitors;resolution;scale;";
  };

  # Variáveis de sessão do usuário
  home.sessionVariables = {
    BROWSER = "firefox-nightly";
    DEFAULT_BROWSER = "${firefox-nightly}/bin/firefox-nightly";
    FILEMANAGER = "dolphin";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_WAYLAND_DISABLE_WINDOWDECORATION = "1";
    GTK_USE_PORTAL = "1";
    NIXOS_OZONE_WL = "1";
    ELECTRON_OZONE_PLATFORM_HINT = "auto";
  };

  # Configuração Qt para integração visual nativa com Caelestia
  qt = {
    enable = true;
    platformTheme.name = "kde";
    style.name = "breeze";
  };

  # Configuração GTK declarativa com Dark Mode harmonizado ao WhiteSur e Caelestia
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "WhiteSur-dark";
      package = pkgs.whitesur-icon-theme;
    };
    cursorTheme = {
      name = "Bibata-Modern-Ice";
      size = 24;
    };
    font = {
      name = "SF Pro Display";
      size = 11;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk4.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
    };
    gtk3.bookmarks = [
      "file://${config.home.homeDirectory}/Documents Documents"
      "file://${config.home.homeDirectory}/Downloads Downloads"
      "file://${config.home.homeDirectory}/Pictures Pictures"
      "file://${config.home.homeDirectory}/Music Music"
      "file://${config.home.homeDirectory}/Videos Videos"
      "file://${config.home.homeDirectory}/Projects Projects"
    ];
  };

  # Padronização de chaves dconf para o ecossistema GNOME / GTK
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      gtk-theme = "adw-gtk3-dark";
      icon-theme = "WhiteSur-dark";
      cursor-theme = "Bibata-Modern-Ice";
      cursor-size = 24;
      font-name = "SF Pro Display 11";
    };
  };

  # Associação de arquivos e protocolos para navegador, mídias e utilitários
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = "org.kde.dolphin.desktop";
      "text/html" = "firefox-nightly.desktop";
      "x-scheme-handler/http" = "firefox-nightly.desktop";
      "x-scheme-handler/https" = "firefox-nightly.desktop";
      "x-scheme-handler/about" = "firefox-nightly.desktop";
      "x-scheme-handler/unknown" = "firefox-nightly.desktop";

      # Visualizador de Imagens
      "image/png" = "org.kde.gwenview.desktop";
      "image/jpeg" = "org.kde.gwenview.desktop";
      "image/jpg" = "org.kde.gwenview.desktop";
      "image/gif" = "org.kde.gwenview.desktop";
      "image/webp" = "org.kde.gwenview.desktop";
      "image/bmp" = "org.kde.gwenview.desktop";
      "image/svg+xml" = "org.kde.gwenview.desktop";
      "image/tiff" = "org.kde.gwenview.desktop";

      # Reprodutor de Vídeo
      "video/mp4" = "mpv.desktop";
      "video/mkv" = "mpv.desktop";
      "video/x-matroska" = "mpv.desktop";
      "video/webm" = "mpv.desktop";
      "video/quicktime" = "mpv.desktop";
      "video/x-msvideo" = "mpv.desktop";
      "video/x-flv" = "mpv.desktop";

      # Documentos e PDFs
      "application/pdf" = "org.kde.okular.desktop";
      "application/epub+zip" = "org.kde.okular.desktop";

      # Arquivos Compactados
      "application/zip" = "org.kde.ark.desktop";
      "application/x-tar" = "org.kde.ark.desktop";
      "application/x-compressed-tar" = "org.kde.ark.desktop";
      "application/x-bzip-compressed-tar" = "org.kde.ark.desktop";
      "application/x-xz-compressed-tar" = "org.kde.ark.desktop";
      "application/x-7z-compressed" = "org.kde.ark.desktop";
      "application/x-rar" = "org.kde.ark.desktop";
    };
  };

  # Padronização declarativa de diretórios de usuário XDG
  xdg.userDirs = {
    enable = true;
    createDirectories = true;
    desktop = "${config.home.homeDirectory}/Desktop";
    documents = "${config.home.homeDirectory}/Documents";
    download = "${config.home.homeDirectory}/Downloads";
    music = "${config.home.homeDirectory}/Music";
    pictures = "${config.home.homeDirectory}/Pictures";
    videos = "${config.home.homeDirectory}/Videos";
    templates = "${config.home.homeDirectory}/Templates";
    publicShare = "${config.home.homeDirectory}/Public";
    extraConfig = {
      XDG_PROJECTS_DIR = "${config.home.homeDirectory}/Projects";
    };
  };

  # Serviço do Syncthing em segundo plano para o usuário
  services.syncthing = {
    enable = true;
  };



  xdg.configFile."hypr/hyprland.conf" = {
    force = true;
    text = builtins.replaceStrings
      [ "@DUCKE_MONITORS@" "@DUCKE_XKB_LAYOUT@" ]
      [ "source = ~/.config/hypr/monitors.conf" localSettings.xkbLayout ]
      (builtins.readFile ./dotfiles/hypr/hyprland.conf);
  };
  xdg.configFile."hypr/hyprlock.conf" = {
    force = true;
    text = builtins.replaceStrings
      [ "@DUCKE_LOCALE@" ]
      [ localSettings.locale ]
      (builtins.readFile ./dotfiles/hypr/hyprlock.conf);
  };
  # Desliga DPMS somente após um minuto de sessão bloqueada. `on-timeout` e
  # `on-resume` ficam no mesmo listener para a primeira entrada religar as telas.
  xdg.configFile."hypr/hypridle.conf".text = ''
    listener {
      timeout = 60
      condition_cmd = caelestia shell lock isLocked 2>/dev/null | grep -qx true
      on-timeout = hyprctl dispatch dpms off
      on-resume = hyprctl dispatch dpms on
    }
  '';
  xdg.configFile."hypr/scripts/lock-with-dpms.sh" = { source = ./dotfiles/hypr/scripts/lock-with-dpms.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/auto-virtual-display.sh" = { source = ./dotfiles/hypr/scripts/auto-virtual-display.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/workspace-compactor.sh" = { source = ./dotfiles/hypr/scripts/workspace-compactor.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/workspace.sh" = { source = ./dotfiles/hypr/scripts/workspace.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/move-windows.sh" = { source = ./dotfiles/hypr/scripts/move-windows.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/toggle-special.sh" = { source = ./dotfiles/hypr/scripts/toggle-special.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/cycle-workspace-window.sh" = { source = ./dotfiles/hypr/scripts/cycle-workspace-window.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/super-peek.sh" = { source = ./dotfiles/hypr/scripts/super-peek.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/cycle-audio-source.sh" = { source = ./dotfiles/hypr/scripts/cycle-audio-source.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/toggle-glass-shader.sh" = { source = ./dotfiles/hypr/scripts/toggle-glass-shader.sh; force = true; executable = true; };
  xdg.configFile."hypr/scripts/toggle-pip.sh" = { source = ./dotfiles/hypr/scripts/toggle-pip.sh; force = true; executable = true; };
  xdg.configFile."hypr/shaders/liquid_glass.frag" = { source = ./dotfiles/hypr/shaders/liquid_glass.frag; force = true; };
  xdg.configFile."kitty/kitty.conf" = { source = ./dotfiles/kitty/kitty.conf; force = true; };
  xdg.configFile."caelestia/cli.json" = { source = ./dotfiles/caelestia/cli.json; force = true; };
  xdg.configFile."caelestia/sync-kde.sh" = { source = ./dotfiles/caelestia/sync-kde.sh; force = true; executable = true; };
  xdg.configFile."fish/config.fish" = { source = ./dotfiles/fish/config.fish; force = true; };
  xdg.configFile."scripts/rebuild.sh" = { source = ./scripts/rebuild.sh; force = true; executable = true; };
  xdg.configFile."scripts/ducke-user.sh" = { source = ./scripts/ducke-user.sh; force = true; executable = true; };
  xdg.configFile."fastfetch/config.jsonc" = { source = ./dotfiles/fastfetch/config.jsonc; force = true; };
  xdg.configFile."fastfetch/tux.png" = { source = ./dotfiles/fastfetch/tux.png; force = true; };
  xdg.configFile."fastfetch/tux.txt" = { source = ./dotfiles/fastfetch/tux.txt; force = true; };
  xdg.configFile."fastfetch/glados.txt" = { source = ./dotfiles/fastfetch/glados.txt; force = true; };
  xdg.configFile."fastfetch/aperture.txt" = { source = ./dotfiles/fastfetch/aperture.txt; force = true; };
  xdg.configFile."cliphist/config" = { source = ./dotfiles/cliphist/config; force = true; };
  xdg.configFile."fuzzel/fuzzel.ini" = { source = ./dotfiles/fuzzel/fuzzel.ini; force = true; };
  xdg.configFile."cava/config" = { source = ./dotfiles/cava/config; force = true; };
  xdg.configFile."htop/htoprc" = { source = ./dotfiles/htop/htoprc; force = true; };
  xdg.configFile."dolphinrc" = { source = ./dotfiles/dolphin/dolphinrc; force = true; };
  xdg.configFile."wireplumber/wireplumber.conf.d/50-follow-default.conf" = { source = ./dotfiles/wireplumber/wireplumber.conf.d/50-follow-default.conf; force = true; };
  xdg.dataFile."kxmlgui5/dolphin/dolphinui.rc" = { source = ./dotfiles/dolphin/dolphinui.rc; force = true; };

  # A interface do shell grava este JSON. Um symlink do Home Manager aponta para
  # o Nix store (0444) e qualquer opção — formato do relógio, fontes, barra —
  # falha com "Failed to save config". O arquivo do repositório só semeia a
  # primeira cópia; o que for alterado na interface fica local e sobrevive ao rebuild.
  home.activation.ensureCaelestiaShellConfig =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      shell_file="${config.xdg.configHome}/caelestia/shell.json"
      if [ -L "$shell_file" ] || [ ! -e "$shell_file" ]; then
        run ${pkgs.coreutils}/bin/rm -f "$shell_file"
        run ${pkgs.coreutils}/bin/install -Dm644 \
          ${./dotfiles/caelestia/shell.json} \
          "$shell_file"
      else
        run ${pkgs.writeShellScript "caelestia-hide-lock-notifs" ''
          tmp=$(mktemp)
          ${pkgs.jq}/bin/jq '.lock = ((.lock // {}) + {hideNotifs: true})' "$1" > "$tmp"
          mv "$tmp" "$1"
        ''} "$shell_file"
      fi
    '';

  # Inicializa um arquivo local editável pelo nwg-displays sem sobrescrever os ajustes.
  home.activation.ensureHyprMonitors =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
      monitor_file="${config.xdg.configHome}/hypr/monitors.conf"
      if [ ! -e "$monitor_file" ] && [ ! -L "$monitor_file" ]; then
        run ${pkgs.coreutils}/bin/install -Dm644 \
          ${pkgs.writeText "hyprland-monitors.conf" localSettings.hyprlandMonitors} \
          "$monitor_file"
      fi
    '';

  # Sincronização automática do tema Caelestia para o KDE/Dolphin na ativação
  home.activation.syncKde = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD bash ${config.home.homeDirectory}/.config/caelestia/sync-kde.sh || true
  '';

  # Garante a existência do arquivo de esquema de cores para o Hyprland não falhar no boot
  home.activation.ensureHyprScheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SCHEME_DIR="${config.home.homeDirectory}/.config/hypr/scheme"
    SCHEME_FILE="$SCHEME_DIR/current.conf"
    mkdir -p "$SCHEME_DIR"
    if [ ! -f "$SCHEME_FILE" ]; then
      cp -f ${./dotfiles/hypr/scheme/default.conf} "$SCHEME_FILE" || true
    fi
  '';

  # Garante layout moderno e limpo para o Dolphin sem painéis sobrepostos
  home.activation.ensureDolphinState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    STATE_DIR="${config.home.homeDirectory}/.local/state"
    mkdir -p "$STATE_DIR"
    cat << 'EOF' > "$STATE_DIR/dolphinstaterc"
[FilterBar]
caseSensitive=false
filterMode=1

[State]
State=AAAA/wAAAAD9AAAAAwAAAAAAAAAAAAAAAPwCAAAAAvsAAAAUAHAAbABhAGMAZQBzAEQAbwBjAGsBAAAAAP////8AAAAeAP////sAAAAWAGYAbwBsAGQAZQByAHMARABvAGMAawAAAAAA/////wAAAB4A////AAAAAQAAAAAAAAAA/AIAAAAB+wAAABAAaQBuAGYAbwBEAG8AYwBrAAAAAAD/////AAAAHgD///8AAAADAAAAAAAAAAD8AQAAAAH7AAAAGAB0AGUAcgBtAGkAbgBhAGwARABvAGMAawAAAAAA/////wAAAFwA////AAAAAAAAAAAAAAAEAAAABAAAAAgAAAAI/AAAAAEAAAACAAAAAQAAABYAbQBhAGkAbgBUAG8AbwBsAEIAYQByAQAAAAD/////AAAAAAAAAAA=
EOF
  '';


  home.pointerCursor = {
    enable = true;
    gtk.enable = true;
    x11.enable = true;
    name = "Bibata-Modern-Ice";
    package = pkgs.bibata-cursors;
    size = 24;
  };

  # Configuração declarativa do Git com GNOME Keyring / Libsecret
  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    settings = {
      credential = {
        helper = "libsecret";
      };
    } // lib.optionalAttrs (duckeAccount.primary && localSettings.gitName != "" && localSettings.gitEmail != "") {
      user = {
        name = localSettings.gitName;
        email = localSettings.gitEmail;
      };
    };
  };

  # Permite que o Home Manager gerencie a si mesmo
  programs.home-manager.enable = true;
}
