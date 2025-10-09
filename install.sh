#!/bin/bash

# ==============================================================================
#                 INSTALADOR DE SSH MANAGER (Versión Python)
# ==============================================================================
#
#   Este script instala la herramienta ssh-manager, instalando Python y Pip
#   si es necesario, y creando un entorno virtual para aislar las dependencias.
#
#   Uso (Linux/macOS): curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh | sudo bash
#   Uso (Termux):      curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh | bash
#
# ==============================================================================

set -e

# --- VARIABLES ---
REPO_BASE_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master"
MAIN_SCRIPT_NAME="ssh-manager.py"
INSTALL_DIR="/usr/local/bin"
MAIN_CMD="ssh-manage"
ALIAS_CMD="sshm"

# --- LÓGICA DE INSTALACIÓN DE DEPENDENCIAS BASE ---
ensure_base_deps() {
    local needs_install=false
    local install_cmd=""
    local python_pkg="python3"
    local pip_pkg="python3-pip"

    # Determinar el gestor de paquetes
    if command -v apt-get &> /dev/null; then
        install_cmd="sudo apt-get update -y && sudo apt-get install -y"
    elif command -v dnf &> /dev/null; then
        install_cmd="sudo dnf install -y"
    elif command -v yum &> /dev/null; then
        install_cmd="sudo yum install -y"
        pip_pkg="python3-pip" # EPEL puede ser necesario
    elif command -v pacman &> /dev/null; then
        install_cmd="sudo pacman -Syu --noconfirm"
        pip_pkg="python-pip"
    elif command -v zypper &> /dev/null; then
        install_cmd="sudo zypper --non-interactive install"
    elif command -v apk &> /dev/null; then
        install_cmd="sudo apk add --no-cache"
        pip_pkg="py3-pip"
    elif command -v brew &> /dev/null; then
        install_cmd="brew install"
    elif command -v pkg &> /dev/null; then
        install_cmd="pkg install -y"
        python_pkg="python"
        pip_pkg="python-pip"
    fi

    # Verificar e instalar Python
    if ! command -v python3 &> /dev/null; then
        echo "Python 3 no está instalado. Intentando instalarlo..."
        if [ -n "$install_cmd" ]; then
            eval "$install_cmd $python_pkg"
            needs_install=true
        else
            echo "[Error] No se pudo determinar el gestor de paquetes para instalar Python 3."
            exit 1
        fi
    fi

    # Verificar e instalar Pip
    if ! python3 -m ensurepip --default-pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        echo "Pip para Python 3 no está instalado. Intentando instalarlo..."
        if [ -n "$install_cmd" ]; then
             # Para CentOS 7, EPEL es necesario para python3-pip
            if command -v yum &> /dev/null && ! command -v dnf &> /dev/null; then
                sudo yum install -y epel-release
            fi
            eval "$install_cmd $pip_pkg"
            needs_install=true
        else
            echo "[Error] No se pudo determinar el gestor de paquetes para instalar Pip."
            exit 1
        fi
    fi

    if [ "$needs_install" = true ]; then
        hash -r
        echo "Dependencias base instaladas."
    fi
}


# --- LÓGICA DE INSTALACIÓN PRINCIPAL ---
main() {
    local original_user="${SUDO_USER:-$USER}"
    local user_home
    if [ "$original_user" != "root" ] && [ -n "$SUDO_USER" ]; then user_home=$(eval echo "~$original_user"); else user_home="$HOME"; fi
    
    local CONFIG_DIR="$user_home/.config/ssh-manager"
    local VENV_DIR="$CONFIG_DIR/venv"
    local WRAPPER_SCRIPT_PATH

    # Detección del entorno
    if [[ -n "$PREFIX" ]]; then
        echo "Detectado entorno Termux."
        INSTALL_DIR="$PREFIX/bin"
        WRAPPER_SCRIPT_PATH="$INSTALL_DIR/$MAIN_CMD"
    else
        echo "Detectado entorno estándar (Linux/macOS)."
        WRAPPER_SCRIPT_PATH="$INSTALL_DIR/$MAIN_CMD"
        if [ "$EUID" -ne 0 ]; then echo "[Error] Se necesitan privilegios de superusuario. Ejecuta con 'sudo'."; exit 1; fi
    fi

    echo "Iniciando la instalación de SSH Manager (Python)..."

    # 1. Asegurar Python y Pip
    ensure_base_deps

    # 2. Crear directorios y venv como el usuario original
    echo "Creando directorio de configuración y entorno virtual en $VENV_DIR..."
    sudo -u "$original_user" mkdir -p "$CONFIG_DIR"
    sudo -u "$original_user" python3 -m venv "$VENV_DIR"

    # 3. Instalar dependencias de Python
    echo "Instalando dependencias (PyYAML, rich)..."
    sudo -u "$original_user" "$VENV_DIR/bin/pip" install --upgrade pip
    sudo -u "$original_user" "$VENV_DIR/bin/pip" install -r <(curl -fsSL "$REPO_BASE_URL/requirements.txt")

    # 4. Descargar el script principal de Python
    echo "Descargando el script principal..."
    curl -fsSL "$REPO_BASE_URL/$MAIN_SCRIPT_NAME" -o "$CONFIG_DIR/$MAIN_SCRIPT_NAME"

    # 5. Crear el script 'wrapper' en /usr/local/bin
    echo "Creando el comando global '$MAIN_CMD'..."
    cat > "$WRAPPER_SCRIPT_PATH" << EOL
#!/bin/bash
# Wrapper para SSH Manager
exec "$VENV_DIR/bin/python" "$CONFIG_DIR/$MAIN_SCRIPT_NAME" "\$@"
EOL

    # 6. Dar permisos y crear alias
    chmod +x "$WRAPPER_SCRIPT_PATH"
    ln -sf "$WRAPPER_SCRIPT_PATH" "$INSTALL_DIR/$ALIAS_CMD"

    echo ""
    echo "[Éxito] ¡Instalación completada!"
    echo "Usa 'sshm' o 'ssh-manage' para empezar."
}

main

