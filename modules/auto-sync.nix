{ config, lib, pkgs, ... }:

let
  cfg = config.ducke.autoSync;
  local = config.ducke.local;
  autoSync = pkgs.writeShellApplication {
    name = "ducke-auto-sync";
    runtimeInputs = with pkgs; [ coreutils git gnugrep util-linux ];
    text = builtins.readFile ../scripts/auto-sync.sh;
  };
in
{
  options.ducke.autoSync = {
    enable = lib.mkEnableOption "sincronizacao e rebuild automaticos do DuckeOS";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "15min";
      description = "Intervalo entre consultas ao repositorio remoto.";
    };

    randomizedDelay = lib.mkOption {
      type = lib.types.str;
      default = "2min";
      description = "Atraso aleatorio maximo aplicado a cada consulta.";
    };

    branch = lib.mkOption {
      type = lib.types.str;
      default = "main";
      description = "Branch remoto acompanhado pelo servico.";
    };

    action = lib.mkOption {
      type = lib.types.enum [ "switch" "boot" ];
      default = "switch";
      description = "Acao usada pelo nixos-rebuild apos uma atualizacao.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.ducke-auto-sync = {
      description = "Sincronizar e aplicar atualizacoes do DuckeOS";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        StateDirectory = "ducke-auto-sync";
        ExecStart = lib.concatStringsSep " " ([
          "${autoSync}/bin/ducke-auto-sync"
        ] ++ map lib.escapeShellArg [
          local.repositoryDirectory
          local.username
          local.homeDirectory
          cfg.branch
          cfg.action
          "${pkgs.nixos-rebuild}/bin/nixos-rebuild"
        ]);
      };
    };

    systemd.timers.ducke-auto-sync = {
      description = "Verificar atualizacoes do DuckeOS periodicamente";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = cfg.interval;
        RandomizedDelaySec = cfg.randomizedDelay;
        Persistent = true;
        Unit = "ducke-auto-sync.service";
      };
    };
  };
}
