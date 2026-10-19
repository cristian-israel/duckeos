#!/usr/bin/env bash
# Contas adicionais desta máquina. A conta principal continua no local-config.nix.
set -euo pipefail

PASS_DIR="/var/lib/duckeos/passwords"
YES=0
NO_APPLY=0
REMOVE_HOME=0
PASS_MODE=""
NAME_SET=0
HOME_SET=0
GROUP_SET=0
EXCLUDE_SET=0
PACKAGE_SET=0
FULL_NAME=""
HOME_DIR=""
USERNAME=""
CHOICES_JSON=""
declare -a EXTRA_GROUPS=()
declare -a EXCLUDES=()
declare -a PACKAGES=()

die() {
    echo "$*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Uso: ducke user <comando> [nome] [flags]

Comandos:
  -l, list                     Lista a conta principal e as adicionais
  add [nome]                   Cadastra uma conta adicional
  edit <nome>                  Altera uma conta adicional
  remove <nome>                Remove a conta e mantém os arquivos

Flags de add e edit:
  --full-name NOME             Nome de exibição
  --home CAMINHO               Home absoluto. Vazio usa /home/<nome>
  --group GRUPO                Grupo extra. Pode repetir. Substitui a lista
  --exclude PACOTE             Programa da área de trabalho a tirar. Pode repetir
  --package PACOTE             Pacote Nix a mais, por exemplo obsidian. Pode repetir
  --password                   Pede a senha neste terminal, duas vezes
  --no-password                Entra no SDDM sem digitar senha
  --no-apply                   Grava a configuração e não roda o rebuild
  --yes                        Não pede confirmação

Flags de remove:
  --remove-home                Apaga o home depois do rebuild. O padrão é manter
  --no-apply                   Só tira a conta do registro
  --yes                        Não pede confirmação

Sem flags e num terminal, add e edit perguntam o resto.
A senha não entra na linha de comando. O hash fica em /var/lib/duckeos/passwords.
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
        die "Não foi possível localizar o repositório DuckeOS."
    fi
fi

USERS_JSON="$REPO_DIR/local-users.json"
LOCAL_CONFIG="$REPO_DIR/local-config.nix"

interactive() {
    [ -t 0 ] && [ -t 1 ]
}

require_tools() {
    local missing=()
    local tool
    for tool in jq nix; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if ((${#missing[@]})); then
        die "Faltam comandos: ${missing[*]}. Rode um rebuild para instalar o comando ducke."
    fi
}

require_prompt_tools() {
    command -v gum >/dev/null 2>&1 || die "O comando gum não está disponível. Rode um rebuild para instalar o comando ducke."
    command -v mkpasswd >/dev/null 2>&1 || die "O comando mkpasswd não está disponível. Rode um rebuild para instalar o comando ducke."
}

nix_string() {
    local key=$1
    sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$LOCAL_CONFIG" | head -n1
}

assert_local_config() {
    [ -f "$LOCAL_CONFIG" ] || die "Crie local-config.nix antes de gerenciar contas."
    if sed 's/#.*//' "$LOCAL_CONFIG" | grep -qE '^[[:space:]]*users[[:space:]]*='; then
        die "local-config.nix ainda define users =. Apague esse bloco. As contas adicionais ficam em local-users.json, pelo comando ducke user."
    fi
}

assert_operator() {
    local actor
    actor="$(id -un)"
    if [ "$actor" != "root" ] && [ "$actor" != "$PRIMARY" ]; then
        die "Só a conta principal (${PRIMARY}) pode gerenciar as outras contas."
    fi
}

load_identity() {
    assert_local_config
    PRIMARY="$(nix_string username)"
    PRIMARY_NAME="$(nix_string fullName)"
    PRIMARY_HOME="$(nix_string homeDirectory)"
    [[ "$PRIMARY" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "ducke.local.username em local-config.nix não é um nome Unix válido."
    [ -n "$PRIMARY_HOME" ] || PRIMARY_HOME="/home/$PRIMARY"
    [ -n "$PRIMARY_NAME" ] || PRIMARY_NAME="$PRIMARY"
    assert_operator
}

ensure_json() {
    if [ ! -f "$USERS_JSON" ]; then
        printf '%s\n' '{"version":1,"users":[]}' > "$USERS_JSON"
    fi
    chmod 600 "$USERS_JSON"
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$USERS_JSON"
    fi
}

load_choices() {
    [ -n "$CHOICES_JSON" ] && return
    CHOICES_JSON="$(nix eval --json --file "$REPO_DIR/modules/account-choices.nix")"
}

json_array() {
    if (($# == 0)); then
        echo '[]'
    else
        printf '%s\n' "$@" | jq -R . | jq -s 'unique'
    fi
}

valid_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

valid_package_name() {
    [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_-]*$ ]]
}

known_group() {
    load_choices
    jq -e --arg name "$1" '.groups | any(.name == $name)' >/dev/null <<<"$CHOICES_JSON"
}

known_exclude() {
    load_choices
    jq -e --arg name "$1" '.excludePackages | index($name) != null' >/dev/null <<<"$CHOICES_JSON"
}

user_record() {
    jq -c --arg name "$1" '.users[] | select(.username == $name)' "$USERS_JSON"
}

user_exists() {
    jq -e --arg name "$1" '.users | any(.username == $name)' >/dev/null <<<"$(cat "$USERS_JSON")"
}

effective_home() {
    local username=$1 home=$2
    if [ -n "$home" ]; then
        printf '%s' "$home"
    else
        printf '/home/%s' "$username"
    fi
}

validate_home() {
    local home=$1
    [ -z "$home" ] && return
    [[ "$home" == /* ]] || die "O home precisa ser um caminho absoluto."
    [[ "$home" != *..* ]] || die "O home não pode conter '..'."
}

validate_lists() {
    local item
    for item in "${EXTRA_GROUPS[@]}"; do
        known_group "$item" || die "Grupo desconhecido: $item"
    done
    for item in "${EXCLUDES[@]}"; do
        known_exclude "$item" || die "Programa desconhecido para --exclude: $item"
    done
    for item in "${PACKAGES[@]}"; do
        valid_package_name "$item" || die "Nome de pacote inválido: $item"
    done
}

prompt_or_abort() {
    local result
    if ! result="$("$@")"; then
        die "Cancelado."
    fi
    printf '%s' "$result"
}

read_lines_from() {
    local -n _dest=$1
    shift
    local status=0
    local output
    output="$("$@")" || status=$?
    if [ "$status" -ne 0 ]; then
        die "Cancelado."
    fi
    _dest=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && _dest+=("$line")
    done <<<"$output"
}

choose_from_json() {
    local header=$1
    local query=$2
    shift 2
    local -a selected=("$@")
    load_choices
    local -a options=()
    local -a preselected=()
    local name description label
    while IFS=$'\t' read -r name description; do
        [ -n "$name" ] || continue
        if [ -n "$description" ]; then
            label="${name} - ${description}"
        else
            label="$name"
        fi
        options+=("${label}|${name}")
        local current
        for current in "${selected[@]}"; do
            if [ "$current" == "$name" ]; then
                preselected+=("$label")
            fi
        done
    done < <(jq -r "$query" <<<"$CHOICES_JSON")

    local height=${#options[@]}
    if ((height > 12)); then
        height=12
    fi
    if ((height < 1)); then
        height=1
    fi

    local -a cmd=(
        gum choose
        --no-limit
        --height "$height"
        --label-delimiter '|'
        --header "$header"
    )
    if ((${#preselected[@]})); then
        cmd+=(--selected "${preselected[@]}")
    fi
    cmd+=("${options[@]}")
    read_lines_from SELECTED_RESULT "${cmd[@]}"
}

ask_text() {
    local header=$1
    local placeholder=$2
    local value=${3:-}
    prompt_or_abort gum input --header "$header" --placeholder "$placeholder" --value "$value"
}

ask_password_mode() {
    local current=${1:-}
    local -a options=(
        "Definir senha|set"
        "Entrar sem senha|none"
    )
    local -a preselected=()
    if [ "$current" = "none" ]; then
        preselected=("Entrar sem senha")
    elif [ "$current" = "set" ]; then
        preselected=("Definir senha")
    fi
    local -a cmd=(
        gum choose
        --height 4
        --label-delimiter '|'
        --header "Como esta conta entra no SDDM"
    )
    if ((${#preselected[@]})); then
        cmd+=(--selected "${preselected[@]}")
    fi
    cmd+=("${options[@]}")
    prompt_or_abort "${cmd[@]}"
}

read_new_password() {
    require_prompt_tools
    local first second
    first="$(prompt_or_abort gum input --password --header "Senha" --placeholder "senha")"
    [ -n "$first" ] || die "A senha não pode ficar vazia. Para entrar sem senha, use --no-password."
    second="$(prompt_or_abort gum input --password --header "Repita a senha" --placeholder "senha")"
    [ "$first" = "$second" ] || die "As senhas não conferem."
    printf '%s' "$first"
}

write_password_file() {
    local username=$1
    local password=$2
    local hash dest
    hash="$(printf '%s' "$password" | mkpasswd -m yescrypt -s)"
    [[ "$hash" != *:* ]] || die "O hash gerado é inválido."
    dest="$PASS_DIR/$username"
    sudo install -d -m 0700 /var/lib/duckeos /var/lib/duckeos/passwords
    printf '%s\n' "$hash" | sudo tee "$dest" >/dev/null
    sudo chown root:root "$dest"
    sudo chmod 0400 "$dest"
    printf '%s' "$dest"
}

clear_password_file() {
    local username=$1
    if sudo test -d "$PASS_DIR"; then
        sudo rm -f "$PASS_DIR/$username"
    fi
}

build_record() {
    local username=$1
    local full_name=$2
    local home=$3
    local passwordless=$4
    local password_file=$5
    jq -n \
        --arg username "$username" \
        --arg fullName "$full_name" \
        --arg homeDirectory "$home" \
        --argjson extraGroups "$(json_array "${EXTRA_GROUPS[@]}")" \
        --argjson excludePackages "$(json_array "${EXCLUDES[@]}")" \
        --argjson extraPackages "$(json_array "${PACKAGES[@]}")" \
        --argjson passwordless "$passwordless" \
        --arg passwordFile "$password_file" \
        '{
          username: $username,
          fullName: $fullName,
          homeDirectory: $homeDirectory,
          extraGroups: $extraGroups,
          excludePackages: $excludePackages,
          extraPackages: $extraPackages,
          passwordless: $passwordless,
          passwordFile: (if $passwordFile == "" then null else $passwordFile end)
        }'
}

upsert_user() {
    local record=$1
    local username=$2
    local tmp
    tmp="$(mktemp "$REPO_DIR/.local-users.json.tmp.XXXXXX")"
    if user_exists "$username"; then
        jq --argjson record "$record" --arg name "$username" \
            '.users |= map(if .username == $name then $record else . end)' \
            "$USERS_JSON" > "$tmp"
    else
        jq --argjson record "$record" '.users += [$record]' "$USERS_JSON" > "$tmp"
    fi
    mv "$tmp" "$USERS_JSON"
    chmod 600 "$USERS_JSON"
    if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
        chown "$SUDO_USER:$(id -gn "$SUDO_USER")" "$USERS_JSON"
    fi
}

confirm() {
    local prompt=$1
    local default=${2:-true}
    if [ "$YES" -eq 1 ]; then
        return 0
    fi
    if ! interactive; then
        die "Confirme com --yes ou rode num terminal: $prompt"
    fi
    require_prompt_tools
    if [ "$default" = "false" ]; then
        gum confirm --default=false "$prompt"
    else
        gum confirm "$prompt"
    fi
}

apply_rebuild() {
    APPLIED=0
    if [ "$NO_APPLY" -eq 1 ]; then
        echo "Registro atualizado. Rode rebuild para aplicar."
        return 0
    fi
    if ! confirm "Aplicar agora com rebuild?"; then
        echo "Registro atualizado. Rode rebuild quando quiser."
        return 0
    fi
    echo "Aplicando com rebuild..."
    bash "$REPO_DIR/scripts/rebuild.sh" -y
    APPLIED=1
}

sync_login_password() {
    local username=$1
    local mode=$2
    if ! id "$username" >/dev/null 2>&1; then
        echo "A forma de entrar fica pronta quando o rebuild criar a conta."
        return
    fi
    if [ "$mode" = "none" ]; then
        sudo passwd -d "$username" >/dev/null
        echo "A conta ${username} entra no SDDM sem senha. SSH, su e sudo continuam pedindo senha."
    elif [ "$mode" = "set" ]; then
        local hash
        hash="$(sudo cat "$PASS_DIR/$username")"
        printf '%s:%s\n' "$username" "$hash" | sudo chpasswd -e
        echo "Senha de ${username} atualizada."
    fi
}

login_label() {
    local passwordless=$1
    local password_file=$2
    if [ "$passwordless" = "true" ]; then
        echo "entra sem senha"
    elif [ -n "$password_file" ] && [ "$password_file" != "null" ]; then
        echo "senha definida"
    else
        echo "login bloqueado"
    fi
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

groups_of() {
    local name=$1
    local fallback=$2
    if id -nG "$name" >/dev/null 2>&1; then
        id -nG "$name"
    else
        printf '%s' "$fallback"
    fi
}

cmd_list() {
    load_identity
    ensure_json
    local -a rows=("TIPO"$'\t'"USUÁRIO"$'\t'"NOME"$'\t'"HOME"$'\t'"LOGIN"$'\t'"GRUPOS")
    rows+=("principal"$'\t'"${PRIMARY}"$'\t'"${PRIMARY_NAME}"$'\t'"${PRIMARY_HOME}"$'\t'"senha definida"$'\t'"$(groups_of "$PRIMARY" "wheel networkmanager docker libvirtd kvm i2c input uinput srv")")
    local count
    count="$(jq '.users | length' "$USERS_JSON")"
    if [ "$count" -eq 0 ]; then
        print_table "${rows[@]}"
        return
    fi
    local line username full_name home login groups
    while IFS=$'\t' read -r username full_name home login groups; do
        if [ -z "$groups" ]; then
            groups="input uinput"
        fi
        rows+=("adicional"$'\t'"${username}"$'\t'"${full_name}"$'\t'"${home}"$'\t'"${login}"$'\t'"$(groups_of "$username" "$groups")")
    done < <(jq -r '.users[] | [
        .username,
        (if .fullName == "" then .username else .fullName end),
        (if .homeDirectory == "" then "/home/" + .username else .homeDirectory end),
        (if .passwordless then "entra sem senha" elif .passwordFile != null then "senha definida" else "login bloqueado" end),
        ((.extraGroups // []) | join(" "))
      ] | @tsv' "$USERS_JSON")
    print_table "${rows[@]}"
}

fill_add_prompts() {
    require_prompt_tools
    if [ -z "$USERNAME" ]; then
        USERNAME="$(ask_text "Nome Unix da conta" "outro")"
    fi
    if [ "$NAME_SET" -eq 0 ]; then
        FULL_NAME="$(ask_text "Nome de exibição" "pode ficar vazio" "")"
    fi
    if [ "$HOME_SET" -eq 0 ]; then
        HOME_DIR="$(ask_text "Home" "/home/${USERNAME:-usuario}" "")"
    fi
    if [ "$GROUP_SET" -eq 0 ]; then
        choose_from_json "Grupos além de input e uinput. Espaço marca, enter confirma." \
            '.groups[] | "\(.name)\t\(.description)"'
        EXTRA_GROUPS=("${SELECTED_RESULT[@]}")
    fi
    if [ "$EXCLUDE_SET" -eq 0 ]; then
        choose_from_json "Programas da área de trabalho para tirar. Espaço marca, enter confirma." \
            '.excludePackages[] | "\(.)\t"'
        EXCLUDES=("${SELECTED_RESULT[@]}")
    fi
    if [ "$PACKAGE_SET" -eq 0 ]; then
        local raw
        raw="$(ask_text "Pacotes Nix a mais, separados por espaço" "obsidian" "")"
        PACKAGES=()
        if [ -n "$raw" ]; then
            read -r -a PACKAGES <<<"$raw"
        fi
    fi
    if [ -z "$PASS_MODE" ]; then
        PASS_MODE="$(ask_password_mode)"
    fi
}

fill_edit_prompts() {
    require_prompt_tools
    local record=$1
    if [ "$NAME_SET" -eq 0 ]; then
        FULL_NAME="$(ask_text "Nome de exibição" "pode ficar vazio" "$(jq -r '.fullName' <<<"$record")")"
    fi
    if [ "$HOME_SET" -eq 0 ]; then
        HOME_DIR="$(ask_text "Home. Vazio usa /home/${USERNAME}" "caminho absoluto" "$(jq -r '.homeDirectory' <<<"$record")")"
    fi
    if [ "$GROUP_SET" -eq 0 ]; then
        local -a current=()
        mapfile -t current < <(jq -r '.extraGroups[]?' <<<"$record")
        choose_from_json "Grupos além de input e uinput. Espaço marca, enter confirma." \
            '.groups[] | "\(.name)\t\(.description)"' \
            "${current[@]}"
        EXTRA_GROUPS=("${SELECTED_RESULT[@]}")
    fi
    if [ "$EXCLUDE_SET" -eq 0 ]; then
        local -a current=()
        mapfile -t current < <(jq -r '.excludePackages[]?' <<<"$record")
        choose_from_json "Programas da área de trabalho para tirar. Espaço marca, enter confirma." \
            '.excludePackages[] | "\(.)\t"' \
            "${current[@]}"
        EXCLUDES=("${SELECTED_RESULT[@]}")
    fi
    if [ "$PACKAGE_SET" -eq 0 ]; then
        local current raw
        current="$(jq -r '(.extraPackages // []) | join(" ")' <<<"$record")"
        raw="$(ask_text "Pacotes Nix a mais, separados por espaço" "obsidian" "$current")"
        PACKAGES=()
        if [ -n "$raw" ]; then
            read -r -a PACKAGES <<<"$raw"
        fi
    fi
    if [ -z "$PASS_MODE" ]; then
        local choice
        choice="$(prompt_or_abort gum choose --height 5 --label-delimiter '|' --header "Senha" \
            "Manter como está|keep" \
            "Definir senha|set" \
            "Entrar sem senha|none")"
        if [ "$choice" != "keep" ]; then
            PASS_MODE="$choice"
        fi
    fi
}

load_record_fields() {
    local record=$1
    if [ "$NAME_SET" -eq 0 ]; then
        FULL_NAME="$(jq -r '.fullName' <<<"$record")"
    fi
    if [ "$HOME_SET" -eq 0 ]; then
        HOME_DIR="$(jq -r '.homeDirectory' <<<"$record")"
    fi
    if [ "$GROUP_SET" -eq 0 ]; then
        mapfile -t EXTRA_GROUPS < <(jq -r '.extraGroups[]?' <<<"$record")
    fi
    if [ "$EXCLUDE_SET" -eq 0 ]; then
        mapfile -t EXCLUDES < <(jq -r '.excludePackages[]?' <<<"$record")
    fi
    if [ "$PACKAGE_SET" -eq 0 ]; then
        mapfile -t PACKAGES < <(jq -r '.extraPackages[]?' <<<"$record")
    fi
}

show_summary() {
    local username=$1
    local login=$2
    echo "Conta: ${username}"
    echo "Nome: ${FULL_NAME:-$username}"
    echo "Home: $(effective_home "$username" "$HOME_DIR")"
    if ((${#EXTRA_GROUPS[@]})); then
        echo "Grupos: ${EXTRA_GROUPS[*]}"
    else
        echo "Grupos: só input e uinput"
    fi
    if ((${#EXCLUDES[@]})); then
        echo "Sem: ${EXCLUDES[*]}"
    fi
    if ((${#PACKAGES[@]})); then
        echo "A mais: ${PACKAGES[*]}"
    fi
    echo "Entrada: ${login}"
}

prepare_password() {
    local username=$1
    local password_file=""
    local passwordless=false
    case "$PASS_MODE" in
        set)
            interactive || die "--password precisa de um terminal para digitar a senha."
            require_prompt_tools
            local password
            password="$(read_new_password)"
            password_file="$(write_password_file "$username" "$password")"
            unset password
            ;;
        none)
            clear_password_file "$username"
            passwordless=true
            ;;
        "")
            ;;
        *)
            die "Modo de senha desconhecido."
            ;;
    esac
    PASSWORD_FILE="$password_file"
    PASSWORDLESS="$passwordless"
}

cmd_add() {
    load_identity
    ensure_json
    if interactive; then
        fill_add_prompts
    elif [ -z "$PASS_MODE" ]; then
        die "Informe --password ou --no-password."
    fi
    [ -n "$USERNAME" ] || die "Informe o nome da conta."
    valid_username "$USERNAME" || die "Nome Unix inválido: $USERNAME"
    [ "$USERNAME" != "$PRIMARY" ] || die "A conta principal não entra nesta lista."
    user_exists "$USERNAME" && die "A conta ${USERNAME} já existe. Use ducke user edit."
    validate_home "$HOME_DIR"
    validate_lists
    local login="senha definida"
    if [ "$PASS_MODE" = "none" ]; then
        login="entra sem senha"
    fi
    echo
    show_summary "$USERNAME" "$login"
    echo
    confirm "Cadastrar esta conta?" || die "Cancelado."
    prepare_password "$USERNAME"
    local record
    local passwordless_json=false
    [ "$PASSWORDLESS" = "true" ] && passwordless_json=true
    record="$(build_record "$USERNAME" "$FULL_NAME" "$HOME_DIR" "$passwordless_json" "$PASSWORD_FILE")"
    upsert_user "$record" "$USERNAME"
    apply_rebuild
    sync_login_password "$USERNAME" "$PASS_MODE"
}

edit_has_changes() {
    [ "$NAME_SET" -eq 1 ] || [ "$HOME_SET" -eq 1 ] || [ "$GROUP_SET" -eq 1 ] \
        || [ "$EXCLUDE_SET" -eq 1 ] || [ "$PACKAGE_SET" -eq 1 ] || [ -n "$PASS_MODE" ]
}

cmd_edit() {
    load_identity
    ensure_json
    [ -n "$USERNAME" ] || die "Informe a conta que será editada."
    valid_username "$USERNAME" || die "Nome Unix inválido: $USERNAME"
    [ "$USERNAME" != "$PRIMARY" ] || die "A conta principal não é editada por aqui."
    user_exists "$USERNAME" || die "A conta ${USERNAME} não está no registro."
    local record
    record="$(user_record "$USERNAME")"
    if ! edit_has_changes; then
        if interactive && [ "$YES" -eq 0 ]; then
            fill_edit_prompts "$record"
        else
            die "Nada para alterar. Informe uma flag ou rode num terminal."
        fi
    else
        load_record_fields "$record"
    fi
    validate_home "$HOME_DIR"
    validate_lists
    local previous_file previous_less login
    previous_file="$(jq -r '.passwordFile // ""' <<<"$record")"
    previous_less="$(jq -r '.passwordless' <<<"$record")"
    if [ -z "$PASS_MODE" ]; then
        login="$(login_label "$previous_less" "$previous_file")"
    elif [ "$PASS_MODE" = "none" ]; then
        login="entra sem senha"
    else
        login="senha definida"
    fi
    echo
    show_summary "$USERNAME" "$login"
    echo
    confirm "Salvar estas alterações?" || die "Cancelado."

    local password_file="$previous_file"
    local passwordless_json=false
    [ "$previous_less" = "true" ] && passwordless_json=true
    if [ -n "$PASS_MODE" ]; then
        prepare_password "$USERNAME"
        password_file="$PASSWORD_FILE"
        passwordless_json=false
        [ "$PASSWORDLESS" = "true" ] && passwordless_json=true
    fi
    local updated
    updated="$(build_record "$USERNAME" "$FULL_NAME" "$HOME_DIR" "$passwordless_json" "$password_file")"
    upsert_user "$updated" "$USERNAME"
    apply_rebuild
    if [ -n "$PASS_MODE" ]; then
        sync_login_password "$USERNAME" "$PASS_MODE"
    fi
}

session_open() {
    local username=$1
    loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | grep -qx "$username"
}

assert_purge_home() {
    local home=$1
    [[ "$home" == /home/* ]] || die "O home ${home} está fora de /home. Remova os arquivos manualmente se ainda quiser apagá-los."
    [[ "$home" != *..* ]] || die "O home não pode conter '..'."
    local rest="${home#/home/}"
    [ -n "$rest" ] || die "Caminho de home inválido."
    [ "$rest" != "." ] && [ "$rest" != ".." ] || die "Caminho de home inválido."
    [ "$home" != "$PRIMARY_HOME" ] || die "Esse caminho é o home da conta principal."
}

cmd_remove() {
    load_identity
    ensure_json
    [ -n "$USERNAME" ] || die "Informe a conta que será removida."
    valid_username "$USERNAME" || die "Nome Unix inválido: $USERNAME"
    [ "$USERNAME" != "$PRIMARY" ] || die "A conta principal não pode ser removida."
    user_exists "$USERNAME" || die "A conta ${USERNAME} não está no registro."
    if session_open "$USERNAME"; then
        die "A conta ${USERNAME} está em uma sessão. Saia dela antes de remover."
    fi
    local record home
    record="$(user_record "$USERNAME")"
    home="$(jq -r '.homeDirectory' <<<"$record")"
    home="$(effective_home "$USERNAME" "$home")"
    if [ "$REMOVE_HOME" -eq 1 ]; then
        [ "$NO_APPLY" -eq 0 ] || die "Não combine --remove-home com --no-apply. Os arquivos só são apagados depois do rebuild."
        assert_purge_home "$home"
    fi
    echo "A conta ${USERNAME} sai do sistema. Os arquivos em ${home} permanecem."
    if [ "$REMOVE_HOME" -eq 1 ]; then
        echo "Em seguida o diretório ${home} será apagado."
    fi
    confirm "Remover a conta ${USERNAME}?" || die "Cancelado."
    if [ "$REMOVE_HOME" -eq 1 ] && [ "$YES" -eq 0 ]; then
        require_prompt_tools
        local typed
        typed="$(ask_text "Digite ${USERNAME} para apagar ${home}" "$USERNAME")"
        [ "$typed" = "$USERNAME" ] || die "O nome não confere. A conta e os arquivos foram mantidos."
    fi
    local tmp
    tmp="$(mktemp "$REPO_DIR/.local-users.json.tmp.XXXXXX")"
    jq --arg name "$USERNAME" '.users |= map(select(.username != $name))' "$USERS_JSON" > "$tmp"
    mv "$tmp" "$USERS_JSON"
    chmod 600 "$USERS_JSON"
    clear_password_file "$USERNAME"
    apply_rebuild
    if [ "$APPLIED" -eq 1 ] && [ "$REMOVE_HOME" -eq 1 ]; then
        sudo rm -rf -- "$home"
        echo "Arquivos de ${home} apagados."
    else
        echo "Arquivos mantidos em ${home}."
    fi
}

parse_common_flags() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --yes|-y)
                YES=1
                ;;
            --no-apply)
                NO_APPLY=1
                ;;
            --no-password)
                [ -z "$PASS_MODE" ] || die "Use só uma opção de senha."
                PASS_MODE="none"
                ;;
            --password)
                [ -z "$PASS_MODE" ] || die "Use só uma opção de senha."
                PASS_MODE="set"
                ;;
            --remove-home)
                REMOVE_HOME=1
                ;;
            --full-name)
                shift
                [ $# -gt 0 ] || die "--full-name precisa de um valor."
                FULL_NAME="$1"
                NAME_SET=1
                ;;
            --home)
                shift
                [ $# -gt 0 ] || die "--home precisa de um valor."
                HOME_DIR="$1"
                HOME_SET=1
                ;;
            --group)
                shift
                [ $# -gt 0 ] || die "--group precisa de um valor."
                EXTRA_GROUPS+=("$1")
                GROUP_SET=1
                ;;
            --exclude)
                shift
                [ $# -gt 0 ] || die "--exclude precisa de um valor."
                EXCLUDES+=("$1")
                EXCLUDE_SET=1
                ;;
            --package)
                shift
                [ $# -gt 0 ] || die "--package precisa de um valor."
                PACKAGES+=("$1")
                PACKAGE_SET=1
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
                if [ -n "$USERNAME" ]; then
                    die "Nome repetido: $1"
                fi
                USERNAME="$1"
                ;;
        esac
        shift
    done
}

main() {
    local command=${1:-}
    if [ -z "$command" ] || [ "$command" = "help" ] || [ "$command" = "--help" ] || [ "$command" = "-h" ]; then
        usage
        if [ -z "$command" ]; then
            exit 1
        fi
        exit 0
    fi
    if [ "$command" != "user" ]; then
        usage
        exit 1
    fi
    shift
    local sub=${1:-}
    if [ -z "$sub" ] || [ "$sub" = "help" ] || [ "$sub" = "--help" ] || [ "$sub" = "-h" ]; then
        usage
        if [ -z "$sub" ]; then
            exit 1
        fi
        exit 0
    fi
    shift
    require_tools
    case "$sub" in
        -l|list)
            [ $# -eq 0 ] || die "ducke user -l não recebe argumentos."
            cmd_list
            ;;
        add)
            parse_common_flags "$@"
            [ "$REMOVE_HOME" -eq 0 ] || die "--remove-home só vale em ducke user remove."
            cmd_add
            ;;
        edit)
            parse_common_flags "$@"
            [ "$REMOVE_HOME" -eq 0 ] || die "--remove-home só vale em ducke user remove."
            cmd_edit
            ;;
        remove|rm)
            parse_common_flags "$@"
            [ -z "$PASS_MODE" ] && [ "$NAME_SET" -eq 0 ] && [ "$HOME_SET" -eq 0 ] \
                && [ "$GROUP_SET" -eq 0 ] && [ "$EXCLUDE_SET" -eq 0 ] && [ "$PACKAGE_SET" -eq 0 ] \
                || die "ducke user remove aceita --remove-home, --no-apply e --yes."
            cmd_remove
            ;;
        *)
            die "Comando desconhecido: $sub"
            ;;
    esac
}

main "$@"
