#!/usr/bin/env bash

# Alterna a visibilidade das janelas Picture-in-Picture do Firefox.
# A primeira vez tira o PiP da tela; a segunda devolve no workspace atual.

export PATH="$PATH:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin"

hidden_workspace="special:pip"
active_workspace="$(hyprctl -j activeworkspace | jq -r '.id')"

mapfile -t windows < <(hyprctl -j clients | jq -r --arg hidden "$hidden_workspace" '
    .[]
    | select(.title == "Picture-in-Picture")
    | [.address, (if .workspace.name == $hidden then "hidden" else "visible" end), (if .pinned then "1" else "0" end)]
    | @tsv
')

if [ "${#windows[@]}" -eq 0 ]; then
    exit 0
fi

action="hide"
for window in "${windows[@]}"; do
    state="${window#*$'\t'}"
    state="${state%%$'\t'*}"
    if [ "$state" = "visible" ]; then
        action="hide"
        break
    fi
    action="show"
done

for window in "${windows[@]}"; do
    address="${window%%$'\t'*}"
    rest="${window#*$'\t'}"
    pinned="${rest#*$'\t'}"

    if [ "$action" = "hide" ]; then
        if [ "$pinned" = "1" ]; then
            hyprctl dispatch pin "address:${address}" >/dev/null
        fi
        hyprctl dispatch movetoworkspacesilent "${hidden_workspace},address:${address}" >/dev/null
    else
        hyprctl dispatch movetoworkspacesilent "${active_workspace},address:${address}" >/dev/null
        hyprctl dispatch pin "address:${address}" >/dev/null
    fi
done
