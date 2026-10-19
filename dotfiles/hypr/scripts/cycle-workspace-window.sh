#!/usr/bin/env bash

# Circula o foco entre as janelas do workspace atual. Se a janela atual estiver
# maximizada ou em tela cheia, a próxima recebe o mesmo modo.

export PATH="$PATH:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin"

direction="${1:-next}"
state=$(hyprctl activewindow -j 2>/dev/null | jq -r '.fullscreen // 0')

if ! [[ "$state" =~ ^[0-9]+$ ]]; then
    state=0
fi

if [ "$state" != "0" ]; then
    hyprctl dispatch fullscreenstate 0 0 >/dev/null
fi

if [ "$direction" = "prev" ]; then
    hyprctl dispatch cyclenext prev >/dev/null
else
    hyprctl dispatch cyclenext >/dev/null
fi

if [ "$state" != "0" ]; then
    hyprctl dispatch fullscreenstate "$state" "$state" >/dev/null
fi
