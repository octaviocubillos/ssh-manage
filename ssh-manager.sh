#!/usr/bin/env bash

# ==============================================================================
#                 GESTOR DE CONEXIONES SSH v1.0.3 (Bash)
#                        BY OTON
# ==============================================================================
#
#   Un script de Bash para gestionar múltiples conexiones SSH, con un menú
#   interactivo navegable por flechas y funcionalidades de red avanzadas.
#
# ==============================================================================


# --- CONFIGURACIÓN PRINCIPAL ---
VERSION="1.0.20"
REPO_BASE_URL="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master"

IS_TERMUX=false
if [[ -n "$PREFIX" ]]; then IS_TERMUX=true; fi

SUDO_CMD="sudo"
if [ "$EUID" -eq 0 ]; then
    SUDO_CMD=""
fi

CONFIG_DIR="$HOME/.config/ssh-manager"
MASTER_CONFIG_FILE="$CONFIG_DIR/config"
CONNECTIONS_FILE=""
DEPS_LOG=""
TUNNELS_PID_FILE=""

load_config() {
    mkdir -p "$CONFIG_DIR"
    if [ ! -f "$MASTER_CONFIG_FILE" ]; then
        echo "CONNECTIONS_PATH=$CONFIG_DIR/connections.json" > "$MASTER_CONFIG_FILE"
        echo "DEPS_LOG_PATH=$CONFIG_DIR/installed_deps.log" >> "$MASTER_CONFIG_FILE"
        echo "TUNNELS_PID_PATH=$CONFIG_DIR/tunnels.pid" >> "$MASTER_CONFIG_FILE"
    fi
    source "$MASTER_CONFIG_FILE"
    
    # Set defaults if not present (backward compatibility)
    if [ -z "$DEPS_LOG_PATH" ]; then DEPS_LOG_PATH="$CONFIG_DIR/installed_deps.log"; fi
    if [ -z "$TUNNELS_PID_PATH" ]; then TUNNELS_PID_PATH="$CONFIG_DIR/tunnels.pid"; fi

    CONFIG_FILE="$CONNECTIONS_PATH"
    LEGACY_PATH="${CONNECTIONS_PATH%.*}.txt"
    # If config file is already .txt (user manual override), respect it but we want json
    if [[ "$CONNECTIONS_PATH" == *.txt ]]; then
         LEGACY_PATH="$CONNECTIONS_PATH"
         CONFIG_FILE="${CONNECTIONS_PATH%.*}.json"
    fi

    DEPS_LOG="$DEPS_LOG_PATH"
    TUNNELS_PID_FILE="$TUNNELS_PID_PATH"
    
    # Ensure files exist
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[]" > "$CONFIG_FILE"
    fi
    if [ ! -f "$DEPS_LOG" ]; then touch "$DEPS_LOG"; fi
    if [ ! -f "$TUNNELS_PID_FILE" ]; then touch "$TUNNELS_PID_FILE"; fi
}

VERBOSE_FLAG=""
args=()
for arg in "$@"; do
    if [ "$arg" == "--verbose" ]; then VERBOSE_FLAG="-v"; else args+=("$arg"); fi
done
set -- "${args[@]}"

RESERVED_COMMANDS=("add" "-a" "edit" "-e" "list" "-l" "connect" "-c" "browse" "-b" "delete" "-d" "update" "-u" "scp" "-s" "tunnel" "-t" "reverse-tunnel" "-rt" "proxy" "help" "-h" "--help" "version" "-v" "list-tunnels" "-lt" "stop-tunnel" "-st" "export" "-x")

# --- VERIFICACIÓN DE DEPENDENCIAS ---

show_spinner() {
    if ! command -v "tput" &> /dev/null; then while true; do sleep 1; done; return; fi
    local -r FRAMES='|/-\'; local i=0; tput civis; trap 'tput cnorm' EXIT
    while true; do printf "\b%s" "${FRAMES:i++%${#FRAMES}:1}"; sleep 0.1; done
}

install_package() {
    local pkg=$1
    local install_cmd=""

    if $IS_TERMUX; then
        install_cmd="pkg install -y $pkg"
    elif command -v apt-get &> /dev/null; then
        install_cmd="$SUDO_CMD apt-get update -y && $SUDO_CMD apt-get install -y $pkg"
    elif command -v dnf &> /dev/null; then
        install_cmd="$SUDO_CMD dnf install -y $pkg"
    elif command -v yum &> /dev/null; then
        if [ "$pkg" == "fuse-sshfs" ]; then
            install_cmd="$SUDO_CMD yum install -y epel-release && $SUDO_CMD yum install -y $pkg"
        else
            install_cmd="$SUDO_CMD yum install -y $pkg"
        fi
    elif command -v pacman &> /dev/null; then
        install_cmd="$SUDO_CMD pacman -Syu --noconfirm $pkg"
    elif command -v zypper &> /dev/null; then
        install_cmd="$SUDO_CMD zypper --non-interactive install $pkg"
    elif command -v apk &> /dev/null; then
        install_cmd="$SUDO_CMD apk add --no-cache $pkg"
    elif command -v brew &> /dev/null; then
        install_cmd="brew install $pkg"
    else
        return 1
    fi

    eval "$install_cmd" > /dev/null 2>&1
}

ensure_dependency() {
    local dep=$1
    local pkg=${2:-$1}

    # Termux specific: openssl binary is provided by openssl-tool package
    if [ "$dep" == "openssl" ] && $IS_TERMUX; then dep="openssl-tool"; fi

    # Check if dependency is already installed
    if command -v "$dep" &> /dev/null; then return 0; fi

    echo "La herramienta '$dep' es necesaria. Intentando instalar '$pkg'..."

    # Yum specific: sshfs package is named fuse-sshfs
    if command -v yum &> /dev/null && [ "$dep" == "sshfs" ]; then pkg="fuse-sshfs"; fi

    printf "Instalando...  "
    show_spinner &
    local spinner_pid=$!

    if install_package "$pkg"; then
        kill $spinner_pid &>/dev/null
        wait $spinner_pid 2>/dev/null
        printf "\b\bListo.\n"
        hash -r
        
        if ! command -v "$dep" &> /dev/null; then 
            echo "Error: La instalación de '$pkg' falló."
            return 1
        fi
        
        if ! grep -q "^$pkg$" "$DEPS_LOG"; then echo "$pkg" >> "$DEPS_LOG"; fi
    else
        kill $spinner_pid &>/dev/null
        wait $spinner_pid 2>/dev/null
        printf "\b\bFalló.\n"
        echo "Error: Gestor de paquetes no compatible o fallo en la instalación."
        return 1
    fi
    return 0
}

check_base_requirements() {
    local deps=("tput" "ssh" "jq" "openssl" "sshpass")
    local missing_deps=()

    # Check for missing dependencies
    for dep in "${deps[@]}"; do
        local check_cmd="$dep"
        # Termux specific check for openssl
        if [[ -n "$PREFIX" ]] && [ "$dep" == "openssl" ]; then check_cmd="openssl-tool"; fi
        
        if ! command -v "$dep" &> /dev/null; then
            # Handle tput/ncurses variants
            if [ "$dep" == "tput" ]; then
                if command -v ncurses-bin &> /dev/null || command -v ncurses &> /dev/null || command -v ncurses-utils &> /dev/null; then
                    continue
                fi
            fi
            # Handle ssh variants
            if [ "$dep" == "ssh" ]; then
                if command -v openssh-client &> /dev/null || command -v openssh &> /dev/null; then
                    continue
                fi
            fi
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -eq 0 ]; then
        return 0
    fi

    clear
    echo "=========================================="
    echo "      DEPENDENCIAS FALTANTES"
    echo "=========================================="
    echo "Para funcionar correctamente, SSH Manager necesita instalar:"
    echo ""
    for dep in "${missing_deps[@]}"; do
        echo " - $dep"
    done
    echo ""
    echo "=========================================="
    read -p "¿Deseas instalarlas ahora? (s/n): " confirm

    if [[ ! "$confirm" =~ ^[sS]$ ]]; then
        echo "Error: No se pueden satisfacer las dependencias. Saliendo."
        exit 1
    fi

    # Refresh sudo credentials if needed to avoid prompt during spinner
    if [ "$EUID" -ne 0 ] && [ -z "$PREFIX" ]; then
        sudo -v
    fi

    echo -n "Instalando...  "
    show_spinner &
    local spinner_pid=$!

    local install_cmd=""
    local sudo_prefix=""
    if [ "$EUID" -ne 0 ] && [ -z "$PREFIX" ]; then
        sudo_prefix="sudo"
    fi

    if [[ -n "$PREFIX" ]]; then
        install_cmd="pkg install -y"
    elif command -v apt-get &> /dev/null; then
        install_cmd="$sudo_prefix apt-get update -y && $sudo_prefix apt-get install -y"
    elif command -v dnf &> /dev/null; then
        install_cmd="$sudo_prefix dnf install -y"
    elif command -v yum &> /dev/null; then
        install_cmd="$sudo_prefix yum install -y"
    elif command -v pacman &> /dev/null; then
        install_cmd="$sudo_prefix pacman -Syu --noconfirm"
    elif command -v zypper &> /dev/null; then
        install_cmd="$sudo_prefix zypper --non-interactive install"
    elif command -v apk &> /dev/null; then
        install_cmd="$sudo_prefix apk add --no-cache"
    elif command -v brew &> /dev/null; then
        install_cmd="brew install"
    else
        kill $spinner_pid &>/dev/null
        wait $spinner_pid 2>/dev/null
        echo ""
        echo "Error: No se pudo detectar el gestor de paquetes. Instala manualmente: ${missing_deps[*]}"
        exit 1
    fi

    # Termux specific package name adjustments
    if [[ -n "$PREFIX" ]]; then
        missing_deps=("${missing_deps[@]/openssl/openssl-tool}")
    fi

    # Run installation silently
    if eval "$install_cmd ${missing_deps[*]}" > /dev/null 2>&1; then
        kill $spinner_pid &>/dev/null
        wait $spinner_pid 2>/dev/null
        printf "\b\bListo.\n"
    else
        kill $spinner_pid &>/dev/null
        wait $spinner_pid 2>/dev/null
        printf "\b\bFalló.\n"
        echo "Error al instalar dependencias. Intenta instalarlas manualmente."
        exit 1
    fi
    
    # Verify installation
    for dep in "${missing_deps[@]}"; do
         # Re-check logic simplified for verification
         if ! command -v "$dep" &> /dev/null && ! command -v "${dep%-tool}" &> /dev/null; then
             echo "Advertencia: Parece que $dep no se instaló correctamente."
         fi
    done
    
    echo "Dependencias instaladas. Continuando..."
    sleep 2
}

# --- FUNCIONES DE LA APLICACIÓN ---

show_usage() {
    echo "Uso: $(basename "$0") [comando] [argumentos...]"
    echo "  o: $(basename "$0") <alias> [comando-remoto...]"
    echo ""
    echo "Comandos de Conexión:"
    printf "  %-35s %s\n" "add,    -a" "Añade una nueva conexión."
    printf "  %-35s %s\n" "edit,   -e <alias> [campo]" "Edita una conexión (campo: host,user,port,auth,dir,cmd)."
    printf "  %-35s %s\n" "list,   -l [-a | -p]" "Lista conexiones. -a: detalles, -p: ver contraseñas."
    printf "  %-35s %s\n" "connect,-c <alias> [cmd]" "Conecta a un servidor (o usa solo el <alias>)."
    printf "  %-35s %s\n" "delete, -d <alias>" "Elimina una conexión."
    if ! $IS_TERMUX; then
        printf "  %-35s %s\n" "browse, -b <alias>" "Abre explorador SFTP visual."
    fi
    echo ""
    echo "Comandos de Utilidad:"
    printf "  %-35s %s\n" "scp,    -s <orig> <dest>" "Copia archivos (ej: alias:ruta/archivo ./local)."
    printf "  %-35s %s\n" "tunnel, -t <alias> <spec>" "Crea túnel local (spec: puerto_local:host_dest:puerto_dest)."
    printf "  %-35s %s\n" "reverse-tunnel, -rt <alias> <spec>" "Crea túnel reverso (spec: puerto_remoto:host_local:puerto_local)."
    printf "  %-35s %s\n" "proxy <alias> <spec>" "Asegura un túnel local y lo expone como ProxyCommand."
    printf "  %-35s %s\n" "list-tunnels,   -lt" "Lista túneles activos en segundo plano."
    printf "  %-35s %s\n" "stop-tunnel,    -st [pid]" "Detiene un túnel activo."
    echo ""
    echo "Otros:"
    printf "  %-35s %s\n" "update, -u" "Busca y aplica actualizaciones."
    printf "  %-35s %s\n" "export, -x" "Exporta las conexiones a ~/.ssh/config."
    printf "  %-35s %s\n" "version,-v" "Muestra la versión actual."
    printf "  %-35s %s\n" "help,   -h" "Muestra esta ayuda."
    echo ""
    echo "Opciones Globales:"
    printf "  %-35s %s\n" "--verbose" "Activa modo detallado para comandos de red."
    echo ""
    echo "Si no se especifican comandos, se abrirá el menú interactivo."
}

show_version() { echo "ssh-manager version $VERSION"; }
is_alias_reserved() { local alias_to_check=$1; for cmd in "${RESERVED_COMMANDS[@]}"; do if [[ "$cmd" == "$alias_to_check" ]]; then return 0; fi; done; return 1; }

read_menu_key() {
    local key
    IFS= read -rsn1 key
    if [[ $key == $'\x1b' ]]; then
        local rest
        IFS= read -rsn2 -t 0.05 rest || true
        key+="$rest"
    fi
    printf '%s' "$key"
}

select_alias() {
    local prompt_text=$1
    # Read aliases and details into an array
    local options=()
    local aliases=()
    
    if [ ! -s "$CONFIG_FILE" ] || [ "$(jq 'length' "$CONFIG_FILE" 2>/dev/null)" -eq 0 ]; then
        echo "Error: No hay conexiones guardadas." >&2
        read -p "Presiona Enter para continuar..." >&2
        return 1
    fi

    while IFS='|' read -r alias host user port; do
        if [ -z "$alias" ] || [ "$alias" == "null" ]; then continue; fi
        aliases+=("$alias")
        options+=("$alias ($user@$host)")
    done < <(jq -r '.[] | "\(.alias)|\(.host)|\(.user)|\(.port)"' "$CONFIG_FILE")

    if [ ${#options[@]} -eq 0 ]; then echo "Error: No hay conexiones guardadas." >&2; return 1; fi
    
    options+=("Volver al menú principal")

    local selected=0
    while true; do
        clear >&2
        echo "$prompt_text" >&2
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/Esc/q para volver." >&2
        echo "------------------------------------------" >&2

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}" >&2
            else
                echo "   ${options[$i]}" >&2
            fi
        done
        echo "------------------------------------------" >&2

        key=$(read_menu_key)

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|$'\x1b'|q|Q) # Left, Esc or q - Back
                return 1
                ;;
            ''|'[C') # Enter or Right - Select
                if [ $selected -eq $((${#options[@]} - 1)) ]; then
                    return 1 # "Volver al menú principal" selected
                else
                    echo "${aliases[$selected]}"
                    return 0
                fi
                ;;
        esac
    done
}

add_connection() {
    echo "Añadir nueva conexión SSH:"
    read -p "Alias (nombre corto): " alias
    if [ -z "$alias" ]; then echo "Cancelado."; return; fi
    
    if jq -e --arg alias "$alias" '.[] | select(.alias == $alias)' "$CONFIG_FILE" > /dev/null; then
        echo "Error: El alias '$alias' ya existe."
        return
    fi

    read -p "Host (IP o dominio): " host
    read -p "Usuario: " user
    read -p "Puerto [22]: " port; port=${port:-22}
    
    echo "Método de autenticación:"
    echo "1. Clave SSH (pem/pub)"
    echo "2. Contraseña (texto plano)"
    echo "3. Contraseña (encriptada)"
    echo "4. Ninguna"
    read -p "Opción [1]: " auth_opt; auth_opt=${auth_opt:-1}

    local key=""
    local pass=""
    
    case "$auth_opt" in
        1)
            read -p "Ruta absoluta a la clave: " key
            if [ ! -f "$key" ]; then echo "Advertencia: El archivo de clave no existe."; fi
            ;;
        2)
            read -s -p "Contraseña: " pass; echo ""
            ;;
        3)
            ensure_dependency "openssl" || return
            read -s -p "Palabra clave para encriptar: " keyword; echo ""
            read -s -p "Contraseña a encriptar: " raw_pass; echo ""
            local encrypted_pass
            encrypted_pass=$(echo -n "$raw_pass" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword")
            pass="enc:$encrypted_pass"
            ;;
        4)
            ;;
        *)
            echo "Opción inválida, se usará 'Ninguna'."
            ;;
    esac

    read -p "Directorio remoto inicial (opcional): " remote_dir
    read -p "Comando a ejecutar al conectar (opcional): " cmd
    read -p "Host de salto (alias, opcional): " jump
    
    # Add to JSON
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg alias "$alias" \
       --arg host "$host" \
       --arg user "$user" \
       --arg port "$port" \
       --arg key "$key" \
       --arg pass "$pass" \
       --arg remote_dir "$remote_dir" \
       --arg cmd "$cmd" \
       --arg jump "$jump" \
       '. + [{alias: $alias, host: $host, user: $user, port: $port, key: $key, pass: $pass, remote_dir: $remote_dir, cmd: $cmd, jump: $jump}]' \
       "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"

    echo "Conexión '$alias' guardada."
}

edit_connection() {
    local alias_to_edit=$1
    local field_to_edit=$2

    if [ -z "$alias_to_edit" ]; then
        alias_to_edit=$(select_alias "Editar conexión")
        if [ $? -ne 0 ]; then return 1; fi
    fi

    # Get connection data from JSON
    local connection_data
    connection_data=$(jq -r --arg alias "$alias_to_edit" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)|\(.remote_dir)|\(.cmd)|\(.jump)"' "$CONFIG_FILE")
    
    if [ -z "$connection_data" ]; then echo "Error: Alias no encontrado."; return 1; fi
    
    IFS='|' read -r old_host old_user old_port old_key old_pass old_remote_dir old_cmd old_jump <<< "$connection_data"
    
    # Handle nulls
    if [ "$old_key" == "null" ]; then old_key=""; fi
    if [ "$old_pass" == "null" ]; then old_pass=""; fi
    if [ "$old_remote_dir" == "null" ]; then old_remote_dir=""; fi
    if [ "$old_cmd" == "null" ]; then old_cmd=""; fi
    if [ "$old_jump" == "null" ]; then old_jump=""; fi

    if [ -n "$field_to_edit" ]; then
        # Single field edit mode (kept for potential CLI usage, though user wants wizard)
        local host="$old_host" user="$old_user" port="$old_port" key="$old_key" pass="$old_pass" remote_dir="$old_remote_dir" cmd="$old_cmd" jump="$old_jump"
        
        case "$field_to_edit" in
            host) read -p "Nuevo Host [$host]: " new_value; host=${new_value:-$host} ;;
            user) read -p "Nuevo Usuario [$user]: " new_value; user=${new_value:-$user} ;;
            port) read -p "Nuevo Puerto [$port]: " new_value; port=${new_value:-$port} ;;
            auth)
                echo "1. Clave SSH (pem/pub)"
                echo "2. Contraseña (texto plano)"
                echo "3. Contraseña (encriptada)"
                echo "4. Ninguna"
                read -p "Opción: " auth_opt
                
                case "$auth_opt" in
                    1)
                        read -p "Nueva ruta clave: " key
                        pass=""
                        ;;
                    2)
                        read -s -p "Nueva contraseña: " pass; echo ""
                        key=""
                        ;;
                    3)
                        ensure_dependency "openssl" || return
                        read -s -p "Palabra clave para encriptar: " keyword; echo ""
                        read -s -p "Nueva contraseña a encriptar: " raw_pass; echo ""
                        local encrypted_pass
                        encrypted_pass=$(echo -n "$raw_pass" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword")
                        pass="enc:$encrypted_pass"
                        key=""
                        ;;
                    4)
                        key=""
                        pass=""
                        ;;
                    *)
                        echo "Opción inválida."
                        ;;
                esac
                ;;
            dir) read -p "Nuevo Directorio [$remote_dir]: " new_value; remote_dir=${new_value:-$remote_dir} ;;
            cmd) read -p "Nuevo Comando [$cmd]: " new_value; cmd=${new_value:-$cmd} ;;
            jump) read -p "Nuevo Host de salto [$jump]: " new_value; jump=${new_value:-$jump} ;;
            *) echo "Campo inválido."; return 1 ;;
        esac
    else
        # Wizard mode
        echo "Editando '$alias_to_edit'. Presiona Enter para mantener el valor actual."
        
        # Host
        while true; do
            read -p "Nuevo Host [$old_host]: " host
            host=${host:-$old_host}
            if [ -z "$host" ]; then echo "Host obligatorio."; else break; fi
        done

        # User
        while true; do
            read -p "Nuevo Usuario [$old_user]: " user
            user=${user:-$old_user}
            if [ -z "$user" ]; then echo "Usuario obligatorio."; else break; fi
        done

        # Port
        read -p "Nuevo Puerto [$old_port]: " port
        port=${port:-$old_port}

        # Remote Dir
        read -p "Nuevo Directorio [$old_remote_dir]: " remote_dir
        remote_dir=${remote_dir:-$old_remote_dir}

        # Command
        read -p "Nuevo Comando [$old_cmd]: " cmd
        cmd=${cmd:-$old_cmd}

        # Jump
        read -p "Nuevo Host de salto (alias) [$old_jump]: " jump
        jump=${jump:-$old_jump}

        # Auth
        local key="$old_key"
        local pass="$old_pass"
        read -p "¿Cambiar autenticación? (s/n): " change_auth
        if [[ "$change_auth" =~ ^[sS]$ ]]; then
            echo "1. Clave SSH (pem/pub)"
            echo "2. Contraseña (texto plano)"
            echo "3. Contraseña (encriptada)"
            echo "4. Ninguna"
            read -p "Opción: " auth_opt
            
            case "$auth_opt" in
                1)
                    read -p "Nueva ruta clave: " key
                    pass=""
                    ;;
                2)
                    read -s -p "Nueva contraseña: " pass; echo ""
                    key=""
                    ;;
                3)
                    ensure_dependency "openssl" || return
                    read -s -p "Palabra clave para encriptar: " keyword; echo ""
                    read -s -p "Nueva contraseña a encriptar: " raw_pass; echo ""
                    local encrypted_pass
                    encrypted_pass=$(echo -n "$raw_pass" | openssl enc -aes-256-cbc -a -salt -pbkdf2 -pass pass:"$keyword")
                    pass="enc:$encrypted_pass"
                    key=""
                    ;;
                4)
                    key=""
                    pass=""
                    ;;
                *)
                    echo "Opción inválida, no se cambiará la autenticación."
                    key="$old_key"
                    pass="$old_pass"
                    ;;
            esac
        fi
    fi

    # Update JSON
    local temp_file
    temp_file=$(mktemp)
    
    jq --arg alias "$alias_to_edit" \
       --arg host "$host" \
       --arg user "$user" \
       --arg port "$port" \
       --arg key "$key" \
       --arg pass "$pass" \
       --arg remote_dir "$remote_dir" \
       --arg cmd "$cmd" \
       --arg jump "$jump" \
       'map(if .alias == $alias then {alias: $alias, host: $host, user: $user, port: $port, key: $key, pass: $pass, remote_dir: $remote_dir, cmd: $cmd, jump: $jump} else . end)' \
       "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
       
    echo "Conexión actualizada."
}

connect_to_host() {
    local alias_to_connect=$1
    local remote_command=$2

    if [ -z "$alias_to_connect" ]; then
        alias_to_connect=$(select_alias "Conectar a servidor")
        if [ $? -ne 0 ]; then return 1; fi
    fi

    # Get connection data from JSON
    local connection_data
    connection_data=$(jq -r --arg alias "$alias_to_connect" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)|\(.remote_dir)|\(.cmd)|\(.jump)"' "$CONFIG_FILE")
    
    if [ -z "$connection_data" ]; then echo "Error: Alias no encontrado."; return 1; fi
    
    IFS='|' read -r host user port key pass remote_dir default_cmd jump <<< "$connection_data"
    
    # Handle nulls
    if [ "$key" == "null" ]; then key=""; fi
    if [ "$pass" == "null" ]; then pass=""; fi
    if [ "$remote_dir" == "null" ]; then remote_dir=""; fi
    if [ "$default_cmd" == "null" ]; then default_cmd=""; fi
    if [ "$jump" == "null" ]; then jump=""; fi

    local command_to_run="${remote_command:-$default_cmd}"
    
    echo "Conectando a $user@$host en el puerto $port..."
    
    local decrypted_pass=""
    if [[ "$pass" == enc:* ]]; then
        ensure_dependency "openssl" || return 1
        read -s -p "Palabra clave: " keyword; echo ""
        local encrypted_data=${pass#enc:}
        decrypted_pass=$(echo "$encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$keyword" 2>/dev/null)
        if [ -z "$decrypted_pass" ]; then echo "Error de desencriptación."; return 1; fi
    elif [ -n "$pass" ]; then
        decrypted_pass="$pass"
    fi

    local final_command="$command_to_run"
    if [ -n "$remote_dir" ]; then
        if [ -n "$final_command" ]; then
            final_command="cd \"$remote_dir\" && $final_command"
        else
            final_command="cd \"$remote_dir\" && exec \${SHELL:-bash} -l"
        fi
    fi

    if [ -n "$final_command" ] && [ "$final_command" != "$remote_command" ]; then
        echo "Iniciando en dir: $remote_dir"
    elif [ -n "$remote_command" ]; then
        echo "Ejecutando: $remote_command"
    fi

    local tty_option=""
    if [ -n "$final_command" ]; then tty_option="-t"; fi

    local jump_args=""
    local jump_sshpass_cmd=""
    
    if [ -n "$jump" ]; then
        local jump_data
        jump_data=$(jq -r --arg alias "$jump" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)"' "$CONFIG_FILE")
        if [ -n "$jump_data" ]; then
            IFS='|' read -r j_host j_user j_port j_key j_pass <<< "$jump_data"
            
            local j_cmd=""
            
            # Handle jump host password decryption
            local j_decrypted_pass=""
            if [[ "$j_pass" == enc:* ]]; then
                ensure_dependency "openssl" || return 1
                # We ask for the jump master password if it's encrypted
                read -s -p "Palabra clave para salto ($jump): " j_keyword; echo ""
                local j_encrypted_data=${j_pass#enc:}
                j_decrypted_pass=$(echo "$j_encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$j_keyword" 2>/dev/null)
                if [ -z "$j_decrypted_pass" ]; then echo "Error de desencriptación para el salto."; return 1; fi
            elif [ -n "$j_pass" ] && [ "$j_pass" != "null" ]; then
                j_decrypted_pass="$j_pass"
            fi

            if [ -n "$j_decrypted_pass" ]; then
                ensure_dependency "sshpass" || return 1
                # Inject sshpass into the jump command itself
                j_cmd="sshpass -p '$j_decrypted_pass' ssh -o StrictHostKeyChecking=no"
            else
                j_cmd="ssh -o StrictHostKeyChecking=no"
            fi
            
            # Handle jump host port
            if [ -n "$j_port" ] && [ "$j_port" != "22" ] && [ "$j_port" != "null" ]; then
                j_cmd+=" -p $j_port"
            fi

            # Handle jump host key
            if [ -n "$j_key" ] && [ "$j_key" != "null" ]; then
                j_cmd+=" -i $j_key"
            fi
            
            # Use ProxyCommand instead of -J for better sshpass compatibility
            jump_args="-o ProxyCommand=\"$j_cmd -W %h:%p $j_user@$j_host\""
        else
            echo "Advertencia: Alias de salto '$jump' no encontrado en la configuración."
        fi
    fi

    if [ -n "$key" ]; then
        eval "ssh $VERBOSE_FLAG $tty_option $jump_args -i \"$key\" -p \"$port\" \"$user@$host\" \"$final_command\""
    elif [ -n "$decrypted_pass" ]; then
        ensure_dependency "sshpass" || return 1
        export SSHPASS="$decrypted_pass"
        eval "sshpass -e ssh $VERBOSE_FLAG $tty_option $jump_args -p \"$port\" \"$user@$host\" -o StrictHostKeyChecking=no \"$final_command\""
        unset SSHPASS
    else
        eval "ssh $VERBOSE_FLAG $tty_option $jump_args -p \"$port\" \"$user@$host\" \"$final_command\""
    fi
}

delete_connection() {
    local alias_to_delete=$1
    if [ -z "$alias_to_delete" ]; then
        alias_to_delete=$(select_alias "Eliminar conexión")
        if [ $? -ne 0 ]; then return 1; fi
    fi

    if ! jq -e --arg alias "$alias_to_delete" '.[] | select(.alias == $alias)' "$CONFIG_FILE" > /dev/null; then
        echo "Error: Alias no encontrado."
        return 1
    fi

    read -p "¿Estás seguro de eliminar '$alias_to_delete'? (s/n): " confirm
    if [[ "$confirm" =~ ^[sS]$ ]]; then
        local temp_file
        temp_file=$(mktemp)
        
        jq --arg alias "$alias_to_delete" 'map(select(.alias != $alias))' "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
        echo "Conexión eliminada."
    else
        echo "Cancelado."
    fi
}

update_script() {
    echo "Buscando actualizaciones..."
    local repo_ref
    repo_ref=$(curl -fsSL "https://api.github.com/repos/octaviocubillos/ssh-manage/commits/master" | jq -r '.sha // empty' 2>/dev/null || true)
    local remote_base_url="$REPO_BASE_URL"
    if [ -n "$repo_ref" ]; then
        remote_base_url="https://raw.githubusercontent.com/octaviocubillos/ssh-manage/$repo_ref"
    fi
    local remote_version; remote_version=$(curl -fsSL "$remote_base_url/version.txt?$(date +%s)" 2>/dev/null)
    if [ -z "$remote_version" ]; then echo "No se pudo verificar la versión remota."; return 1; fi
    if [ "$VERSION" == "$remote_version" ]; then echo "Ya tienes la última versión instalada ($VERSION)."; else
        echo "¡Nueva versión disponible! ($remote_version)"; read -p "¿Deseas actualizar ahora? (s/n): " choice
        if [[ "$choice" =~ ^[sS]$ ]]; then
            local install_script_url="$remote_base_url/install.sh?$(date +%s)"
            local exec_cmd="curl -fsSL $install_script_url | $SUDO_CMD bash"
            if $IS_TERMUX; then exec_cmd="curl -fsSL $install_script_url | bash"; fi
            echo "Ejecutando el instalador..."
            sh -c "$exec_cmd"
            echo "Actualización completada. Por favor, reinicia el script."
            exit 0
        else echo "Actualización cancelada."; fi
    fi
}

run_scp() {
    ensure_dependency "scp" "openssh-client" || ensure_dependency "scp" "openssh" || return 1
    local source=$1
    local destination=$2
    
    if [ -z "$source" ] || [ -z "$destination" ]; then
        echo "Error: se requieren un origen y un destino."
        show_usage
        return 1
    fi

    local alias_str=""
    if [[ "$source" == *":"* ]]; then
        alias_str=$(echo "$source" | cut -d: -f1)
    elif [[ "$destination" == *":"* ]]; then
        alias_str=$(echo "$destination" | cut -d: -f1)
    else
        echo "Error: el origen o el destino debe tener el formato <alias>:/ruta"
        show_usage
        return 1
    fi

    # Get connection data from JSON
    local connection_data
    connection_data=$(jq -r --arg alias "$alias_str" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)|\(.jump)"' "$CONFIG_FILE")
    
    if [ -z "$connection_data" ]; then echo "Error: Alias '$alias_str' no encontrado."; return 1; fi
    
    IFS='|' read -r host user port key pass jump <<< "$connection_data"
    
    if [ "$key" == "null" ]; then key=""; fi
    if [ "$pass" == "null" ]; then pass=""; fi
    if [ "$jump" == "null" ]; then jump=""; fi

    local decrypted_pass=""
    if [[ "$pass" == enc:* ]]; then
        ensure_dependency "openssl" || return 1
        read -s -p "Palabra clave: " keyword; echo ""
        local encrypted_data=${pass#enc:}
        decrypted_pass=$(echo "$encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$keyword" 2>/dev/null)
        if [ -z "$decrypted_pass" ]; then echo "Error de desencriptación."; return 1; fi
    elif [ -n "$pass" ]; then
        decrypted_pass="$pass"
    fi

    local scp_command="scp $VERBOSE_FLAG -r -P $port"
    if [ -n "$key" ]; then scp_command+=" -i $key"; fi

    if [ -n "$jump" ]; then
        local jump_data
        jump_data=$(jq -r --arg alias "$jump" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)"' "$CONFIG_FILE")
        if [ -n "$jump_data" ]; then
            IFS='|' read -r j_host j_user j_port j_key j_pass <<< "$jump_data"
            
            local j_cmd=""
            local j_decrypted_pass=""
            if [[ "$j_pass" == enc:* ]]; then
                ensure_dependency "openssl" || return 1
                read -s -p "Palabra clave para salto ($jump): " j_keyword; echo ""
                local j_encrypted_data=${j_pass#enc:}
                j_decrypted_pass=$(echo "$j_encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$j_keyword" 2>/dev/null)
                if [ -z "$j_decrypted_pass" ]; then echo "Error de desencriptación para el salto."; return 1; fi
            elif [ -n "$j_pass" ] && [ "$j_pass" != "null" ]; then
                j_decrypted_pass="$j_pass"
            fi

            if [ -n "$j_decrypted_pass" ]; then
                ensure_dependency "sshpass" || return 1
                j_cmd="sshpass -p '$j_decrypted_pass' ssh -o StrictHostKeyChecking=no"
            else
                j_cmd="ssh -o StrictHostKeyChecking=no"
            fi
            
            if [ -n "$j_port" ] && [ "$j_port" != "22" ] && [ "$j_port" != "null" ]; then j_cmd+=" -p $j_port"; fi
            if [ -n "$j_key" ] && [ "$j_key" != "null" ]; then j_cmd+=" -i $j_key"; fi
            scp_command+=" -o ProxyCommand=\"$j_cmd -W %h:%p $j_user@$j_host\""
        else
            echo "Advertencia: Alias de salto '$jump' no encontrado."
        fi
    fi

    local final_source="$source"
    local final_destination="$destination"
    
    final_source=${final_source/$alias_str/$user@$host}
    final_destination=${final_destination/$alias_str/$user@$host}

    echo "Copiando archivos..."
    if [ -n "$decrypted_pass" ]; then
        ensure_dependency "sshpass" || return 1
        export SSHPASS="$decrypted_pass"
        eval "sshpass -e $scp_command \"$final_source\" \"$final_destination\""
        unset SSHPASS
    else
        eval "$scp_command \"$final_source\" \"$final_destination\""
    fi
    echo "Copia completada."
}

run_tunnel() {
    local alias_str=$1
    local tunnel_spec=$2
    local reverse=${3:-false}
    local background=${4:-false}
    local tunnel_kind=${5:-tunnel}

    if [ -z "$alias_str" ] || [ -z "$tunnel_spec" ]; then
        echo "Error: se requiere un alias y una especificación de túnel."
        show_usage
        return 1
    fi

    # Get connection data from JSON
    local connection_data
    connection_data=$(jq -r --arg alias "$alias_str" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)|\(.jump)"' "$CONFIG_FILE")
    
    if [ -z "$connection_data" ]; then echo "Error: Alias '$alias_str' no encontrado."; return 1; fi
    
    IFS='|' read -r host user port key pass jump <<< "$connection_data"
    
    if [ "$key" == "null" ]; then key=""; fi
    if [ "$pass" == "null" ]; then pass=""; fi
    if [ "$jump" == "null" ]; then jump=""; fi

    local decrypted_pass=""
    if [[ "$pass" == enc:* ]]; then
        ensure_dependency "openssl" || return 1
        read -s -p "Palabra clave: " keyword; echo ""
        local encrypted_data=${pass#enc:}
        decrypted_pass=$(echo "$encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$keyword" 2>/dev/null)
        if [ -z "$decrypted_pass" ]; then echo "Error de desencriptación."; return 1; fi
    elif [ -n "$pass" ]; then
        decrypted_pass="$pass"
    fi

    local tunnel_flag="-L"
    local tunnel_type="local"
    if [ "$reverse" = true ]; then
        tunnel_flag="-R"
        tunnel_type="reverso"
    fi

    local ssh_command="ssh $VERBOSE_FLAG -o StrictHostKeyChecking=no -o ExitOnForwardFailure=yes -N $tunnel_flag $tunnel_spec -p $port"
    if [ -n "$key" ]; then ssh_command+=" -i $key"; fi

    if [ -n "$jump" ]; then
        local jump_data
        jump_data=$(jq -r --arg alias "$jump" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)"' "$CONFIG_FILE")
        if [ -n "$jump_data" ]; then
            IFS='|' read -r j_host j_user j_port j_key j_pass <<< "$jump_data"
            
            local j_cmd=""
            local j_decrypted_pass=""
            if [[ "$j_pass" == enc:* ]]; then
                ensure_dependency "openssl" || return 1
                read -s -p "Palabra clave para salto ($jump): " j_keyword; echo ""
                local j_encrypted_data=${j_pass#enc:}
                j_decrypted_pass=$(echo "$j_encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$j_keyword" 2>/dev/null)
                if [ -z "$j_decrypted_pass" ]; then echo "Error de desencriptación para el salto."; return 1; fi
            elif [ -n "$j_pass" ] && [ "$j_pass" != "null" ]; then
                j_decrypted_pass="$j_pass"
            fi

            if [ -n "$j_decrypted_pass" ]; then
                ensure_dependency "sshpass" || return 1
                j_cmd="sshpass -p '$j_decrypted_pass' ssh -o StrictHostKeyChecking=no"
            else
                j_cmd="ssh -o StrictHostKeyChecking=no"
            fi
            
            if [ -n "$j_port" ] && [ "$j_port" != "22" ] && [ "$j_port" != "null" ]; then j_cmd+=" -p $j_port"; fi
            if [ -n "$j_key" ] && [ "$j_key" != "null" ]; then j_cmd+=" -i $j_key"; fi
            ssh_command+=" -o ProxyCommand=\"$j_cmd -W %h:%p $j_user@$j_host\""
        else
            echo "Advertencia: Alias de salto '$jump' no encontrado."
        fi
    fi

    if [ "$background" = true ]; then
        echo "Estableciendo túnel SSH $tunnel_type en segundo plano..."
    else
        echo "Estableciendo túnel SSH $tunnel_type. Presiona Ctrl+C para cerrarlo."
    fi

    if [ "$background" = true ]; then
        local tunnel_pid
        local safe_alias
        safe_alias=$(echo "$alias_str" | tr -c '[:alnum:]_.-' '_')
        local log_file="$CONFIG_DIR/tunnel-${safe_alias}-$(date +%s).log"

        if [ -n "$decrypted_pass" ]; then
            ensure_dependency "sshpass" || return 1
            export SSHPASS="$decrypted_pass"
            eval "nohup sshpass -e $ssh_command \"$user@$host\" > \"$log_file\" 2>&1 & tunnel_pid=\$!"
            unset SSHPASS
        else
            eval "nohup $ssh_command \"$user@$host\" > \"$log_file\" 2>&1 & tunnel_pid=\$!"
        fi

        sleep 1
        if [ -n "$tunnel_pid" ] && ps -p "$tunnel_pid" > /dev/null; then
            echo "$tunnel_pid|$alias_str|$tunnel_spec|$tunnel_kind" >> "$TUNNELS_PID_FILE"
            echo "Túnel creado en segundo plano con PID: $tunnel_pid"
        else
            echo "Error: Falló la creación del túnel en segundo plano."
            if [ -s "$log_file" ]; then
                echo "Log del túnel ($log_file):"
                sed -n '1,20p' "$log_file"
            fi
            return 1
        fi
    elif [ -n "$decrypted_pass" ]; then
        ensure_dependency "sshpass" || return 1
        export SSHPASS="$decrypted_pass"
        eval "sshpass -e $ssh_command \"$user@$host\""
        unset SSHPASS
    else
        eval "$ssh_command \"$user@$host\""
    fi
}

run_proxy() {
    local alias_str=$1
    local tunnel_spec=$2

    if [ -z "$alias_str" ] || [ -z "$tunnel_spec" ]; then
        echo "Error: se requiere un alias y una especificación de túnel." >&2
        return 1
    fi

    local local_port=${tunnel_spec%%:*}
    if [ -z "$local_port" ] || [ "$local_port" = "$tunnel_spec" ]; then
        echo "Error: spec inválido. Usa puerto_local:host_dest:puerto_dest." >&2
        return 1
    fi

    local nc_cmd=""
    if command -v nc >/dev/null 2>&1; then
        nc_cmd="nc"
    elif command -v ncat >/dev/null 2>&1; then
        nc_cmd="ncat"
    elif command -v netcat >/dev/null 2>&1; then
        nc_cmd="netcat"
    else
        echo "Error: se requiere nc, ncat o netcat para usar proxy." >&2
        return 1
    fi

    run_tunnel "$alias_str" "$tunnel_spec" false true proxy >/dev/null 2>&1 || true
    exec "$nc_cmd" 127.0.0.1 "$local_port"
}

list_tunnels() {
    if [ ! -s "$TUNNELS_PID_FILE" ]; then echo "No hay túneles activos gestionados."; return; fi
    local temp_pid_file; temp_pid_file=$(mktemp); local active_tunnels=false
    echo "Túneles/proxies activos en segundo plano:"; echo "-----------------------------------------"
    while IFS='|' read -r pid alias_str spec kind || [ -n "$pid" ]; do
        if ps -p "$pid" > /dev/null; then
            kind=${kind:-tunnel}
            printf "  PID: %-10s | Tipo: %-6s | Alias: %-15s | Spec: %s\n" "$pid" "$kind" "$alias_str" "$spec"
            echo "$pid|$alias_str|$spec|$kind" >> "$temp_pid_file"; active_tunnels=true
        fi
    done < "$TUNNELS_PID_FILE"
    if [ "$active_tunnels" = false ]; then echo "No se encontraron túneles activos. Limpiando registro..."; fi
    mv "$temp_pid_file" "$TUNNELS_PID_FILE"
}

select_tunnel() {
    if [ ! -s "$TUNNELS_PID_FILE" ]; then echo "No hay túneles activos gestionados." >&2; return 1; fi
    
    local options=()
    local pids=()
    
    # Filter active tunnels
    local temp_pid_file; temp_pid_file=$(mktemp)
    while IFS='|' read -r pid alias_str spec kind || [ -n "$pid" ]; do
        if ps -p "$pid" > /dev/null; then
            kind=${kind:-tunnel}
            options+=("$pid - $kind - $alias_str ($spec)")
            pids+=("$pid")
            echo "$pid|$alias_str|$spec|$kind" >> "$temp_pid_file"
        fi
    done < "$TUNNELS_PID_FILE"
    mv "$temp_pid_file" "$TUNNELS_PID_FILE"

    if [ ${#options[@]} -eq 0 ]; then echo "No hay túneles activos." >&2; return 1; fi
    options+=("Volver")

    local selected=0
    while true; do
        clear >&2
        echo "Selecciona el túnel a detener:" >&2
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/Esc/q para volver." >&2
        echo "------------------------------------------" >&2

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}" >&2
            else
                echo "   ${options[$i]}" >&2
            fi
        done
        echo "------------------------------------------" >&2

        key=$(read_menu_key)

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|$'\x1b'|q|Q) # Left, Esc or q - Back
                return 1
                ;;
            ''|'[C') # Enter or Right - Select
                if [ $selected -eq $((${#options[@]} - 1)) ]; then
                    return 1 # "Volver" selected
                else
                    echo "${pids[$selected]}"
                    return 0
                fi
                ;;
        esac
    done
}

stop_tunnel() {
    local pid_to_kill=$1
    if [ -z "$pid_to_kill" ]; then
        pid_to_kill=$(select_tunnel)
        if [ $? -ne 0 ] || [ -z "$pid_to_kill" ]; then return 1; fi
    fi
    
    if grep -q "^${pid_to_kill}|" "$TUNNELS_PID_FILE"; then
        if kill "$pid_to_kill"; then 
            echo "Túnel con PID $pid_to_kill detenido."
            grep -v "^${pid_to_kill}|" "$TUNNELS_PID_FILE" > "${TUNNELS_PID_FILE}.tmp" && mv "${TUNNELS_PID_FILE}.tmp" "$TUNNELS_PID_FILE"
        else 
            echo "Error al detener el proceso."
        fi
    else 
        echo "Error: No se encontró un túnel gestionado con el PID $pid_to_kill."
    fi
}

browse_sftp() {
    if $IS_TERMUX; then
        echo "Error: La función 'browse' no está disponible en Termux."
        return 1
    fi

    ensure_dependency "mc" || return 1
    ensure_dependency "sshfs" || return 1
    
    # ... (lógica de fuse checks omitida por brevedad)
    
    local alias_to_browse=$1
    if [ -z "$alias_to_browse" ]; then
        alias_to_browse=$(select_alias "Explorar archivos")
        if [ $? -ne 0 ]; then return 1; fi
    fi

    # Get connection data from JSON
    local connection_data
    connection_data=$(jq -r --arg alias "$alias_to_browse" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)|\(.remote_dir)|\(.jump)"' "$CONFIG_FILE")
    
    if [ -z "$connection_data" ]; then echo "Error: Alias no encontrado."; return 1; fi
    
    IFS='|' read -r host user port key pass remote_dir jump <<< "$connection_data"
    
    if [ "$key" == "null" ]; then key=""; fi
    if [ "$pass" == "null" ]; then pass=""; fi
    if [ "$remote_dir" == "null" ]; then remote_dir=""; fi
    if [ "$jump" == "null" ]; then jump=""; fi

    local decrypted_pass=""
    if [[ "$pass" == enc:* ]]; then
        ensure_dependency "openssl" || return 1
        read -s -p "Palabra clave: " keyword; echo ""
        local encrypted_data=${pass#enc:}
        decrypted_pass=$(echo "$encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$keyword" 2>/dev/null)
        if [ -z "$decrypted_pass" ]; then echo "Error de desencriptación."; return 1; fi
    elif [ -n "$pass" ]; then
        decrypted_pass="$pass"
    fi

    local MOUNT_POINT
    MOUNT_POINT=$(mktemp -d)
    
    trap 'fusermount -u "$MOUNT_POINT" 2>/dev/null; rmdir "$MOUNT_POINT" 2>/dev/null; echo "Conexión SFTP cerrada.";' INT TERM EXIT
    
    echo "Montando sistema de archivos remoto en $MOUNT_POINT..."
    
    local sshfs_opts="-p $port -o StrictHostKeyChecking=no"
    if ! $IS_TERMUX; then sshfs_opts+=" -o allow_other,default_permissions"; fi
    if [ -n "$key" ]; then sshfs_opts+=" -o IdentityFile=$key"; fi
    
    if [ -n "$jump" ]; then
        local jump_data
        jump_data=$(jq -r --arg alias "$jump" '.[] | select(.alias == $alias) | "\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)"' "$CONFIG_FILE")
        if [ -n "$jump_data" ]; then
            IFS='|' read -r j_host j_user j_port j_key j_pass <<< "$jump_data"
            
            local j_cmd=""
            local j_decrypted_pass=""
            if [[ "$j_pass" == enc:* ]]; then
                ensure_dependency "openssl" || return 1
                read -s -p "Palabra clave para salto ($jump): " j_keyword; echo ""
                local j_encrypted_data=${j_pass#enc:}
                j_decrypted_pass=$(echo "$j_encrypted_data" | openssl enc -aes-256-cbc -a -d -salt -pbkdf2 -pass pass:"$j_keyword" 2>/dev/null)
                if [ -z "$j_decrypted_pass" ]; then echo "Error de desencriptación para el salto."; return 1; fi
            elif [ -n "$j_pass" ] && [ "$j_pass" != "null" ]; then
                j_decrypted_pass="$j_pass"
            fi

            if [ -n "$j_decrypted_pass" ]; then
                ensure_dependency "sshpass" || return 1
                j_cmd="sshpass -p '$j_decrypted_pass' ssh -o StrictHostKeyChecking=no"
            else
                j_cmd="ssh -o StrictHostKeyChecking=no"
            fi
            
            if [ -n "$j_port" ] && [ "$j_port" != "22" ] && [ "$j_port" != "null" ]; then j_cmd+=" -p $j_port"; fi
            if [ -n "$j_key" ] && [ "$j_key" != "null" ]; then j_cmd+=" -i $j_key"; fi
            sshfs_opts+=" -o ProxyCommand=\"$j_cmd -W %h:%p $j_user@$j_host\""
        else
            echo "Advertencia: Alias de salto '$jump' no encontrado."
        fi
    fi
    
    local remote_path_to_mount
    local mc_start_path
    
    if [ -n "$remote_dir" ]; then
        remote_path_to_mount="/"
        mc_start_path="$MOUNT_POINT/$(echo "$remote_dir" | sed 's#^/##')"
    else
        remote_path_to_mount=""
        mc_start_path="$MOUNT_POINT"
    fi

    if [ -n "$decrypted_pass" ]; then
        ensure_dependency "sshpass" || return 1
        if ! eval "echo \"$decrypted_pass\" | sshfs \"${user}@${host}:${remote_path_to_mount}\" \"$MOUNT_POINT\" -o password_stdin $sshfs_opts"; then
            echo "Error de montaje."
            return 1
        fi
    else
        if ! eval "sshfs \"${user}@${host}:${remote_path_to_mount}\" \"$MOUNT_POINT\" $sshfs_opts"; then
            echo "Error de montaje."
            return 1
        fi
    fi
    
    echo "¡Montaje exitoso! Sale con F10 para desmontar."
    mc "$mc_start_path"
}

list_connections() {
    local show_all=false
    local show_pass=false

    for arg in "$@"; do
        case "$arg" in
            -a|--all) show_all=true ;;
            -p|--password) show_pass=true ;;
            -ap|-pa) show_all=true; show_pass=true ;;
        esac
    done

    if [ ! -s "$CONFIG_FILE" ] || [ "$(jq 'length' "$CONFIG_FILE" 2>/dev/null)" -eq 0 ]; then
        echo "No hay conexiones guardadas."
        return
    fi

    echo "Conexiones guardadas:"
    echo "---------------------"
    if [ "$show_all" = true ] || [ "$show_pass" = true ]; then
        # Header for detailed view
        printf "%-15s | %-30s | %-20s | %s\n" "Alias" "Target" "Auth" "Extra"
        echo "----------------------------------------------------------------------------------------------------"
    fi

    jq -r '.[] | "\(.alias)|\(.host)|\(.user)|\(.port)|\(.key)|\(.pass)|\(.remote_dir)|\(.cmd)|\(.jump)"' "$CONFIG_FILE" | \
    while IFS='|' read -r alias host user port key pass remote_dir cmd jump; do
        # Skip comments or empty lines
        if [ -z "$alias" ] || [ "$alias" == "null" ]; then continue; fi

        if [ "$show_all" = true ] || [ "$show_pass" = true ]; then
            # Format Target: User@Host:Port
            local target="$user@$host"
            if [ "$port" != "22" ]; then target="$target:$port"; fi

            # Format Auth
            local auth_info="None"
            if [ -n "$key" ] && [ "$key" != "null" ]; then
                auth_info="Key: $(basename "$key")"
            elif [ -n "$pass" ] && [ "$pass" != "null" ]; then
                if [ "$show_pass" = true ]; then
                    auth_info="Pass: $pass"
                else
                    auth_info="Pass: ******"
                fi
            fi

            # Format Extra
            local extra=""
            if [ -n "$remote_dir" ] && [ "$remote_dir" != "null" ]; then extra="Dir: $remote_dir "; fi
            if [ -n "$cmd" ] && [ "$cmd" != "null" ]; then extra="${extra}Cmd: $cmd "; fi
            if [ -n "$jump" ] && [ "$jump" != "null" ]; then extra="${extra}Jump: $jump "; fi

            printf "%-15s | %-30s | %-20s | %s\n" "$alias" "$target" "$auth_info" "$extra"
        else
            echo "  - $alias ($user@$host)"
        fi
    done
    echo ""
}

export_ssh_config() {
    local ssh_dir="$HOME/.ssh"
    local ssh_config_file="$ssh_dir/config"
    local config_file="$CONFIG_FILE"
    
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    touch "$ssh_config_file"
    chmod 600 "$ssh_config_file"

    local marker_start="### BEGIN SSH MANAGER CONFIG ###"
    local marker_end="### END SSH MANAGER CONFIG ###"

    # Remove existing managed block
    if grep -q "^$marker_start" "$ssh_config_file"; then
        sed -i "/^$marker_start/,/^$marker_end/d" "$ssh_config_file"
    fi

    # Read active connections
    if [ ! -s "$config_file" ] || [ "$(jq 'length' "$config_file" 2>/dev/null)" -eq 0 ]; then
        echo "No hay conexiones guardadas para exportar."
        return
    fi
    
    # Check if there's anything else in the config file to append a newline nicely
    if [ -s "$ssh_config_file" ] && [ -n "$(tail -c 1 "$ssh_config_file")" ]; then
        echo "" >> "$ssh_config_file"
    fi

    echo "Exportando conexiones a $ssh_config_file..."

    # Append new managed block
    {
        echo "$marker_start"
        echo "# Generado automáticamente por SSH Manager."
        echo "# No edites este bloque manualmente, será sobreescrito en la próxima exportación."
        
        jq -r '.[] | "\(.alias)|\(.host)|\(.user)|\(.port)|\(.key)|\(.jump)"' "$config_file" | \
        while IFS='|' read -r alias host user port key jump; do
            if [ -z "$alias" ] || [ "$alias" == "null" ]; then continue; fi

            echo ""
            echo "Host $alias"
            echo "    HostName $host"
            echo "    User $user"
            if [ "$port" != "22" ] && [ "$port" != "null" ]; then
                echo "    Port $port"
            fi
            if [ -n "$key" ] && [ "$key" != "null" ]; then
                echo "    IdentityFile $key"
            fi
            if [ -n "$jump" ] && [ "$jump" != "null" ]; then
                echo "    ProxyJump $jump"
            fi
        done
        
        echo ""
        echo "$marker_end"
    } >> "$ssh_config_file"
    
    echo "¡Configuraciones exportadas exitosamente!"
}

run_tunnels_menu() {
    local options=("Listar túneles/proxies activos" "Detener túnel/proxy" "Crear túnel local" "Crear túnel reverso" "Volver")
    local selected=0

    while true; do
        clear >&2
        echo "==========================================" >&2
        echo "           TÚNELES SSH" >&2
        echo "==========================================" >&2
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/Esc/q para volver." >&2
        echo "------------------------------------------" >&2

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}" >&2
            else
                echo "   ${options[$i]}" >&2
            fi
        done
        echo "==========================================" >&2

        key=$(read_menu_key)

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|$'\x1b'|q|Q) # Left, Esc or q - Back
                return
                ;;
            ''|'[C') # Enter or Right - Select
                local choice="${options[$selected]}"
                case "$choice" in
                    "Listar túneles/proxies activos") list_tunnels; read -p "Presiona Enter para continuar..." ;;
                    "Detener túnel/proxy") stop_tunnel; read -p "Presiona Enter para continuar..." ;;
                    "Crear túnel local") 
                        local a; a=$(select_alias "Selecciona conexión para el túnel")
                        if [ $? -ne 0 ] || [ -z "$a" ]; then continue; fi
                        
                        echo "Configurando túnel local (Puerto Local -> Host:Puerto Remoto)"
                        read -p "Puerto Local (tu máquina): " l_port
                        if [ -z "$l_port" ]; then echo "Cancelado."; sleep 1; continue; fi
                        
                        read -p "Host Destino (desde el servidor) [localhost]: " d_host
                        d_host=${d_host:-localhost}
                        
                        read -p "Puerto Destino (en el servidor/red): " d_port
                        if [ -z "$d_port" ]; then echo "Cancelado."; sleep 1; continue; fi
                        
                        run_tunnel "$a" "$l_port:$d_host:$d_port" false true
                        read -p "Presiona Enter para continuar..." 
                        ;;
                    "Crear túnel reverso") 
                        local a; a=$(select_alias "Selecciona conexión para el túnel")
                        if [ $? -ne 0 ] || [ -z "$a" ]; then continue; fi

                        echo "Configurando túnel reverso (Puerto Remoto -> Host:Puerto Local)"
                        read -p "Puerto Remoto (en el servidor): " r_port
                        if [ -z "$r_port" ]; then echo "Cancelado."; sleep 1; continue; fi

                        read -p "Host Local (desde tu máquina) [localhost]: " l_host
                        l_host=${l_host:-localhost}

                        read -p "Puerto Local (tu máquina): " l_port
                        if [ -z "$l_port" ]; then echo "Cancelado."; sleep 1; continue; fi

                        run_tunnel "$a" "$r_port:$l_host:$l_port" true true
                        read -p "Presiona Enter para continuar..." 
                        ;;
                    "Volver") return ;;
                esac
                ;;
        esac
    done
}

run_settings_menu() {
    local options=("Ver configuración actual" "Archivo de conexiones" "Archivo de logs (deps)" "Archivo PID túneles" "Exportar conexiones a ~/.ssh/config" "Actualizar script" "Volver")
    local selected=0

    while true; do
        clear >&2
        echo "==========================================" >&2
        echo "               AJUSTES" >&2
        echo "==========================================" >&2
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/Esc/q para volver." >&2
        echo "------------------------------------------" >&2

        for i in "${!options[@]}"; do
            if [ $i -eq $selected ]; then
                printf " > \e[32m%s\e[0m\n" "${options[$i]}" >&2
            else
                echo "   ${options[$i]}" >&2
            fi
        done
        echo "==========================================" >&2

        key=$(read_menu_key)

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|$'\x1b'|q|Q) # Left, Esc or q - Back
                return
                ;;
            ''|'[C') # Enter or Right - Select
                local choice="${options[$selected]}"
                case "$choice" in
                    "Ver configuración actual")
                        echo "------------------------------------------"
                        echo "Archivo de conexiones: $CONNECTIONS_PATH"
                        echo "Archivo de logs:       $DEPS_LOG"
                        echo "Archivo PID túneles:   $TUNNELS_PID_FILE"
                        echo "------------------------------------------"
                        read -p "Presiona Enter para continuar..."
                        ;;
                    "Archivo de conexiones")
                        echo "Ubicación actual: $CONNECTIONS_PATH"
                        read -p "Nueva ubicación (vacío para cancelar): " new_path
                        if [ -n "$new_path" ]; then
                            # Expand tilde if present
                            new_path="${new_path/#\~/$HOME}"
                            # Update master config
                            if grep -q "CONNECTIONS_PATH=" "$MASTER_CONFIG_FILE"; then
                                sed -i "s|^CONNECTIONS_PATH=.*|CONNECTIONS_PATH=$new_path|" "$MASTER_CONFIG_FILE"
                            else
                                echo "CONNECTIONS_PATH=$new_path" >> "$MASTER_CONFIG_FILE"
                            fi
                            load_config
                            echo "Configuración actualizada."
                            read -p "Presiona Enter para continuar..."
                        fi
                        ;;
                    "Archivo de logs (deps)")
                        echo "Ubicación actual: $DEPS_LOG"
                        read -p "Nueva ubicación (vacío para cancelar): " new_path
                        if [ -n "$new_path" ]; then
                            new_path="${new_path/#\~/$HOME}"
                            if grep -q "DEPS_LOG_PATH=" "$MASTER_CONFIG_FILE"; then
                                sed -i "s|^DEPS_LOG_PATH=.*|DEPS_LOG_PATH=$new_path|" "$MASTER_CONFIG_FILE"
                            else
                                echo "DEPS_LOG_PATH=$new_path" >> "$MASTER_CONFIG_FILE"
                            fi
                            load_config
                            echo "Configuración actualizada."
                            read -p "Presiona Enter para continuar..."
                        fi
                        ;;
                    "Archivo PID túneles")
                        echo "Ubicación actual: $TUNNELS_PID_FILE"
                        read -p "Nueva ubicación (vacío para cancelar): " new_path
                        if [ -n "$new_path" ]; then
                            new_path="${new_path/#\~/$HOME}"
                            if grep -q "TUNNELS_PID_PATH=" "$MASTER_CONFIG_FILE"; then
                                sed -i "s|^TUNNELS_PID_PATH=.*|TUNNELS_PID_PATH=$new_path|" "$MASTER_CONFIG_FILE"
                            else
                                echo "TUNNELS_PID_PATH=$new_path" >> "$MASTER_CONFIG_FILE"
                            fi
                            load_config
                            echo "Configuración actualizada."
                            read -p "Presiona Enter para continuar..."
                        fi
                        ;;
                    "Exportar conexiones a ~/.ssh/config") export_ssh_config; read -p "Presiona Enter para continuar..." ;;
                    "Actualizar script") update_script; read -p "Presiona Enter para continuar..." ;;
                    "Volver") return ;;
                esac
                ;;
        esac
    done
}

run_interactive_menu() {
    local options=("Conectar a un servidor" "Listar conexiones" "Añadir nueva conexión" "Editar conexión" "Eliminar conexión")
    if ! $IS_TERMUX; then options+=("Explorar archivos"); fi
    options+=("Túneles SSH" "Ajustes" "Salir")

    local selected=0
    local has_connections=false
    
    while true; do
        # Check connections status on every loop in case user adds/deletes one
        if [ -s "$CONFIG_FILE" ] && [ "$(jq 'length' "$CONFIG_FILE" 2>/dev/null)" -gt 0 ]; then
            has_connections=true
        else
            has_connections=false
        fi

        clear
        echo "=========================================="
        echo "      SSH MANAGER v$VERSION"
        echo "=========================================="
        echo "Usa ↑/↓ para moverte, Enter/→ para seleccionar, ←/Esc/q para salir."
        echo "------------------------------------------"

        for i in "${!options[@]}"; do
            local opt="${options[$i]}"
            local is_disabled=false
            
            # Determine if option should be disabled
            case "$opt" in
                "Conectar a un servidor"|"Listar conexiones"|"Editar conexión"|"Eliminar conexión"|"Explorar archivos"|"Túneles SSH")
                    if [ "$has_connections" = false ]; then is_disabled=true; fi
                    ;;
            esac

            if [ $i -eq $selected ]; then
                if [ "$is_disabled" = true ]; then
                    printf " > \e[90m%s (Sin conexiones)\e[0m\n" "$opt"
                else
                    printf " > \e[32m%s\e[0m\n" "$opt"
                fi
            else
                if [ "$is_disabled" = true ]; then
                    printf "   \e[90m%s\e[0m\n" "$opt"
                else
                    echo "   $opt"
                fi
            fi
        done
        echo "=========================================="

        key=$(read_menu_key)

        case "$key" in
            '[A') # Up
                selected=$(( (selected - 1 + ${#options[@]}) % ${#options[@]} ))
                ;;
            '[B') # Down
                selected=$(( (selected + 1) % ${#options[@]} ))
                ;;
            '[D'|$'\x1b'|q|Q) # Left, Esc or q - Exit
                exit 0
                ;;
            ''|'[C') # Enter or Right - Select
                local choice="${options[$selected]}"
                
                # Check if disabled before executing
                local choice_disabled=false
                case "$choice" in
                    "Conectar a un servidor"|"Listar conexiones"|"Editar conexión"|"Eliminar conexión"|"Explorar archivos"|"Túneles SSH")
                        if [ "$has_connections" = false ]; then choice_disabled=true; fi
                        ;;
                esac

                if [ "$choice_disabled" = true ]; then
                    # Optional: Flash a message or just ignore
                    continue
                fi

                case "$choice" in
                    "Conectar a un servidor") connect_to_host ;;
                    "Listar conexiones") list_connections -a; read -p "Presiona Enter para continuar..." ;;
                    "Añadir nueva conexión") if add_connection; then read -p "Presiona Enter para continuar..."; fi ;;
                    "Editar conexión") if edit_connection; then read -p "Presiona Enter para continuar..."; fi ;;
                    "Eliminar conexión") if delete_connection; then read -p "Presiona Enter para continuar..."; fi ;;
                    "Explorar archivos") browse_sftp ;;
                    "Túneles SSH") run_tunnels_menu ;;
                    "Ajustes") run_settings_menu ;;
                    "Salir") exit 0 ;;
                esac
                ;;
        esac
    done
}

# --- PUNTO DE ENTRADA PRINCIPAL ---
main() {
    load_config
    if [ "${1:-}" != "proxy" ]; then
        check_base_requirements
    fi

    if [ "$#" -gt 0 ]; then
        local COMMAND=$1; shift
        case "$COMMAND" in
            add|-a) add_connection ;;
            edit|-e) edit_connection "$1" "$2" ;;
            list|-l) list_connections "$@" ;;
            connect|-c) connect_to_host "$1" "$2" ;;
            browse|-b) browse_sftp "$1" ;;
            delete|-d) delete_connection "$1" ;;
            export|-x) export_ssh_config ;;
            update|-u) update_script ;;
            version|-v) show_version ;;
            help|-h|--help) show_usage ;;
            scp|-s) run_scp "$1" "$2" ;;
            tunnel|-t) run_tunnel "$1" "$2" "$3" "$4" ;;
            reverse-tunnel|-rt) run_tunnel "$1" "$2" true "$4" ;;
            proxy) run_proxy "$1" "$2" ;;
            list-tunnels|-lt) list_tunnels ;;
            stop-tunnel|-st) stop_tunnel "$1" ;;
            *) 
                # Check if it's an alias directly
                if jq -e --arg alias "$COMMAND" '.[] | select(.alias == $alias)' "$CONFIG_FILE" > /dev/null 2>&1; then
                    connect_to_host "$COMMAND" "$@"
                else
                    echo "Comando desconocido: $COMMAND"
                    show_usage
                    exit 1
                fi
                ;;
        esac
    else
        run_interactive_menu
    fi
}

main "$@"
