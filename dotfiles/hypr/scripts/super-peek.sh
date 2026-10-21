#!/usr/bin/env bash

# Dois toques em Super, com a janela em tela cheia, mostram o workspace.
# O clique escolhe outra janela e devolve o mesmo modo de tela cheia a ela.
# Escape, outro toque em Super ou um clique na janela original restauram essa.

export PATH="$PATH:/run/current-system/sw/bin:$HOME/.nix-profile/bin:/etc/profiles/per-user/$USER/bin"

action="${1:-tap}"
runtime="${XDG_RUNTIME_DIR:-/tmp}/duckeos"
mkdir -p "$runtime"
stamp="$runtime/super-tap"
state="$runtime/super-peek"
lock="$runtime/super-peek.lock"
double_tap_ms=320

read_state() {
    addr=""
    fullscreen=""
    workspace=""
    [[ -f "$state" ]] || return 1
    {
        IFS= read -r addr
        IFS= read -r fullscreen
        IFS= read -r workspace
    } < "$state"
    [[ "$addr" == 0x* && "$fullscreen" =~ ^[123]$ && "$workspace" =~ ^-?[0-9]+$ ]]
}

window_exists() {
    hyprctl clients -j 2>/dev/null | jq -e --arg address "$1" 'any(.[]; .address == $address)' >/dev/null
}

clear_peek() {
    hyprctl keyword input:follow_mouse 1 >/dev/null 2>&1 || true
    hyprctl dispatch submap reset >/dev/null 2>&1 || true
    rm -f "$state"
}

restore_original() {
    if window_exists "$addr"; then
        hyprctl dispatch focuswindow "address:$addr" >/dev/null
        hyprctl dispatch fullscreenstate "$fullscreen" "$fullscreen" >/dev/null
    fi
}

finish() {
    local chosen_addr chosen_ws cursor_x cursor_y lock_fd
    exec {lock_fd}>>"$lock"
    flock -n "$lock_fd" || return 0
    if ! read_state; then
        clear_peek
        return 0
    fi

    if [ "$1" = "click" ]; then
        chosen_addr=""
        chosen_ws=""
        local _try
        for _try in 1 2 3 4 5 6 7 8; do
            IFS=$'\t' read -r chosen_addr chosen_ws < <(hyprctl activewindow -j 2>/dev/null | jq -r '[.address // "", (.workspace.id | tostring)] | @tsv' 2>/dev/null || true)
            if [ -n "$chosen_addr" ] && [ "$chosen_addr" != "$addr" ]; then
                break
            fi
            sleep 0.02
        done

        if [ -z "$chosen_addr" ] || [ "$chosen_addr" = "$addr" ]; then
            IFS=',' read -r cursor_x cursor_y < <(hyprctl cursorpos 2>/dev/null || true)
            cursor_x=${cursor_x// /}
            cursor_y=${cursor_y// /}
            chosen_addr=""
            if [[ "$cursor_x" =~ ^-?[0-9]+$ && "$cursor_y" =~ ^-?[0-9]+$ ]]; then
                chosen_addr=$(hyprctl clients -j 2>/dev/null | jq -r --argjson x "$cursor_x" --argjson y "$cursor_y" --argjson ws "$workspace" '
                    [ .[] | select(
                        .workspace.id == $ws
                        and (.mapped // true)
                        and .at[0] <= $x and $x < (.at[0] + .size[0])
                        and .at[1] <= $y and $y < (.at[1] + .size[1])
                    ) ] | sort_by(.size[0] * .size[1]) | .[0].address // empty
                ' 2>/dev/null || true)
            fi
            chosen_ws="$workspace"
        fi

        if [ -n "$chosen_addr" ] && [ "$chosen_addr" != "$addr" ] && [ "$chosen_ws" = "$workspace" ] && window_exists "$chosen_addr"; then
            hyprctl dispatch focuswindow "address:$chosen_addr" >/dev/null
            hyprctl dispatch fullscreenstate "$fullscreen" "$fullscreen" >/dev/null
            clear_peek
            return 0
        fi
    fi

    restore_original
    clear_peek
}

start_peek() {
    local active fullscreen_now workspace_now address_now count
    active=$(hyprctl activewindow -j 2>/dev/null || true)
    fullscreen_now=$(printf '%s' "$active" | jq -r '.fullscreen // 0' 2>/dev/null || echo 0)
    address_now=$(printf '%s' "$active" | jq -r '.address // empty' 2>/dev/null || true)
    workspace_now=$(printf '%s' "$active" | jq -r '.workspace.id // empty' 2>/dev/null || true)

    if ! [[ "$fullscreen_now" =~ ^[123]$ && "$address_now" == 0x* && "$workspace_now" =~ ^-?[0-9]+$ ]]; then
        return 0
    fi

    count=$(hyprctl clients -j 2>/dev/null | jq --argjson ws "$workspace_now" '[.[] | select(.workspace.id == $ws and (.mapped // true))] | length' 2>/dev/null || echo 0)
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -lt 2 ]; then
        return 0
    fi

    printf '%s\n%s\n%s\n' "$address_now" "$fullscreen_now" "$workspace_now" > "$state"
    hyprctl keyword input:follow_mouse 0 >/dev/null
    hyprctl dispatch fullscreenstate 0 0 >/dev/null
    hyprctl dispatch submap peek >/dev/null
}

case "$action" in
    tap)
        if [ -f "$state" ]; then
            finish cancel
            exit 0
        fi

        now=$(date +%s%3N)
        if [ -f "$stamp" ]; then
            last=$(<"$stamp")
            if [[ "$last" =~ ^[0-9]+$ ]] && (( now - last <= double_tap_ms && now - last >= 0 )); then
                rm -f "$stamp"
                start_peek
                exit 0
            fi
        fi
        printf '%s\n' "$now" > "$stamp"
        ;;
    click)
        finish click
        ;;
    cancel)
        finish cancel
        ;;
esac
