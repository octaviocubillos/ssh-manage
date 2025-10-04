#!/bin/bash

# ==============================================================================
#                 GESTOR DE CONEXIONES SSH v6.0
# ==============================================================================
#
#   Un script de Bash para gestionar múltiples conexiones SSH.
#   Compatible con la mayoría de distribuciones de Linux, macOS y Termux.
#
# ==============================================================================


# --- CONFIGURACIÓN PRINCIPAL ---
VERSION="6.0"
REPO_BASE_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master"

# Detección de Termux
IS_TERMUX=false
if [[ -n "$PREFIX" ]]; then
    IS_TERMUX=true
fi

POINTER_FILE="$HOME/.sshm_config_path"
DEFAULT_CONFIG_DIR="$HOME/.config/ssh-manager"
CONFIG_DIR=""
if [ -f "$POINTER_FILE" ]; then CONFIG_DIR=$(cat "$POINTER_FILE"); else CONFIG_DIR="$DEFAULT_CONFIG_DIR"; fi
CONFIG_FILE="$CONFIG_DIR/connections.txt"
DEPS_LOG="$CONFIG_DIR/installed_deps.log"
RESERVED_COMMANDS=("add" "-a" "edit" "-e" "list" "-l" "connect" "-c" "browse" "-b" "delete" "-d" "update" "-u" "scp" "-s" "tunnel" "-t" "reverse-tunnel" "-rt" "help" "-h")


# --- VERIFICACIÓN DE DEPENDENCIAS Y ANIMACIÓN ---

show_spinner() {
    if ! command -v "tput" &> /dev/null; then while true; do sleep 1; done; return; fi
    local -r FRAMES='|/-\'; local -r NUMBER_OF_FRAMES=${#FRAMES}; local -r delay=0.1; local i=0
    tput civis; trap 'tput cnorm' EXIT
    while true; do printf "\b%s" "${FRAMES:i++%NUMBER_OF_FRAMES:1}"; sleep $delay; done
}

ensure_dependency() {
    local dep=$1; local package_name=${2:-$1}; local was_installed=true
    if [ "$dep" == "openssl" ] && $IS_TERMUX; then dep="openssl-tool"; fi
    if ! command -v "$dep" &> /dev/null; then
        was_installed=false
        echo "La herramienta '$dep' es necesaria y no está instalada."
        local install_cmd=""; if $IS_TERMUX; then install_cmd="pkg install -y $package_name"; elif command -v apt-get &> /dev/null; then install_cmd="sudo apt-get update -y && sudo apt-get install -y $package_name"; elif command -v dnf &> /dev/null; then install_cmd="sudo dnf install -y $package_name"; elif command -v yum &> /dev/null; then if [ "$dep" == "sshfs" ]; then package_name="fuse-sshfs"; fi; install_cmd="sudo yum install -y epel-release && sudo yum install -y $package_name"; elif command -v pacman &> /dev/null; then install_cmd="sudo pacman -Syu --noconfirm $package_name"; elif command -v zypper &> /dev/null; then install_cmd="sudo zypper --non-interactive install $package_name"; elif command -v apk &> /dev/null; then install_cmd="sudo apk add --no-cache $package_name"; elif command -v brew &> /dev/null; then install_cmd="brew install $package_name"; else echo "Error: Gestor de paquetes no compatible."; return 1; fi
        printf "Instalando '$package_name'...  "; show_spinner &
        local spinner_pid=$!; eval "$install_cmd" > /dev/null 2>&1
        kill $spinner_pid &>/dev/null; wait $spinner_pid 2>/dev/null; printf "\b\bListo.\n"
        hash -r
        if ! command -v "$dep" &> /dev/null; then echo "Error: La instalación de '$package_name' falló."; return 1; fi
    fi
    if [ "$was_installed" == "false" ]; then echo "$package_name" >> "$DEPS_LOG"; fi
    return 0
}

check_base_requirements() {
    # 1. Verificar tput (para la interfaz)
    if ! command -v "tput" &> /dev/null; then
        echo "La herramienta 'tput' (para la interfaz) no está instalada."
        local ncurses_pkg="ncurses-bin"; local install_cmd=""
        if $IS_TERMUX; then ncurses_pkg="ncurses-utils"; install_cmd="pkg install -y $ncurses_pkg"; elif command -v apt-get &> /dev/null; then install_cmd="sudo apt-get update -y && sudo apt-get install -y $ncurses_pkg"; elif command -v dnf &> /dev/null; then ncurses_pkg="ncurses"; install_cmd="sudo dnf install -y $ncurses_pkg"; elif command -v yum &> /dev/null; then ncurses_pkg="ncurses"; install_cmd="sudo yum install -y $ncurses_pkg"; elif command -v pacman &> /dev/null; then ncurses_pkg="ncurses"; install_cmd="sudo pacman -Syu --noconfirm $ncurses_pkg"; elif command -v zypper &> /dev/null; then ncurses_pkg="ncurses"; install_cmd="sudo zypper --non-interactive install $ncurses_pkg"; elif command -v apk &> /dev/null; then ncurses_pkg="ncurses"; install_cmd="sudo apk add --no-cache $ncurses_pkg"; elif command -v brew &> /dev/null; then ncurses_pkg="ncurses"; install_cmd="brew install $ncurses_pkg"; fi
        if [ -n "$install_cmd" ]; then printf "Instalando '$ncurses_pkg'...\n"; if eval "$install_cmd"; then echo "Instalación completada."; hash -r; else echo "Error al instalar '$ncurses_pkg'."; fi; else echo "Advertencia: no se pudo instalar 'tput'."; fi
    fi
    # 2. Verificar ssh (fundamental)
    if ! command -v "ssh" &> /dev/null; then
        echo "El cliente SSH ('ssh') no está instalado."
        local ssh_pkg="openssh-client"; local install_cmd=""
        if $IS_TERMUX; then ssh_pkg="openssh"; install_cmd="pkg install -y $ssh_pkg"; elif command -v apt-get &> /dev/null; then install_cmd="sudo apt-get update -y && sudo apt-get install -y $ssh_pkg"; elif command -v dnf &> /dev/null; then ssh_pkg="openssh-clients"; install_cmd="sudo dnf install -y $ssh_pkg"; elif command -v yum &> /dev/null; then ssh_pkg="openssh-clients"; install_cmd="sudo yum install -y $ssh_pkg"; elif command -v pacman &> /dev/null; then ssh_pkg="openssh"; install_cmd="sudo pacman -Syu --noconfirm $ssh_pkg"; elif command -v zypper &> /dev/null; then ssh_pkg="openssh-clients"; install_cmd="sudo zypper --non-interactive install $ssh_pkg"; elif command -v apk &> /dev/null; then ssh_pkg="openssh-client"; install_cmd="sudo apk add --no-cache $ssh_pkg"; elif command -v brew &> /dev/null; then ssh_pkg="openssh"; install_cmd="brew install $ssh_pkg"; fi
        if [ -n "$install_cmd" ]; then printf "Instalando '$ssh_pkg'...\n"; if eval "$install_cmd"; then echo "Instalación completada."; hash -r; else echo "Error al instalar cliente SSH."; exit 1; fi; else echo "Error: No se pudo instalar el cliente SSH."; exit 1; fi
    fi
}


# --- FUNCIONES DE LA APLICACIÓN ---

show_usage() {
    echo "Uso: $(basename "$0") [comando] [argumentos...]"; echo "  o: $(basename "$0") <alias> [comando-remoto...]"
    echo ""; echo "Comandos:"; echo "  add,    -a                     Añade una nueva conexión."
    echo "  edit,   -e <alias> [campo]   Edita una conexión (campo: host,user,port,auth,dir,cmd)."
    echo "  list,   -l [-a | --all]        Lista conexiones. Con -a muestra todos los detalles."
    echo "  connect,-c <alias> [cmd]       Conecta a un servidor (o usa solo el <alias>)."
    if ! $IS_TERMUX; then echo "  browse, -b <alias>             Abre un explorador de archivos SFTP visual."; fi
    echo "  scp,    -s <orig> <dest>     Copia archivos/directorios vía SCP."
    echo "  tunnel, -t <alias> <LPORT:RHOST:RPORT>  Crea un túnel SSH local."
    echo "  reverse-tunnel, -rt <alias> <RPORT:LHOST:LPORT> Crea un túnel SSH reverso."
    echo "  delete, -d <alias>             Elimina una conexión por su alias."
    echo "  update, -u                     Busca y aplica actualizaciones para esta herramienta."
    echo "  help,   -h                     Muestra esta ayuda."
    echo ""; echo "Si no se especifican comandos, se abrirá el menú interactivo."
}

show_menu() {
    echo "==================================="; echo "  Gestor de Conexiones SSH"; echo "==================================="
    echo "l) Listar"; echo "c) Conectar"; if ! $IS_TERMUX; then echo "b) Explorar"; fi; echo "s) Copiar (SCP)"; echo "t) Túnel"; echo "rt) Túnel Reverso"
    echo "a) Añadir"; echo "e) Editar"; echo "d) Eliminar"
    echo "u) Actualizar"; echo "h) Ayuda"; echo "q) Salir"; echo "-----------------------------------"
}

is_alias_reserved() { local alias_to_check=$1; for cmd in "${RESERVED_COMMANDS[@]}"; do if [[ "$cmd" == "$alias_to_check" ]]; then return 0; fi; done; return 1; }

list_connections() {
    local show_all=false; if [[ "$1" == "-a" || "$1" == "--all" ]]; then show_all=true; fi
    echo "Conexiones guardadas:"; grep -vE '^\s*#|^\s*$' "$CONFIG_FILE" | while IFS='|' read -r alias host user port key pass remote_dir default_cmd _; do
        if [ "$show_all" = true ]; then
            echo "-------------------------"; echo "alias: $alias"; echo "host: $host"; echo "user: $user"; echo "port: $port"; if [ -n "$key" ]; then echo "key: $key"; fi; if [ -n "$pass" ]; then if [[ "$pass" == enc:* ]]; then echo "pass: (encriptada)"; else echo "pass: $pass (texto plano)"; fi; fi; if [ -n "$remote_dir" ]; then echo "directory: $remote_dir"; fi; if [ -n "$default_cmd" ]; then echo "command: $default_cmd"; fi
        else
            printf "  %-15s -> %s@%s\n" "$alias" "$user" "$host"
        fi
    done; if [ "$show_all" = true ]; then echo "-------------------------"; fi; echo ""
}

add_connection() {
    echo "Añadiendo una nueva conexión..."
    local alias; while true; do read -p "Alias: " alias; if [ -z "$alias" ]; then echo "Error: Alias vacío."; elif grep -qE "^${alias}\|" "$CONFIG_FILE"; then echo "Error: Alias ya existe."; elif is_alias_reserved "$alias"; then echo "Error: Alias reservado."; else break; fi; done
    local host; while true; do read -p "Host: " host; if [ -z "$host" ]; then echo "Error: Host obligatorio."; else break; fi; done
    local current_user=$(whoami); read -p "Usuario [$current_user]: " user; user=${user:-$current_user}
    read -p "Puerto [22]: " port; port=${port:-22}
    echo "Tipo auth: 1) Clave SSH, 2) Pass (plano), 3) Pass (encriptada), 4) Ninguna"; read -p "Opción: " auth_choice
    key_path=""; password=""
    if [ "$auth_choice" = "1" ]; then read -p "Ruta a clave: " key_path
    elif [ "$auth_choice" = "2" ]; then read -s -p "Contraseña: " password; echo ""
    elif [ "$auth_choice" = "3" ]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; read -s -p "Contraseña a encriptar: " pass_to_encrypt; echo ""; encrypted_pass=$(echo "$pass_to_encrypt" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword"); password="enc:$encrypted_pass"
    fi
    read -p "Directorio remoto (opcional): " remote_dir
    read -p "Comando por defecto (opcional): " default_cmd
    echo "$alias|$host|$user|$port|$key_path|$password|$remote_dir|$default_cmd|" >> "$CONFIG_FILE"; echo "¡Conexión '$alias' añadida!"
}

edit_connection() {
    local alias_to_edit=$1; local field_to_edit=$2; if [ -z "$alias_to_edit" ]; then list_connections; read -p "Alias a editar: " alias_to_edit; fi; if [ -z "$alias_to_edit" ]; then echo "Cancelado."; return 1; fi
    local connection_line; connection_line=$(grep -E "^${alias_to_edit}\|" "$CONFIG_FILE"); if [ -z "$connection_line" ]; then echo "Error: Alias no encontrado."; return 1; fi
    IFS='|' read -r old_alias old_host old_user old_port old_key old_pass old_remote_dir old_cmd _ <<< "$connection_line"
    local new_alias="$old_alias"; local new_host="$old_host"; local new_user="$old_user"; local new_port="$old_port"; local new_key="$old_key"; local new_pass="$old_pass"; local new_remote_dir="$old_remote_dir"; local new_cmd="$old_cmd"
    if [ -n "$field_to_edit" ]; then
        echo "Editando campo '$field_to_edit' para '$alias_to_edit'..."; case $field_to_edit in alias) while true; do read -p "Nuevo alias: " new_alias; if [ -z "$new_alias" ]; then echo "Alias vacío."; elif [[ "$new_alias" != "$old_alias" ]] && grep -qE "^${new_alias}\|" "$CONFIG_FILE"; then echo "Alias ya existe."; elif is_alias_reserved "$new_alias"; then echo "Alias reservado."; else break; fi; done;; host) while true; do read -p "Nuevo host: " new_host; if [ -z "$new_host" ]; then echo "Host obligatorio."; else break; fi; done;; user) while true; do read -p "Nuevo usuario: " new_user; if [ -z "$new_user" ]; then echo "Usuario obligatorio."; else break; fi; done;; port) read -p "Nuevo puerto: " new_port;; dir) read -p "Nuevo dir. remoto: " new_remote_dir;; cmd|command) read -p "Nuevo comando por defecto: " new_cmd;; auth) echo "Tipo auth: 1) Clave SSH, 2) Pass (plano), 3) Pass (encriptada), 4) Ninguna"; read -p "Opción: " auth_choice; new_key=""; new_pass=""; if [ "$auth_choice" = "1" ]; then read -p "Ruta a clave: " new_key; elif [ "$auth_choice" = "2" ]; then read -s -p "Nueva Contraseña: " new_pass; echo ""; elif [ "$auth_choice" = "3" ]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; read -s -p "Nueva Contraseña: " pass_to_encrypt; echo ""; encrypted_pass=$(echo "$pass_to_encrypt" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword"); new_pass="enc:$encrypted_pass"; fi;; *) echo "Error: Campo '$field_to_edit' desconocido."; return 1;; esac
    else
        echo "Editando '$old_alias'. Enter para mantener valor."; while true; do read -p "Nuevo alias [$old_alias]: " new_alias; new_alias=${new_alias:-$old_alias}; if [ -z "$new_alias" ]; then echo "Alias vacío."; elif [[ "$new_alias" != "$old_alias" ]] && grep -qE "^${new_alias}\|" "$CONFIG_FILE"; then echo "Alias ya existe."; elif is_alias_reserved "$new_alias"; then echo "Alias reservado."; else break; fi; done; while true; do read -p "Nuevo host [$old_host]: " new_host; new_host=${new_host:-$old_host}; if [ -z "$new_host" ]; then echo "Host obligatorio."; else break; fi; done; while true; do read -p "Nuevo usuario [$old_user]: " new_user; new_user=${new_user:-$old_user}; if [ -z "$new_user" ]; then echo "Usuario obligatorio."; else break; fi; done; read -p "Nuevo puerto [$old_port]: " new_port; new_port=${new_port:-$old_port}; read -p "Nuevo dir. remoto [$old_remote_dir]: " new_remote_dir; new_remote_dir=${new_remote_dir:-$old_remote_dir}; read -p "Nuevo comando por defecto [$old_cmd]: " new_cmd; new_cmd=${new_cmd:-$old_cmd}; read -p "¿Cambiar auth? (s/n): " change_auth; if [[ "$change_auth" =~ ^[sS]$ ]]; then echo "Tipo auth: 1) Clave SSH, 2) Pass (plano), 3) Pass (encriptada), 4) Ninguna"; read -p "Opción: " auth_choice; new_key=""; new_pass=""; if [ "$auth_choice" = "1" ]; then read -p "Ruta a clave: " new_key; elif [ "$auth_choice" = "2" ]; then read -s -p "Nueva Contraseña: " new_pass; echo ""; elif [ "$auth_choice" = "3" ]; then ensure_dependency "openssl" || return 1; read -s -p "Palabra clave: " keyword; echo ""; read -s -p "Nueva Contraseña: " pass_to_encrypt; echo ""; encrypted_pass=$(echo "$pass_to_encrypt" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword"); new_pass="enc:$encrypted_pass"; else new_key="$old_key"; new_pass="$old_pass"; fi; fi
    fi
    local new_line="$new_alias|$new_host|$new_user|$new_port|$new_key|$new_pass|$new_remote_dir|$new_cmd|"
    grep -vE "^${old_alias}\|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"; echo "$new_line" >> "${CONFIG_FILE}.tmp"; mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"; echo "¡Conexión '$new_alias' actualizada!"
}

# ... (El resto de las funciones: browse_sftp, connect_to_host, etc. van aquí) ...

# --- PUNTO DE ENTRADA PRINCIPAL ---
check_base_requirements

# Crear el directorio de configuración si no existe
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "# Formato: alias|host|usuario|puerto|ruta_clave|contraseña|directorio_remoto|comando_defecto|" > "$CONFIG_FILE"
fi

if [ "$#" -gt 0 ]; then
    COMMAND=$1
    shift
    case $COMMAND in -a) FULL_COMMAND="add" ;; -e) FULL_COMMAND="edit" ;; -l) FULL_COMMAND="list" ;; -c) FULL_COMMAND="connect" ;; -b) FULL_COMMAND="browse" ;; -d) FULL_COMMAND="delete" ;; -u) FULL_COMMAND="update" ;; -h) FULL_COMMAND="help" ;; add|edit|list|connect|browse|delete|update|help) FULL_COMMAND=$COMMAND ;; *) FULL_COMMAND="" ;; esac
    if [ -n "$FULL_COMMAND" ]; then
        case $FULL_COMMAND in 
            add) add_connection ;; 
            edit) edit_connection "$1" "$2" ;; 
            list) list_connections "$1" ;; 
            connect) connect_to_host "$1" "${@:2}" ;; 
            browse) if $IS_TERMUX; then echo "Error: La función 'browse' no está disponible en Termux."; exit 1; else browse_sftp "$1"; fi ;; 
            delete) delete_connection "$1" ;;
            update) update_script ;;
            help) show_usage ;;
        esac
    else
        if grep -qE "^${COMMAND}\|" "$CONFIG_FILE"; then
            connect_to_host "$COMMAND" "$@"
        else
            echo "Error: Comando o alias '$COMMAND' no reconocido."
            show_usage
            exit 1
        fi
    fi
else
    run_interactive_menu
fi
