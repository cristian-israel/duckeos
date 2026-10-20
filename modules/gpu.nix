{ config, lib, pkgs, ... }:

let
  cfg = config.myHardware.gpu;
  isNvidia = cfg.type == "nvidia" || cfg.type == "hybrid-intel-nvidia";

  # Ordem de DRM para Aquamarine/Hyprland. O primeiro dispositivo é o primário.
  # Em NVIDIA pura: só o dGPU. Em Optimus: iGPU primeiro (painel interno).
  defaultAqDrmDevices =
    if cfg.type == "nvidia" then "/dev/dri/nvidia-card"
    else if cfg.type == "hybrid-intel-nvidia" then "/dev/dri/intel-card:/dev/dri/nvidia-card"
    else if cfg.type == "amd" then "/dev/dri/amd-card"
    else if cfg.type == "intel" then "/dev/dri/intel-card"
    else null;
in
{
  options.myHardware.gpu = {
    type = lib.mkOption {
      type = lib.types.enum [ "intel" "nvidia" "hybrid-intel-nvidia" "amd" "none" ];
      default = "none";
      description = "Tipo de GPU da máquina: 'intel', 'nvidia', 'hybrid-intel-nvidia', 'amd', ou 'none'";
    };
    nvidia = {
      enableContainerToolkit = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Habilitar Nvidia Container Toolkit (CDI) para Docker quando a GPU Nvidia estiver ativa";
      };
      open = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Usar módulo de kernel open-source da NVIDIA.
          Mantenha false em Turing e anteriores (ex.: RTX 1650); o módulo aberto
          é mais confiável a partir de Ampere (RTX 30xx+) com drivers recentes.
        '';
      };
    };
    aqDrmDevices = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = defaultAqDrmDevices;
      description = "Ordem de prioridade de GPUs para Aquamarine/Hyprland (AQ_DRM_DEVICES)";
    };
  };

  config = lib.mkMerge [
    # Aceleração gráfica base
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = true;
      };

      # Symlinks previsíveis e sem ':' para GPUs (evita conflito de parsing no Aquamarine/Hyprland)
      services.udev.extraRules = ''
        KERNEL=="card*", SUBSYSTEM=="drm", ATTRS{vendor}=="0x10de", SYMLINK+="dri/nvidia-card"
        KERNEL=="card*", SUBSYSTEM=="drm", ATTRS{vendor}=="0x1002", SYMLINK+="dri/amd-card"
        KERNEL=="card*", SUBSYSTEM=="drm", ATTRS{vendor}=="0x8086", SYMLINK+="dri/intel-card"
      '';
    }

    # Configuração Intel
    (lib.mkIf (cfg.type == "intel" || cfg.type == "hybrid-intel-nvidia") {
      hardware.graphics.extraPackages = with pkgs; [
        intel-media-driver
        vpl-gpu-rt
      ];
    })

    # Configuração NVIDIA
    (lib.mkIf isNvidia {
      services.xserver.videoDrivers = [ "nvidia" ];

      # Em desktop só-NVIDIA, o greeter Wayland do SDDM costuma falhar (tela
      # congelada em "Reached target Graphical Interface"). X11 no SDDM +
      # sessão Hyprland Wayland é a combinação estável para Turing/Ampere.
      services.displayManager.sddm.wayland.enable =
        lib.mkIf (cfg.type == "nvidia") (lib.mkForce false);

      hardware.nvidia = {
        modesetting.enable = true;
        powerManagement.enable = false;
        powerManagement.finegrained = false;
        open = cfg.nvidia.open;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;
      };

      # fbdev=1 evita console de texto “preso” após graphical.target com drivers
      # recentes (necessário em várias RTX 16xx / 20xx no Wayland).
      boot.kernelParams = [ "nvidia-drm.fbdev=1" ];

      hardware.nvidia-container-toolkit.enable = cfg.nvidia.enableContainerToolkit;

      # O módulo registra os dispositivos NVIDIA; este helper privilegiado cria
      # os nós /dev/nvidia* necessários para CUDA e nvidia-smi.
      environment.systemPackages = [ pkgs.nvidia-modprobe ];
      security.wrappers.nvidia-modprobe = {
        source = "${pkgs.nvidia-modprobe}/bin/nvidia-modprobe";
        owner = "root";
        group = "root";
        setuid = true;
      };

      # O wrapper é útil para ferramentas em sessão gráfica, mas a criação dos
      # nós precisa ocorrer como root logo após os módulos do kernel carregarem.
      systemd.services.nvidia-device-nodes = {
        description = "Criar nós de dispositivo da NVIDIA";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-modules-load.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.nvidia-modprobe}/bin/nvidia-modprobe -u -c=0";
        };
      };

      environment.sessionVariables = {
        LIBVA_DRIVER_NAME = "nvidia";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        GBM_BACKEND = "nvidia-drm";
        NVD_BACKEND = "direct";
      };
    })

    # Configuração AMD
    (lib.mkIf (cfg.type == "amd") {
      services.xserver.videoDrivers = [ "amdgpu" ];
      hardware.graphics.extraPackages = with pkgs; [
        amdvlk
      ];
      hardware.graphics.extraPackages32 = with pkgs; [
        driversi686Linux.amdvlk
      ];
    })

    # Prioridade de GPUs para Aquamarine/Hyprland
    (lib.mkIf (cfg.aqDrmDevices != null) {
      environment.sessionVariables = {
        AQ_DRM_DEVICES = cfg.aqDrmDevices;
      };
    })
  ];
}
