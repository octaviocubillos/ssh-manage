# SSH Manager

Un gestor de conexiones SSH simple y potente escrito en Bash. Te permite guardar, gestionar y conectar a tus servidores de forma rápida y eficiente, todo desde la línea de comandos.

## ✨ Características

- **Gestión de Conexiones**: Añade, edita, lista y elimina conexiones SSH fácilmente.
- **Atajos Inteligentes**: Conéctate a tus servidores usando un alias corto (ej: `sshm mi-servidor`).
- **Seguridad Opcional**: Guarda contraseñas en texto plano o encriptadas con una palabra clave usando OpenSSL.
- **Comandos Remotos**: Ejecuta comandos directamente en el servidor después de conectar (ej: `sshm mi-servidor top`).
- **Explorador de Archivos Visual**: Navega por los archivos de tu servidor con una interfaz visual SFTP gracias a la integración con `sshfs` y `Midnight Commander`.
- **Instalación de Dependencias Automática**: El script detecta e instala las herramientas que necesita en una amplia gama de distribuciones (Debian, Fedora, Arch, CentOS, Alpine, macOS, Termux y más).
- **Portátil**: Funciona en la mayoría de los sistemas operativos tipo Unix.

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

| Comando Completo | Atajo | Descripción                                                 |
| ---------------- | ----- | ----------------------------------------------------------- |
| `add`            | `-a`  | Añade una nueva conexión de forma interactiva.              |
| `list`           | `-l`  | Lista todas las conexiones guardadas.                       |
| `connect`        | `-c`  | Se conecta a un servidor usando su alias.                   |
| `browse`         | `-b`  | Abre un explorador de archivos SFTP visual en el servidor.  |
| `edit`           | `-e`  | Modifica una conexión existente.                            |
| `delete`         | `-d`  | Elimina una conexión guardada.                              |

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

# Conectar y ejecutar un comando
sshm mi-servidor "tail -f /var/log/syslog"

# Abrir el explorador de archivos visual en un servidor
sshm browse mi-servidor

# Editar una conexión (modo interactivo)
sshm edit mi-servidor

# Editar solo el usuario de una conexión
sshm edit mi-servidor user

# Eliminar una conexión
sshm delete mi-servidor
```

## ⚙️ Configuración

El archivo de configuración se crea automáticamente en `~/.config/ssh-manager/connections.txt`. Puedes editarlo manualmente si lo necesitas.

El formato es un archivo de texto simple donde cada línea es una conexión y los campos están separados por `|`:

```
alias|host|usuario|puerto|ruta_clave|contraseña|directorio_remoto|


```
