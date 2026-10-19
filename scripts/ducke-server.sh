#!/usr/bin/env bash
# Servidores SSH desta máquina. O registro fica fora do Git.
set -euo pipefail

STORE_DIR="/var/lib/ducke-srv"
SERVERS_JSON="$STORE_DIR/servers.json"
YES=0

die() {
    echo "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Uso: ducke srv [comando] [apelido] [painéis]

Sem comando, abre o painel para escolher um servidor.
O comando é ducke srv. srv sozinho não existe.

Comandos:
  -l                         Lista os servidores
  add [apelido]              Cadastra um servidor
  edit <apelido>             Altera endereço, usuário ou painéis
  remove <apelido>           Encerra a sessão desta conta e apaga o registro
  close <apelido>            Encerra a sessão desta conta
  close --all                Encerra todas as sessões desta conta
  pane                       Abre outro terminal na sessão atual

  ducke srv api              Abre ou reanexa o servidor
  ducke srv api 2            Na próxima sessão nova, abre dois painéis

Flags de add e edit:
  --host ENDEREÇO            Nome Tailscale, IPv4 ou IPv6
  --user USUÁRIO             Usuário remoto
  --panes N                  De 1 a 12. O padrão é 4
  --yes                      Não pede confirmação no remove

A senha não entra no comando nem no registro. Ela é digitada no primeiro painel.
Só a conta principal, ou root, cadastra, edita e apaga.
EOF
}

if [ -z "${REPO_DIR:-}" ]; then
    SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)"
    if [ -n "${DUCKE_REPO:-}" ] && [ -f "$DUCKE_REPO/flake.nix" ]; then
        REPO_DIR="$DUCKE_REPO"
    elif [ -f "$SCRIPT_ROOT/flake.nix" ]; then
        REPO_DIR="$SCRIPT_ROOT"
    elif [ -d "$HOME/duckeos" ] && [ -f "$HOME/duckeos/flake.nix" ]; then
        REPO_DIR="$HOME/duckeos"
    elif [ -d "$HOME/ducke" ] && [ -f "$HOME/ducke/flake.nix" ]; then
        REPO_DIR="$HOME/ducke"
    elif [ -d "$HOME/DuckeOS" ] && [ -f "$HOME/DuckeOS/flake.nix" ]; then
        REPO_DIR="$HOME/DuckeOS"
    elif [ -d "$HOME/nixos" ] && [ -f "$HOME/nixos/flake.nix" ]; then
        REPO_DIR="$HOME/nixos"
    elif [ -f "$PWD/flake.nix" ]; then
        REPO_DIR="$PWD"
    else
        REPO_DIR=""
    fi
fi

LOCAL_CONFIG="${REPO_DIR:-}/local-config.nix"

interactive() {
    [ -t 0 ] && [ -t 1 ]
}

require_tools() {
    command -v jq >/dev/null 2>&1 || die "O comando jq não está disponível. Rode um rebuild para instalar o comando ducke."
}

require_prompt_tools() {
    command -v gum >/dev/null 2>&1 || die "O comando gum não está disponível. Rode um rebuild para instalar o comando ducke."
}

runtime_dir() {
    local dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/srv
    mkdir -p "$dir"
    chmod 700 "$dir"
    printf '%s' "$dir"
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

in_group() {
    [ "$(id -u)" -eq 0 ] && return 0
    id -nG | tr ' ' '\n' | grep -qx srv
}

account_in_group() {
    [ "$(id -u)" -eq 0 ] && return 0
    id -nG "$(id -un)" 2>/dev/null | tr ' ' '\n' | grep -qx srv
}

# Uma sessão aberta antes do rebuild não carrega o grupo novo.
# sg aplica o grupo desta conta só neste comando.
adopt_srv_group() {
    in_group && return 0
    account_in_group || return 0
    [ -z "${DUCKE_SRV_SG:-}" ] || return 0
    command -v sg >/dev/null 2>&1 || return 0
    export DUCKE_SRV_SG=1
    local args
    args="$(printf '%q ' "$0" "$@")"
    exec sg srv -c "exec bash ${args}"
}

require_member() {
    in_group || die "Esta conta não está no grupo srv."
}

nix_string() {
    local key=$1
    [ -n "$REPO_DIR" ] && [ -f "$LOCAL_CONFIG" ] || return 1
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$LOCAL_CONFIG" | head -n1
}

load_primary() {
    PRIMARY="$(nix_string username || true)"
    [ -n "${PRIMARY:-}" ] || return 1
    [[ "$PRIMARY" =~ ^[a-z_][a-z0-9_-]*$ ]] || return 1
}

is_owner() {
    [ "$(id -u)" -eq 0 ] && return 0
    load_primary || return 1
    [ "$(id -un)" = "$PRIMARY" ]
}

require_owner() {
    if ! is_owner; then
        if load_primary; then
            die "Só a conta principal (${PRIMARY}) cadastra, edita e apaga servidores."
        fi
        die "Só a conta principal cadastra, edita e apaga servidores."
    fi
}

valid_alias() {
    [[ "$1" =~ ^[A-Za-z][A-Za-z0-9._-]*$ ]]
}

valid_user() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9._-]*$ ]]
}

valid_host() {
    local host=$1
    [[ "$host" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] && return 0
    [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0
    [[ "$host" =~ ^[0-9A-Fa-f:]+$ && "$host" == *:* ]] && return 0
    return 1
}

valid_panes() {
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    [ "$1" -ge 1 ] && [ "$1" -le 12 ]
}

session_name() {
    printf 'ssh-%s' "$1"
}

print_table() {
    local -a widths=()
    local line i cell
    local -a cols
    for line in "$@"; do
        IFS=$'\t' read -r -a cols <<<"$line"
        for i in "${!cols[@]}"; do
            cell=${cols[$i]}
            if [ -z "${widths[$i]:-}" ] || [ "${#cell}" -gt "${widths[$i]}" ]; then
                widths[$i]=${#cell}
            fi
        done
    done
    for line in "$@"; do
        IFS=$'\t' read -r -a cols <<<"$line"
        for i in "${!cols[@]}"; do
            printf '%-*s' "${widths[$i]}" "${cols[$i]}"
            if [ "$i" -lt $((${#cols[@]} - 1)) ]; then
                printf '  '
            fi
        done
        printf '\n'
    done
}

read_store() {
    if [ ! -f "$SERVERS_JSON" ]; then
        printf '%s\n' '{"version":1,"servers":[]}'
        return 0
    fi
    jq -c . "$SERVERS_JSON"
}

ensure_store() {
    if ! as_root install -d -o root -g srv -m 0750 "$STORE_DIR"; then
        die "Não foi possível preparar ${STORE_DIR}. O grupo srv precisa existir. Rode um rebuild."
    fi
    if ! as_root test -f "$SERVERS_JSON"; then
        printf '%s\n' '{"version":1,"servers":[]}' | as_root tee "$SERVERS_JSON" >/dev/null
        as_root chown root:srv "$SERVERS_JSON"
        as_root chmod 0640 "$SERVERS_JSON"
    fi
}

write_store() {
    local content=$1
    printf '%s\n' "$content" | as_root tee "$SERVERS_JSON" >/dev/null
    as_root chown root:srv "$SERVERS_JSON"
    as_root chmod 0640 "$SERVERS_JSON"
}

server_record() {
    local alias=$1
    local data
    data="$(read_store)"
    jq -c --arg alias "$alias" '.servers[] | select(.alias == $alias)' <<<"$data"
}

require_server() {
    local alias=$1
    local record
    record="$(server_record "$alias")"
    [ -n "$record" ] || die "Servidor desconhecido: ${alias}"
    printf '%s' "$record"
}

cmd_list() {
    require_member
    require_tools
    local data count
    data="$(read_store)"
    count="$(jq '.servers | length' <<<"$data")"
    local -a rows=("APELIDO"$'\t'"ENDEREÇO"$'\t'"USUÁRIO"$'\t'"PAINÉIS")
    if [ "$count" -eq 0 ]; then
        print_table "${rows[@]}"
        echo "Nenhum servidor."
        return 0
    fi
    local line
    while IFS= read -r line; do
        rows+=("$line")
    done < <(jq -r '.servers | sort_by(.alias)[] | [.alias, .host, .user, (.panes | tostring)] | @tsv' <<<"$data")
    print_table "${rows[@]}"
}

ask_text() {
    local header=$1
    local placeholder=$2
    local value=${3:-}
    require_prompt_tools
    gum input --header "$header" --placeholder "$placeholder" --value "$value"
}

cmd_add() {
    local alias=${1:-}
    local host=${2:-}
    local user=${3:-}
    local panes=${4:-}
    require_member
    require_owner
    require_tools
    if [ -z "$alias" ]; then
        interactive || die "No modo sem terminal, ducke srv add precisa do apelido."
        alias="$(ask_text "Apelido" "api")"
    fi
    valid_alias "$alias" || die "O apelido começa com letra e segue com letras, números, ponto, hífen ou sublinhado."
    if [ -n "$(server_record "$alias")" ]; then
        die "O servidor ${alias} já existe. Use ducke srv edit."
    fi
    if [ -z "$host" ]; then
        interactive || die "Informe --host."
        host="$(ask_text "Endereço Tailscale" "100.64.0.12")"
    fi
    valid_host "$host" || die "Endereço inválido: ${host}"
    if [ -z "$user" ]; then
        interactive || die "Informe --user."
        user="$(ask_text "Usuário remoto" "deploy")"
    fi
    valid_user "$user" || die "Usuário remoto inválido: ${user}"
    if [ -z "$panes" ]; then
        if interactive; then
            panes="$(ask_text "Painéis" "4" "4")"
        else
            panes=4
        fi
    fi
    valid_panes "$panes" || die "A quantidade de painéis fica entre 1 e 12."
    ensure_store
    local updated
    updated="$(jq -c --arg alias "$alias" --arg host "$host" --arg user "$user" --argjson panes "$panes" \
        '.servers += [{alias: $alias, host: $host, user: $user, panes: $panes}]' <<<"$(read_store)")"
    write_store "$updated"
    echo "Servidor ${alias} cadastrado."
}

cmd_edit() {
    local alias=${1:-}
    local host=${2:-}
    local user=${3:-}
    local panes=${4:-}
    local host_set=${5:-0}
    local user_set=${6:-0}
    local panes_set=${7:-0}
    require_member
    require_owner
    require_tools
    [ -n "$alias" ] || die "Informe o apelido. Exemplo: ducke srv edit api"
    valid_alias "$alias" || die "Apelido inválido: ${alias}"
    local record
    record="$(require_server "$alias")"
    local current_host current_user current_panes
    current_host="$(jq -r '.host' <<<"$record")"
    current_user="$(jq -r '.user' <<<"$record")"
    current_panes="$(jq -r '.panes' <<<"$record")"
    if [ "$host_set" -eq 0 ]; then
        interactive || host="$current_host"
        if interactive && [ -z "$host" ]; then
            host="$(ask_text "Endereço Tailscale" "100.64.0.12" "$current_host")"
        fi
    fi
    if [ "$user_set" -eq 0 ]; then
        interactive || user="$current_user"
        if interactive && [ -z "$user" ]; then
            user="$(ask_text "Usuário remoto" "deploy" "$current_user")"
        fi
    fi
    if [ "$panes_set" -eq 0 ]; then
        interactive || panes="$current_panes"
        if interactive && [ -z "$panes" ]; then
            panes="$(ask_text "Painéis" "4" "$current_panes")"
        fi
    fi
    [ -n "$host" ] || host="$current_host"
    [ -n "$user" ] || user="$current_user"
    [ -n "$panes" ] || panes="$current_panes"
    valid_host "$host" || die "Endereço inválido: ${host}"
    valid_user "$user" || die "Usuário remoto inválido: ${user}"
    valid_panes "$panes" || die "A quantidade de painéis fica entre 1 e 12."
    ensure_store
    local updated
    updated="$(jq -c --arg alias "$alias" --arg host "$host" --arg user "$user" --argjson panes "$panes" \
        '.servers |= map(if .alias == $alias then .host = $host | .user = $user | .panes = $panes else . end)' \
        <<<"$(read_store)")"
    write_store "$updated"
    echo "Servidor ${alias} atualizado."
}

socket_path() {
    printf '%s/%s.sock' "$(runtime_dir)" "$1"
}

master_dir() {
    printf '%s/%s.master' "$(runtime_dir)" "$1"
}

ssh_check() {
    local sock=$1
    ssh -o "ControlPath=$sock" -o ConnectTimeout=2 -O check ducke-srv >/dev/null 2>&1
}

ssh_options() {
    local host=$1
    local user=$2
    local sock=$3
    local master=$4
    cat <<EOF
-o
HostName=${host}
-o
User=${user}
-o
PubkeyAuthentication=no
-o
PreferredAuthentications=keyboard-interactive,password
-o
IdentitiesOnly=yes
-o
GSSAPIAuthentication=no
-o
ControlMaster=${master}
-o
ControlPath=${sock}
-o
ServerAliveInterval=30
-o
ServerAliveCountMax=3
-o
NumberOfPasswordPrompts=1
EOF
}

run_autossh() {
    local host=$1
    local user=$2
    local sock=$3
    local master=$4
    local -a opts=()
    local opt
    while IFS= read -r opt; do
        opts+=("$opt")
    done < <(ssh_options "$host" "$user" "$sock" "$master")
    AUTOSSH_GATETIME=0 AUTOSSH_PORT=0 autossh -M 0 "${opts[@]}" ducke-srv
}

cmd_connect() {
    local alias=${1:-}
    require_member
    require_tools
    command -v autossh >/dev/null 2>&1 || die "O comando autossh não está disponível. Rode um rebuild."
    command -v ssh >/dev/null 2>&1 || die "O comando ssh não está disponível. Rode um rebuild."
    [ -n "$alias" ] || die "Falta o apelido da conexão."
    valid_alias "$alias" || die "Apelido inválido: ${alias}"
    local record host user sock marker
    record="$(require_server "$alias")"
    host="$(jq -r '.host' <<<"$record")"
    user="$(jq -r '.user' <<<"$record")"
    sock="$(socket_path "$alias")"
    marker="$(master_dir "$alias")"
    while true; do
        if mkdir "$marker" 2>/dev/null; then
            if ! ssh_check "$sock"; then
                rm -f "$sock"
            fi
            run_autossh "$host" "$user" "$sock" yes || true
            rmdir "$marker" 2>/dev/null || true
        else
            local i ready=0
            for i in $(seq 1 900); do
                if ssh_check "$sock"; then
                    ready=1
                    break
                fi
                if [ ! -d "$marker" ]; then
                    break
                fi
                sleep 0.2
            done
            if [ "$ready" -eq 1 ]; then
                run_autossh "$host" "$user" "$sock" no || true
            fi
        fi
        sleep 1
    done
}

session_exists() {
    local session=$1
    command -v zellij >/dev/null 2>&1 || return 1
    zellij list-sessions --short 2>/dev/null | grep -Fxq "$session"
}

save_panes() {
    local alias=$1
    local panes=$2
    ensure_store
    local updated
    updated="$(jq -c --arg alias "$alias" --argjson panes "$panes" \
        '.servers |= map(if .alias == $alias then .panes = $panes else . end)' <<<"$(read_store)")"
    write_store "$updated"
}

wait_and_add_panes() {
    local session=$1
    local alias=$2
    local panes=$3
    local sock i dir=right
    sock="$(socket_path "$alias")"
    for i in $(seq 1 900); do
        if ssh_check "$sock"; then
            break
        fi
        if ! session_exists "$session"; then
            return 0
        fi
        sleep 0.2
    done
    ssh_check "$sock" || return 0
    for ((i = 1; i < panes; i++)); do
        zellij --session "$session" action new-pane -d "$dir" --no-focus -- ducke srv connect "$alias" || true
        if [ "$dir" = right ]; then
            dir=down
        else
            dir=right
        fi
    done
}

cmd_open() {
    local alias=$1
    local count=${2:-}
    require_member
    require_tools
    valid_alias "$alias" || die "Apelido inválido: ${alias}"
    local record panes session
    record="$(require_server "$alias")"
    panes="$(jq -r '.panes' <<<"$record")"
    session="$(session_name "$alias")"
    command -v zellij >/dev/null 2>&1 || die "O Zellij não está disponível. Rode um rebuild."
    command -v kitty >/dev/null 2>&1 || die "O Kitty não está disponível. Rode um rebuild."
    if [ -n "$count" ] && ! session_exists "$session"; then
        valid_panes "$count" || die "A quantidade de painéis fica entre 1 e 12."
        panes="$count"
        if is_owner; then
            save_panes "$alias" "$panes"
        fi
    fi
    local opening
    opening="$(runtime_dir)/${alias}.opening"
    if ! session_exists "$session"; then
        if mkdir "$opening" 2>/dev/null; then
            zellij attach "$session" --create-background -- ducke srv connect "$alias"
            wait_and_add_panes "$session" "$alias" "$panes" &
            rmdir "$opening" 2>/dev/null || true
        else
            local i
            for i in $(seq 1 50); do
                session_exists "$session" && break
                sleep 0.1
            done
            if ! session_exists "$session"; then
                rmdir "$opening" 2>/dev/null || true
                mkdir "$opening" 2>/dev/null || die "Não foi possível abrir a sessão ${session}."
                zellij attach "$session" --create-background -- ducke srv connect "$alias"
                wait_and_add_panes "$session" "$alias" "$panes" &
                rmdir "$opening" 2>/dev/null || true
            fi
        fi
    fi
    session_exists "$session" || die "Não foi possível abrir a sessão ${session}."
    kitty --title "$alias" -- zellij attach "$session"
}

cmd_pick() {
    require_member
    require_tools
    interactive || die "Sem terminal, use ducke srv <apelido> ou ducke srv -l."
    require_prompt_tools
    local data count choice
    data="$(read_store)"
    count="$(jq '.servers | length' <<<"$data")"
    if [ "$count" -eq 0 ]; then
        die "Nenhum servidor. Cadastre com ducke srv add."
    fi
    choice="$(jq -r '.servers | sort_by(.alias)[] | .alias' <<<"$data" | gum choose --header "Servidor")" || exit 1
    [ -n "$choice" ] || exit 1
    cmd_open "$choice"
}

cmd_pane() {
    require_member
    command -v zellij >/dev/null 2>&1 || die "O Zellij não está disponível. Rode um rebuild."
    if [ -z "${ZELLIJ:-}" ] || [ -z "${ZELLIJ_SESSION_NAME:-}" ]; then
        die "Rode ducke srv pane de dentro do Zellij."
    fi
    case "$ZELLIJ_SESSION_NAME" in
        ssh-*)
            local alias=${ZELLIJ_SESSION_NAME#ssh-}
            require_server "$alias" >/dev/null
            zellij action new-pane -d right -- ducke srv connect "$alias"
            ;;
        *)
            zellij action new-pane
            ;;
    esac
}

close_one() {
    local alias=$1
    local session sock marker
    session="$(session_name "$alias")"
    sock="$(socket_path "$alias")"
    marker="$(master_dir "$alias")"
    if command -v zellij >/dev/null 2>&1; then
        zellij kill-session "$session" >/dev/null 2>&1 || true
        zellij delete-session --force "$session" >/dev/null 2>&1 || true
    fi
    rm -f "$sock"
    rmdir "$marker" 2>/dev/null || true
}

cmd_close() {
    local target=${1:-}
    require_member
    if [ "$target" = "--all" ]; then
        if command -v zellij >/dev/null 2>&1; then
            local name
            while IFS= read -r name; do
                case "$name" in
                    ssh-*)
                        zellij kill-session "$name" >/dev/null 2>&1 || true
                        zellij delete-session --force "$name" >/dev/null 2>&1 || true
                        ;;
                esac
            done < <(zellij list-sessions --short 2>/dev/null || true)
        fi
        find "$(runtime_dir)" -mindepth 1 -maxdepth 1 \( -name '*.sock' -o -name '*.master' -o -name '*.opening' \) -exec rm -rf {} + 2>/dev/null || true
        return 0
    fi
    [ -n "$target" ] || die "Informe o apelido ou --all. Exemplo: ducke srv close api"
    valid_alias "$target" || die "Apelido inválido: ${target}"
    require_server "$target" >/dev/null
    close_one "$target"
}

cmd_remove() {
    local alias=${1:-}
    require_member
    require_owner
    require_tools
    [ -n "$alias" ] || die "Informe o apelido. Exemplo: ducke srv remove api"
    valid_alias "$alias" || die "Apelido inválido: ${alias}"
    require_server "$alias" >/dev/null
    if [ "$YES" -eq 0 ]; then
        if ! interactive; then
            die "Confirme com --yes ou rode num terminal."
        fi
        require_prompt_tools
        gum confirm --default=false "Apagar o servidor ${alias} e encerrar a sessão desta conta?" || exit 1
    fi
    close_one "$alias"
    ensure_store
    local updated
    updated="$(jq -c --arg alias "$alias" '.servers |= map(select(.alias != $alias))' <<<"$(read_store)")"
    write_store "$updated"
    echo "Servidor ${alias} apagado."
}

main() {
    local command=${1:-}
    if [ "$command" = "help" ] || [ "$command" = "--help" ] || [ "$command" = "-h" ]; then
        usage
        exit 0
    fi
    if [ "$command" != "srv" ]; then
        usage
        exit 1
    fi
    case ${2:-} in
        help|--help|-h) ;;
        *) adopt_srv_group "$@" ;;
    esac
    shift
    local sub=${1:-}
    if [ -z "$sub" ]; then
        cmd_pick
        exit 0
    fi
    if [ "$sub" = "help" ] || [ "$sub" = "--help" ] || [ "$sub" = "-h" ]; then
        usage
        exit 0
    fi
    case "$sub" in
        -l|list)
            shift
            [ $# -eq 0 ] || die "ducke srv -l não recebe argumentos."
            cmd_list
            ;;
        add)
            shift
            local alias="" host="" user="" panes=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --host)
                        shift
                        [ $# -gt 0 ] || die "--host precisa de um valor."
                        host=$1
                        ;;
                    --user)
                        shift
                        [ $# -gt 0 ] || die "--user precisa de um valor."
                        user=$1
                        ;;
                    --panes)
                        shift
                        [ $# -gt 0 ] || die "--panes precisa de um valor."
                        panes=$1
                        ;;
                    --yes)
                        YES=1
                        ;;
                    --help|-h)
                        usage
                        exit 0
                        ;;
                    --)
                        shift
                        break
                        ;;
                    -*)
                        die "Flag desconhecida: $1"
                        ;;
                    *)
                        [ -z "$alias" ] || die "Apelido repetido: $1"
                        alias=$1
                        ;;
                esac
                shift
            done
            cmd_add "$alias" "$host" "$user" "$panes"
            ;;
        edit)
            shift
            local alias="" host="" user="" panes=""
            local host_set=0 user_set=0 panes_set=0
            while [ $# -gt 0 ]; do
                case "$1" in
                    --host)
                        shift
                        [ $# -gt 0 ] || die "--host precisa de um valor."
                        host=$1
                        host_set=1
                        ;;
                    --user)
                        shift
                        [ $# -gt 0 ] || die "--user precisa de um valor."
                        user=$1
                        user_set=1
                        ;;
                    --panes)
                        shift
                        [ $# -gt 0 ] || die "--panes precisa de um valor."
                        panes=$1
                        panes_set=1
                        ;;
                    --yes)
                        YES=1
                        ;;
                    --help|-h)
                        usage
                        exit 0
                        ;;
                    -*)
                        die "Flag desconhecida: $1"
                        ;;
                    *)
                        [ -z "$alias" ] || die "Apelido repetido: $1"
                        alias=$1
                        ;;
                esac
                shift
            done
            cmd_edit "$alias" "$host" "$user" "$panes" "$host_set" "$user_set" "$panes_set"
            ;;
        remove|rm)
            shift
            local alias=""
            while [ $# -gt 0 ]; do
                case "$1" in
                    --yes)
                        YES=1
                        ;;
                    --help|-h)
                        usage
                        exit 0
                        ;;
                    -*)
                        die "Flag desconhecida: $1"
                        ;;
                    *)
                        [ -z "$alias" ] || die "Apelido repetido: $1"
                        alias=$1
                        ;;
                esac
                shift
            done
            cmd_remove "$alias"
            ;;
        close)
            shift
            cmd_close "${1:-}"
            ;;
        pane)
            shift
            [ $# -eq 0 ] || die "ducke srv pane não recebe argumentos."
            cmd_pane
            ;;
        connect)
            shift
            cmd_connect "${1:-}"
            ;;
        *)
            local alias=$sub
            local count=""
            shift
            if [ $# -gt 0 ]; then
                count=$1
                shift
            fi
            [ $# -eq 0 ] || die "Argumento inesperado: $1"
            cmd_open "$alias" "$count"
            ;;
    esac
}

main "$@"
