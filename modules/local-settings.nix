{ config, lib, pkgs, ... }:

let
  cfg = config.ducke.local;
  accountChoices = import ./account-choices.nix;
  allowedGroupNames = map (group: group.name) accountChoices.groups;

  # Mesma ordem de flake.nix: o JSON fica fora do repositório publicado.
  # O flake ignora arquivos locais, então a cópia na Nix Store não o contém.
  resolveUsersFile =
    let
      name = "local-users.json";
      pwd = builtins.getEnv "PWD";
      flakeDir = builtins.getEnv "FLAKE_DIR";
      pwdPath = if pwd != "" then /. + pwd + "/${name}" else null;
      flakePath = if flakeDir != "" then /. + flakeDir + "/${name}" else null;
      etcPath = /. + "/etc/nixos/${name}";
      repoPath = ../. + "/${name}";
    in
      if builtins.pathExists repoPath then repoPath
      else if pwdPath != null && builtins.pathExists pwdPath then pwdPath
      else if flakePath != null && builtins.pathExists flakePath then flakePath
      else if builtins.pathExists etcPath then etcPath
      else null;

  usersFile = resolveUsersFile;
  usersFromFile =
    if usersFile == null then [ ]
    else
      let
        data = builtins.fromJSON (builtins.readFile usersFile);
      in
        if builtins.isList data then data else data.users or [ ];

  normalizePasswordFile = user:
    if user.passwordFile == null || user.passwordFile == "" then null
    else user.passwordFile;

  normalizeExtra = user: {
    username = user.username;
    fullName = if user.fullName == "" then user.username else user.fullName;
    homeDirectory = if user.homeDirectory == "" then "/home/${user.username}" else user.homeDirectory;
    primary = false;
    extraPackages = map (name: pkgs.${name}) user.extraPackages;
    excludePackages = user.excludePackages;
    extraGroups = user.extraGroups;
    passwordless = user.passwordless;
    passwordFile = normalizePasswordFile user;
  };
in
{
  options.ducke.local = {
    configured = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Confirma que local-config.nix foi criado e revisado nesta máquina";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "user";
      description = "Nome da conta local; deve ser sobrescrito em local-config.nix";
    };

    fullName = lib.mkOption {
      type = lib.types.str;
      default = "Local User";
      description = "Nome de exibição da conta local";
    };

    homeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/user";
      description = "Diretório home da conta local";
    };

    repositoryDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/home/user/ducke";
      description = "Diretório local do checkout DuckeOS";
    };

    gitName = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Nome do autor Git, mantido somente na configuração local";
    };

    gitEmail = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "E-mail do autor Git, mantido somente na configuração local";
    };

    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      description = "Fuso horário desta instalação";
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "pt_BR.UTF-8";
      description = "Locale principal desta instalação";
    };

    xkbLayout = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "Layout XKB usado no sistema e no Hyprland";
    };

    consoleKeyMap = lib.mkOption {
      type = lib.types.str;
      default = "us";
      description = "Mapa de teclado dos consoles virtuais";
    };

    hyprlandMonitors = lib.mkOption {
      type = lib.types.lines;
      default = "monitor = ,preferred,auto,1";
      description = "Configuração local de monitores e workspaces do Hyprland";
    };

    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Programas adicionais só da conta principal, declarados em local-config.nix";
    };

    excludePackages = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Chaves de home.nix removidas só da conta principal";
    };

    users = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          username = lib.mkOption {
            type = lib.types.str;
            description = "Nome Unix da conta adicional";
          };
          fullName = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Nome de exibição. Vazio repete o username.";
          };
          homeDirectory = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Home da conta. Vazio usa /home/<username>.";
          };
          extraPackages = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Nomes de pacotes Nix acrescentados só nesta conta, por exemplo obsidian";
          };
          excludePackages = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Chaves de home.nix removidas só nesta conta";
          };
          extraGroups = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Grupos além de input e uinput. Inclua networkmanager para permitir editar a rede.";
          };
          passwordless = lib.mkOption {
            type = lib.types.bool;
            default = false;
            description = "Entra no SDDM sem digitar senha. SSH, su e sudo continuam sem aceitar isso.";
          };
          passwordFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Arquivo com o hash da senha, fora da Nix Store. Nulo quando não há senha gravada.";
          };
        };
      });
      default = usersFromFile;
      description = "Contas adicionais desta máquina. O comando ducke user grava local-users.json.";
    };

    accounts = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      internal = true;
      description = "Conta principal seguida das contas adicionais.";
    };
  };

  config.ducke.local.accounts = [
    {
      username = cfg.username;
      fullName = cfg.fullName;
      homeDirectory = cfg.homeDirectory;
      primary = true;
      extraPackages = cfg.extraPackages;
      excludePackages = cfg.excludePackages;
      extraGroups = [ ];
      passwordless = false;
      passwordFile = null;
    }
  ] ++ map normalizeExtra cfg.users;

  config.assertions = [
    {
      assertion = config.ducke.local.configured;
      message = "Crie local-config.nix a partir de local-config.example.nix antes de aplicar o DuckeOS.";
    }
    {
      assertion = builtins.match "[a-z_][a-z0-9_-]*" config.ducke.local.username != null;
      message = "ducke.local.username não é um nome de usuário Unix válido.";
    }
    {
      assertion = lib.hasPrefix "/" config.ducke.local.homeDirectory;
      message = "ducke.local.homeDirectory precisa ser um caminho absoluto.";
    }
    {
      assertion = lib.hasPrefix "/" config.ducke.local.repositoryDirectory;
      message = "ducke.local.repositoryDirectory precisa ser um caminho absoluto.";
    }
    {
      assertion = (config.ducke.local.gitName == "") == (config.ducke.local.gitEmail == "");
      message = "Defina ducke.local.gitName e gitEmail juntos, ou deixe ambos vazios.";
    }
    {
      assertion = lib.all (user: builtins.match "[a-z_][a-z0-9_-]*" user.username != null) cfg.users;
      message = "Cada ducke.local.users.username precisa ser um nome de usuário Unix válido.";
    }
    {
      assertion = lib.length (lib.unique (map (user: user.username) cfg.accounts)) == lib.length cfg.accounts;
      message = "Há nomes de usuário repetidos entre a conta principal e ducke.local.users.";
    }
    {
      assertion = lib.all (user: lib.hasPrefix "/" user.homeDirectory) cfg.accounts;
      message = "Cada conta precisa de um homeDirectory absoluto.";
    }
    {
      assertion = lib.all (user:
        lib.all (name: builtins.hasAttr name pkgs) user.extraPackages
      ) cfg.users;
      message = "Cada extraPackages de ducke.local.users precisa ser um nome de pacote do Nixpkgs, por exemplo obsidian.";
    }
    {
      assertion = lib.all (user:
        lib.all (group: lib.elem group allowedGroupNames) user.extraGroups
      ) cfg.users;
      message = "Grupo desconhecido em ducke.local.users. Os grupos aceitos são: ${lib.concatStringsSep ", " allowedGroupNames}.";
    }
    {
      assertion = lib.all (user:
        !(user.passwordless && normalizePasswordFile user != null)
      ) cfg.users;
      message = "Uma conta não pode entrar sem senha e ao mesmo tempo apontar para um arquivo de senha.";
    }
    {
      assertion = lib.all (user:
        let
          file = normalizePasswordFile user;
        in
          file == null || lib.hasPrefix "/var/lib/duckeos/passwords/" file
      ) cfg.users;
      message = "passwordFile precisa ficar em /var/lib/duckeos/passwords/.";
    }
  ];
}
