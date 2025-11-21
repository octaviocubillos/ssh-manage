#!/bin/bash

# ==============================================================================
#                 INSTALADOR DE SSH MANAGER
# ==============================================================================
#
#   Este script descarga la última versión de ssh-manager, la instala
#   globalmente y te permite elegir dónde guardar tus configuraciones.
#
#   Uso (Linux/macOS): curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh | sudo bash
#   Uso (Termux):      curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh | bash
#
# ==============================================================================

set -e # Salir inmediatamente si un comando falla

# --- VARIABLES ---
REPO_BASE_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master"
MAIN_CMD="ssh-manage"
ALIAS_CMD="sshm"

# --- LÓGICA DE INSTALACIÓN ---

main() {
    local INSTALL_DIR
    local original_user
    local user_home

    if [ -n "$SUDO_USER" ]; then
        original_user="$SUDO_USER"
    else
        original_user=$(whoami)
    fi

    if [ "$original_user" == "root" ]; then
        user_home="/root"
    elif [ -n "$HOME" ]; then
        user_home="$HOME"
    else
        user_home=$(getent passwd "$original_user" | cut -d: -f6)
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
    
    local default_config_dir="$user_home/.config/ssh-manager"
    read -p "Introduce la ruta para guardar las conexiones [$default_config_dir]: " config_dir < /dev/tty
    config_dir=${config_dir:-$default_config_dir}
    
    # Expandir tilde (~) si el usuario la introduce
    eval config_dir="$config_dir"
    
    echo "Las conexiones se guardarán en: $config_dir"
    
    echo "Descargando scripts..."
    if ! curl -fsSL "$REPO_BASE_URL/ssh-manager.sh" -o "$INSTALL_DIR/$MAIN_CMD"; then
        echo "Error: No se pudo descargar el script principal."; exit 1
    fi

    chmod +x "$INSTALL_DIR/$MAIN_CMD"
    ln -sf "$INSTALL_DIR/$MAIN_CMD" "$INSTALL_DIR/$ALIAS_CMD"
    
    local master_config_file="$config_dir/config"
    echo "Creando directorio de configuración en $config_dir..."
    if [ "$(whoami)" == "$original_user" ]; then
        mkdir -p "$config_dir"
        echo "CONNECTIONS_PATH='$config_dir/connections.txt'" > "$master_config_file"
        echo "DEPS_LOG_PATH='$config_dir/installed_deps.log'" >> "$master_config_file"
        echo "TUNNELS_PID_PATH='$config_dir/tunnels.pid'" >> "$master_config_file"
        touch "$config_dir/installed_deps.log"
    else
        sudo -u "$original_user" mkdir -p "$config_dir"
        sudo -u "$original_user" bash -c "echo \"CONNECTIONS_PATH='$config_dir/connections.txt'\" > '$master_config_file'"
        sudo -u "$original_user" bash -c "echo \"DEPS_LOG_PATH='$config_dir/installed_deps.log'\" >> '$master_config_file'"
        sudo -u "$original_user" bash -c "echo \"TUNNELS_PID_PATH='$config_dir/tunnels.pid'\" >> '$master_config_file'"
        sudo -u "$original_user" touch "$config_dir/installed_deps.log"
    fi

    echo ""; echo "¡Instalación completada con éxito!"
    echo "Usa 'sshm' o 'ssh-manage' para empezar."
}
main
