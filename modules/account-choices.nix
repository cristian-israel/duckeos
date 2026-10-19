# Opções que `ducke user` oferece no terminal.
# Os nomes de excludePackages precisam existir como chaves de basePackages em home.nix.
{
  groups = [
    { name = "wheel"; description = "sudo"; }
    { name = "networkmanager"; description = "ligar, desligar e editar a rede"; }
    { name = "docker"; description = "Docker"; }
    { name = "libvirtd"; description = "máquinas virtuais"; }
    { name = "kvm"; description = "KVM"; }
    { name = "i2c"; description = "barramento i2c"; }
  ];

  excludePackages = [
    "chatgpt"
    "grok-bot"
    "mission-center"
    "firefox"
    "google-chrome"
    "keepassxc"
    "vscode"
    "code-cursor"
    "syncthing"
    "lmstudio"
    "spotify"
    "zapzap"
    "telegram-desktop"
    "libreoffice-stable"
    "mysql-workbench"
    "mongodb-compass"
    "postman"
    "dolphin"
    "gwenview"
    "okular"
    "mpv"
    "nmap"
    "moonlight-qt"
    "rustdesk-flutter"
    "scrcpy"
    "winbox"
  ];
}
