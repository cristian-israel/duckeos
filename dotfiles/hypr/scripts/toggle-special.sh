#!/usr/bin/env bash

# ==============================================================================
# Toggle Special Workspace & Application Launcher for Hyprland
# 
# Permite abrir / alternar workspaces especiais (ex: communication, music, passwords),
# iniciando o aplicativo automaticamente caso não esteja aberto.
# ==============================================================================

export PATH="$PATH:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin"

WORKSPACE="$1"
shift

if [ -z "$WORKSPACE" ] || [ $# -lt 2 ] || [ $(($# % 2)) -ne 0 ]; then
    echo "Uso: $0 <nome_workspace> <regex_classe> <comando_launch> [<regex_classe> <comando_launch> ...]"
    exit 1
fi

run_app() {
    if command -v uwsm >/dev/null 2>&1; then
        uwsm app -- "$@"
    else
        "$@" &
    fi
}

# 1. Verifica se o workspace especial já está visível e focado no monitor atual
MONITORS_JSON=$(hyprctl -j monitors 2>/dev/null)
CURRENT_SPECIAL=$(echo "$MONITORS_JSON" | jq -r '.[] | select(.focused == true) | .specialWorkspace.name // ""')

if [ "$CURRENT_SPECIAL" = "special:$WORKSPACE" ]; then
    # Se já estiver aberto no monitor atual, fecha (toggle)
    hyprctl dispatch togglespecialworkspace "$WORKSPACE"
    exit 0
fi

# 2. Separa o ZapZap para ele abrir antes e permanecer à esquerda.
CLIENTS_JSON=$(hyprctl -j clients 2>/dev/null)
ZAP_CLASS='^(zapzap|com\.rtosta\.zapzap)$'
zap_regex=""
zap_cmd=""
rest=()
while [ $# -ge 2 ]; do
    CLASS_REGEX="$1"
    LAUNCH_CMD="$2"
    shift 2
    if echo "zapzap" | grep -Eq "$CLASS_REGEX"; then
        zap_regex="$CLASS_REGEX"
        zap_cmd="$LAUNCH_CMD"
    else
        rest+=("$CLASS_REGEX" "$LAUNCH_CMD")
    fi
done

window_address() {
    hyprctl -j clients 2>/dev/null | jq -r --arg pat "$1" '[.[] | select(.class | test($pat; "i"))][0].address // empty'
}

launch_if_missing() {
    local class_regex="$1"
    local launch_cmd="$2"
    local has_window
    has_window=$(echo "$CLIENTS_JSON" | jq -r --arg pat "$class_regex" '[.[] | select(.class | test($pat; "i"))] | length')
    if [ "$has_window" = "0" ] || [ -z "$has_window" ]; then
        eval "run_app $launch_cmd" >/dev/null 2>&1 &
        local _ address
        for _ in $(seq 1 50); do
            address=$(window_address "$class_regex")
            if [ -n "$address" ]; then
                return 0
            fi
            sleep 0.1
        done
    fi
}

# Se alguma janela do atalho já existe, só mostra o que está aberto.
# Os aplicativos são iniciados apenas quando a gaveta está vazia.
has_any=0
if [ -n "$zap_regex" ]; then
    zap_open=$(echo "$CLIENTS_JSON" | jq -r --arg pat "$zap_regex" '[.[] | select(.class | test($pat; "i"))] | length')
    if [ "${zap_open:-0}" != "0" ]; then
        has_any=1
    fi
fi
index=0
while [ "$index" -lt "${#rest[@]}" ]; do
    open_count=$(echo "$CLIENTS_JSON" | jq -r --arg pat "${rest[$index]}" '[.[] | select(.class | test($pat; "i"))] | length')
    if [ "${open_count:-0}" != "0" ]; then
        has_any=1
    fi
    index=$((index + 2))
done

if [ "$has_any" = "0" ]; then
    if [ -n "$zap_cmd" ]; then
        launch_if_missing "$zap_regex" "$zap_cmd"
    fi

    index=0
    while [ "$index" -lt "${#rest[@]}" ]; do
        launch_if_missing "${rest[$index]}" "${rest[$((index + 1))]}"
        index=$((index + 2))
    done
fi

# 3. Abre o workspace especial no monitor focado
hyprctl dispatch togglespecialworkspace "$WORKSPACE"

# O Telegram chega depois e empurra o ZapZap. Devolve o ZapZap para a esquerda.
if [ -n "$zap_cmd" ]; then
    for _ in $(seq 1 4); do
        clients=$(hyprctl -j clients 2>/dev/null)
        read -r zap_address zap_ws zap_x <<EOF
$(echo "$clients" | jq -r --arg pat "$ZAP_CLASS" '[.[] | select(.class | test($pat; "i"))][0] | select(.address) | "\(.address) \(.workspace.id) \(.at[0])"')
EOF
        [ -z "$zap_address" ] && break
        needs_swap=$(echo "$clients" | jq -r --arg addr "$zap_address" --argjson ws "$zap_ws" --argjson x "$zap_x" 'any(.[]; .address != $addr and .workspace.id == $ws and .at[0] < $x)')
        hyprctl dispatch focuswindow "address:$zap_address" >/dev/null
        if [ "$needs_swap" != "true" ]; then
            break
        fi
        hyprctl dispatch swapwindow l >/dev/null
        sleep 0.05
    done
fi
