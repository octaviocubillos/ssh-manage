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
REPO_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/ssh-manager.sh"
MAIN_CMD="ssh-manage"
ALIAS_CMD="sshm"

# --- LÓGICA DE INSTALACIÓN ---

main() {
    local INSTALL_DIR
    local original_user="${SUDO_USER:-$USER}"
    local user_home

    # Obtener el directorio home del usuario original
    if [ "$original_user" != "root" ] && [ -n "$SUDO_USER" ]; then
        user_home=$(eval echo "~$original_user")
    else
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
    
    # --- Preguntar por la ruta de configuración ---
    local config_dir="$user_home/.config/ssh-manager"
    local connections_file
    read -p "Introduce la ruta para guardar el archivo de conexiones [$config_dir/connections.txt]: " connections_file < /dev/tty
    connections_file=${connections_file:-"$config_dir/connections.txt"}
    
    # Expandir tilde (~) si el usuario la introduce
    eval connections_file="$connections_file"
    
    echo "Las conexiones se guardarán en: $connections_file"
    
    # Descargar el script principal
    echo "Descargando la última versión desde GitHub..."
    if ! curl -fsSL "$REPO_URL" -o "$INSTALL_DIR/$MAIN_CMD"; then
        echo "Error: No se pudo descargar el script."; exit 1
    fi

    chmod +x "$INSTALL_DIR/$MAIN_CMD"
    ln -sf "$INSTALL_DIR/$MAIN_CMD" "$INSTALL_DIR/$ALIAS_CMD"
    
    # --- Crear el directorio y el archivo de configuración central ---
    local master_config_file="$config_dir/config"

    echo "Creando directorio de configuración..."
    # Ejecutar como el usuario original para crear el directorio en su home
    if [ "$EUID" -eq 0 ] && [ "$original_user" != "root" ]; then
        sudo -u "$original_user" mkdir -p "$(dirname "$connections_file")"
        sudo -u "$original_user" bash -c "echo \"CONNECTIONS_PATH='$connections_file'\" > \"$master_config_file\""
        sudo -u "$original_user" bash -c "echo \"INSTALLED_DEPS=''\" >> \"$master_config_file\""
    else
        mkdir -p "$(dirname "$connections_file")"
        echo "CONNECTIONS_PATH='$connections_file'" > "$master_config_file"
        echo "INSTALLED_DEPS=''" >> "$master_config_file"
    fi

    echo ""
    echo "--------------------------------------------------------"
    echo " ¡Instalación completada con éxito!"
    echo "--------------------------------------------------------"
    echo "Ahora puedes usar los comandos 'ssh-manage' o 'sshm'."
    echo ""
}

main
