# SSH Manager v1.0.0

Un gestor de conexiones SSH simple y potente escrito en Bash. Te permite guardar, gestionar y conectar a tus servidores de forma rápida y eficiente, todo desde la línea de comandos.

## ✨ Características

- **Gestión de Conexiones**: Añade, edita, lista y elimina conexiones SSH fácilmente.
- **Atajos Inteligentes**: Conéctate a tus servidores usando un alias corto (ej: `sshm mi-servidor`).
- **Seguridad Opcional**: Guarda contraseñas en texto plano o encriptadas con una palabra clave usando OpenSSL.
- **Comandos Remotos**: Ejecuta comandos directamente en el servidor después de conectar (ej: `sshm mi-servidor top`).
- **Explorador de Archivos Visual**: Navega por los archivos de tu servidor con una interfaz visual SFTP gracias a la integración con `sshfs` y `Midnight Commander`. (No disponible en Termux).
- **Copia de Archivos Segura**: Transfiere archivos y directorios con una sintaxis similar a `scp`.
- **Túneles SSH Avanzados**: Crea túneles locales y reversos con un asistente guiado, ejecútalos en segundo plano y gestiónalos interactivamente.
- **Menú de Ajustes**: Configura la ubicación de tu archivo de conexiones directamente desde la interfaz.
- **Instalación de Dependencias Automática**: El script detecta e instala las herramientas que necesita en una amplia gama de distribuciones.
- **Auto-actualización**: El comando `update` busca la última versión en GitHub y se actualiza automáticamente.
- **Portátil**: Funciona en la mayoría de los sistemas operativos tipo Unix, incluyendo Linux, macOS y Termux.

## 🚀 Instalación

Elige el comando adecuado para tu sistema:

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh | sudo bash
```

**Termux (Android)**

```bash
curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/install.sh | bash
```

## 🔄 Actualización

Para actualizar a la última versión, simplemente ejecuta:

```bash
sshm update
```

O selecciona "Actualizar script" desde el menú de "Ajustes".

## 🗑️ Desinstalación

Para desinstalar, simplemente ejecuta el siguiente comando:

**Linux / macOS**

```bash
curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/uninstall.sh | sudo bash
```

**Termux (Android)**

```bash
curl -fsSL https://raw.githubusercontent.com/octaviocubillos/ssh-manage/master/uninstall.sh | bash
```

## 💻 Uso

Una vez instalado, puedes llamarlo con `ssh-manage` o el atajo `sshm`.

### Comandos Disponibles

| Comando Completo | Atajo | Descripción                                                |
| ---------------- | ----- | ---------------------------------------------------------- |
| `add`            | `-a`  | Añade una nueva conexión de forma interactiva.             |
| `edit`           | `-e`  | Modifica una conexión existente.                           |
| `list`           | `-l`  | Lista todas las conexiones guardadas.                      |
| `connect`        | `-c`  | Se conecta a un servidor usando su alias.                  |
| `delete`         | `-d`  | Elimina una conexión guardada.                             |
| `browse`         | `-b`  | Abre un explorador de archivos SFTP visual en el servidor. |
| `scp`            | `-s`  | Copia archivos/directorios vía SCP.                        |
| `tunnel`         | `-t`  | Crea un túnel SSH local.                                   |
| `reverse-tunnel` | `-rt` | Crea un túnel SSH reverso.                                 |
| `list-tunnels`   | `-lt` | Lista los túneles activos en segundo plano.                |
| `stop-tunnel`    | `-st` | Detiene un túnel activo (interactivo si no se da PID).     |
| `update`         | `-u`  | Busca y aplica actualizaciones para la herramienta.        |
| `help`           | `-h`  | Muestra la ayuda.                                          |
| `version`        | `-v`  | Muestra la versión actual.                                 |

### Ejemplos

```bash
# Añadir una nueva conexión (modo interactivo)
sshm add

# Listar todas las conexiones
sshm list

# Listar con todos los detalles
sshm list -a

# Conectar a un servidor usando su alias (atajo)
sshm mi-servidor

# Conectar y ejecutar un comando (anula el comando por defecto)
sshm mi-servidor "tail -f /var/log/syslog"

# Abrir el explorador de archivos visual en un servidor
sshm browse mi-servidor

# Editar solo el usuario de una conexión
sshm edit mi-servidor user

# Copiar un archivo local al servidor
sshm scp ./mi_archivo.txt mi-servidor:/home/user/

# Descargar una carpeta del servidor
sshm scp -r mi-servidor:/var/log ./logs_locales

# Crear un túnel para acceder a una base de datos remota
sshm tunnel mi-servidor 3307:localhost:3306

# Crear el mismo túnel, pero en segundo plano
sshm tunnel mi-servidor 3307:localhost:3306 -bg

# Listar los túneles activos
sshm list-tunnels

# Detener un túnel (interactivo)
sshm stop-tunnel

# Eliminar una conexión
sshm delete mi-servidor
```

## ⚙️ Configuración

El archivo de configuración se crea automáticamente en la ruta que elijas durante la instalación (por defecto `~/.config/ssh-manager/`).

- **`config`**: Almacena la ruta a tu archivo de conexiones y un registro de las dependencias que ha instalado el script.
- **`connections.txt`**: El archivo de texto simple donde cada línea es una conexión y los campos están separados por `|`:
  ```
  alias|host|usuario|puerto|ruta_clave|contraseña|directorio_remoto|comando_defecto|
  ```

Puedes cambiar la ubicación de este archivo desde el menú "Ajustes" dentro de la aplicación.
