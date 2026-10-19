{
  description = "DuckeOS - NixOS com Hyprland e Caelestia Shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell = {
      url = "github:outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    caelestia-shell = {
      url = "github:caelestia-dots/shell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.quickshell.follows = "quickshell";
    };
    caelestia-cli = {
      url = "github:caelestia-dots/cli";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.caelestia-shell.follows = "caelestia-shell";
    };
    apple-fonts = {
      url = "github:Lyndeno/apple-fonts.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Binário oficial do Firefox Nightly. A versão fica no flake.lock e só
    # avança com `nix flake update firefox-nightly` ou `rebuild -u`.
    firefox-nightly = {
      url = "github:nix-community/flake-firefox-nightly";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    agent-proxy = {
      url = "github:typedbywill/agent-proxy";
      flake = false;
    };
  };

  outputs = { nixpkgs, home-manager, ... }@inputs:
  let
    resolveLocalModule = name:
      let
        pwdPath = if builtins.getEnv "PWD" != "" then (/. + (builtins.getEnv "PWD") + "/${name}") else null;
        flakeDirPath = if builtins.getEnv "FLAKE_DIR" != "" then (/. + (builtins.getEnv "FLAKE_DIR") + "/${name}") else null;
        etcPath = /. + "/etc/nixos/${name}";
      in
        if builtins.pathExists (./. + "/${name}") then (./. + "/${name}")
        else if pwdPath != null && builtins.pathExists pwdPath then pwdPath
        else if flakeDirPath != null && builtins.pathExists flakeDirPath then flakeDirPath
        else if builtins.pathExists etcPath then etcPath
        else {};

    mkDuckeOS = nixpkgs.lib.nixosSystem {
      specialArgs = { inherit inputs; };
      modules = [
        ./configuration.nix
        (resolveLocalModule "hardware-configuration.nix")
        (resolveLocalModule "local-config.nix")
        home-manager.nixosModules.home-manager
        ({ config, lib, ... }: {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.backupFileExtension = "backup";
          home-manager.extraSpecialArgs = {
            inherit inputs;
            localSettings = config.ducke.local;
          };
          home-manager.users = lib.listToAttrs (map (account: {
            name = account.username;
            value = {
              imports = [ ./home.nix ];
              _module.args.duckeAccount = {
                primary = account.primary;
                extraPackages = account.extraPackages;
                excludePackages = account.excludePackages;
              };
              home.username = account.username;
              home.homeDirectory = account.homeDirectory;
            };
          }) config.ducke.local.accounts);
        })
      ];
    };
  in {
    nixosConfigurations = {
      # Existe um único sistema público. Identidade e hardware da máquina são
      # injetados pelos arquivos locais ignorados pelo Git acima.
      ducke = mkDuckeOS;
    };
  };
}
