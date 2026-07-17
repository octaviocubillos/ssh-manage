#!/bin/bash

# ==============================================================================
#                 INSTALADOR DE SSH MANAGER
# ==============================================================================
#
#   Este script descarga la última versión de ssh-manager, la instala
#   globalmente y te permite elegir dónde guardar tus configuraciones.
#
#   Uso (Linux/macOS): curl -fsSL "https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh?$(date +%s)" | sudo bash
#   Uso (Termux):      curl -fsSL "https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh?$(date +%s)" | bash
#
# ==============================================================================

set -e # Salir inmediatamente si un comando falla

# --- VARIABLES ---
REPO_BASE_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master"
MAIN_CMD="ssh-manage"
ALIAS_CMD="sshm"

# --- LÓGICA DE INSTALACIÓN ---

show_spinner() {
    if [ ! -t 1 ] || [ -z "${TERM:-}" ]; then while true; do sleep 1; done; return; fi
    if ! command -v "tput" &> /dev/null; then while true; do sleep 1; done; return; fi
    local -r FRAMES='|/-\'; local i=0; tput civis; trap 'tput cnorm' EXIT
    while true; do printf "\b%s" "${FRAMES:i++%${#FRAMES}:1}"; sleep 0.1; done
}



install_dependencies() {
    echo "Verificando dependencias..."
    local deps=("jq" "openssl" "sshpass" "curl")
    local missing_deps=()

    # Check for missing dependencies
    for dep in "${deps[@]}"; do
        local check_cmd="$dep"
        # Termux specific check for openssl
        if [[ -n "$PREFIX" ]] && [ "$dep" == "openssl" ]; then check_cmd="openssl-tool"; fi
        
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [[ -n "$PREFIX" ]]; then
        if ! command -v "ssh" &> /dev/null; then missing_deps+=("openssh"); fi
        if ! command -v "tput" &> /dev/null; then missing_deps+=("ncurses-utils"); fi
    fi

    # Optional browse dependencies are not installed on Termux because browse is unsupported there.
    if [[ -z "$PREFIX" ]]; then
        if ! command -v "sshfs" &> /dev/null; then missing_deps+=("sshfs"); fi
        if ! command -v "mc" &> /dev/null; then missing_deps+=("mc"); fi
    fi

    if [ ${#missing_deps[@]} -eq 0 ]; then
        echo "Todas las dependencias están instaladas."
        return 0
    fi

    echo "Faltan las siguientes dependencias: ${missing_deps[*]}"

    local update_cmd=""
    local install_base_cmd=""
    local sudo_prefix=""
    if [ "$EUID" -ne 0 ] && [ -z "$PREFIX" ]; then
        sudo_prefix="sudo"
    fi

    if [[ -n "$PREFIX" ]]; then
        install_base_cmd="pkg install -y"
    elif command -v apt-get &> /dev/null; then
        update_cmd="$sudo_prefix apt-get update -y"
        install_base_cmd="$sudo_prefix apt-get install -y"
    elif command -v dnf &> /dev/null; then
        install_base_cmd="$sudo_prefix dnf install -y"
    elif command -v yum &> /dev/null; then
        install_base_cmd="$sudo_prefix yum install -y"
        # Special case for sshfs on yum/centos
        if [[ " ${missing_deps[*]} " =~ " sshfs " ]]; then
             $sudo_prefix yum install -y epel-release > /dev/null 2>&1
             missing_deps=("${missing_deps[@]/sshfs/fuse-sshfs}")
        fi
    elif command -v pacman &> /dev/null; then
        update_cmd="$sudo_prefix pacman -Sy --noconfirm"
        install_base_cmd="$sudo_prefix pacman -S --noconfirm"
    elif command -v zypper &> /dev/null; then
        install_base_cmd="$sudo_prefix zypper --non-interactive install"
    elif command -v apk &> /dev/null; then
        update_cmd="$sudo_prefix apk update"
        install_base_cmd="$sudo_prefix apk add --no-cache"
    elif command -v brew &> /dev/null; then
        update_cmd="brew update"
        install_base_cmd="brew install"
    else
        echo "Advertencia: No se pudo detectar el gestor de paquetes. Por favor instala manualmente: ${missing_deps[*]}"
        return 1
    fi

    # Termux specific package name adjustments
    if [[ -n "$PREFIX" ]]; then
        missing_deps=("${missing_deps[@]/openssl/openssl-tool}")
    fi

    local final_cmd=""
    if [ -n "$update_cmd" ]; then
        final_cmd="$update_cmd && "
    fi
    final_cmd="${final_cmd}$install_base_cmd ${missing_deps[*]}"

    echo -n "Instalando dependencias...  "
    show_spinner &
    local spinner_pid=$!
    
    if eval "$final_cmd" > /dev/null 2>&1 < /dev/null; then
        kill $spinner_pid &>/dev/null || true
        wait $spinner_pid 2>/dev/null || true
        printf "\b\bListo.\n"
    else
        kill $spinner_pid &>/dev/null || true
        wait $spinner_pid 2>/dev/null || true
        printf "\b\bFalló.\n"
        echo "Error al instalar dependencias."
        return 1
    fi
}


main() {
    local INSTALL_DIR
    local original_user
    local user_home

    if [ -n "$SUDO_USER" ]; then
        original_user="$SUDO_USER"
    else
        original_user=$(whoami)
    fi

    if command -v getent >/dev/null 2>&1; then
        user_home=$(getent passwd "$original_user" | cut -d: -f6)
    fi
    if [ -z "$user_home" ]; then
        user_home="$HOME"
    fi


    # Detección del entorno (Termux o estándar)
    if [[ -n "$PREFIX" ]]; then
        echo "Detectado entorno Termux."
        INSTALL_DIR="$PREFIX/bin"
    else
        echo "Detectado entorno estándar (Linux/macOS)."
        INSTALL_DIR="/usr/local/bin"
        if [ "$EUID" -ne 0 ]; then
            echo "Este instalador necesita privilegios de superusuario."; exit 1
        fi
    fi

    echo "Iniciando la instalación de SSH Manager..."
    
    install_dependencies
    
    
    local default_config_dir="$user_home/.config/ssh-manager"
    local config_dir=""
    
    local tty_path=""
    tty_path=$(tty 2>/dev/null || true)
    if [ -n "$tty_path" ] && [ "$tty_path" != "not a tty" ] && [ -r "$tty_path" ]; then
        if read -p "Introduce la ruta para guardar las conexiones [$default_config_dir]: " config_dir < "$tty_path"; then
            :
        else
             echo "Usando directorio por defecto."
        fi
    else
        echo "Entorno no interactivo. Usando directorio por defecto."
    fi
    config_dir=${config_dir:-$default_config_dir}
    
    # Expandir tilde (~) si el usuario la introduce
    eval config_dir="$config_dir"
    
    echo "Las conexiones se guardarán en: $config_dir"
    
    echo "Descargando scripts..."
    local repo_ref
    repo_ref=$(curl -fsSL "https://api.github.com/repos/octaviocubillos/ssh-manage/commits/master" | jq -r '.sha // empty' 2>/dev/null || true)
    local download_base_url="$REPO_BASE_URL"
    if [ -n "$repo_ref" ]; then
        download_base_url="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/$repo_ref"
    fi
    if ! curl -fsSL "$download_base_url/ssh-manager.sh?$(date +%s)" -o "$INSTALL_DIR/$MAIN_CMD"; then
        echo "Error: No se pudo descargar el script principal."; exit 1
    fi

    chmod +x "$INSTALL_DIR/$MAIN_CMD"
    ln -sf "$INSTALL_DIR/$MAIN_CMD" "$INSTALL_DIR/$ALIAS_CMD"
    
    local master_config_file="$config_dir/config"
    echo "Creando directorio de configuración en $config_dir..."
    if [ "$(whoami)" == "$original_user" ]; then
        mkdir -p "$config_dir"
        echo "CONNECTIONS_PATH='$config_dir/connections.json'" > "$master_config_file"
        echo "DEPS_LOG_PATH='$config_dir/installed_deps.log'" >> "$master_config_file"
        echo "TUNNELS_PID_PATH='$config_dir/tunnels.pid'" >> "$master_config_file"
        touch "$config_dir/installed_deps.log"
    else
        sudo -u "$original_user" mkdir -p "$config_dir"
        sudo -u "$original_user" bash -c "echo \"CONNECTIONS_PATH='$config_dir/connections.json'\" > '$master_config_file'"
        sudo -u "$original_user" bash -c "echo \"DEPS_LOG_PATH='$config_dir/installed_deps.log'\" >> '$master_config_file'"
        sudo -u "$original_user" bash -c "echo \"TUNNELS_PID_PATH='$config_dir/tunnels.pid'\" >> '$master_config_file'"
        sudo -u "$original_user" touch "$config_dir/installed_deps.log"
    fi

    echo ""; echo "¡Instalación completada con éxito!"
    echo "======================================================="
    echo "  Para ejecutar SSH Manager, usa el comando:"
    echo "      sshm"
    echo "  o"
    echo "      ssh-manage"
    echo "======================================================="
}
main
