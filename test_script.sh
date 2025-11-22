#!/bin/bash

# Setup
CONFIG_DIR="$HOME/.config/ssh-manager"
mkdir -p "$CONFIG_DIR"
export CONNECTIONS_PATH="$CONFIG_DIR/connections_test.json"
echo "[]" > "$CONNECTIONS_PATH"

# Source the script to use its functions or just run it? 
# Running it is better to test the actual execution.
# We need to modify the script to use our test config? 
# The script loads config from ~/.config/ssh-manager/config.
# Let's temporarily modify the master config or just mock the config loading.

# Backup real config
cp "$CONFIG_DIR/config" "$CONFIG_DIR/config.bak" 2>/dev/null
echo "CONNECTIONS_PATH='$CONNECTIONS_PATH'" > "$CONFIG_DIR/config"
echo "DEPS_LOG_PATH='$CONFIG_DIR/installed_deps.log'" >> "$CONFIG_DIR/config"
echo "TUNNELS_PID_PATH='$CONFIG_DIR/tunnels.pid'" >> "$CONFIG_DIR/config"

echo "--- TEST 1: Add Connection (Plain Password) ---"
# Inputs: Alias, Host, User, Port, Auth(2=Pass), Password, Dir, Cmd
printf "test1\n192.168.1.10\ntestuser\n22\n2\npassword123\n/tmp\nls -la\n" | ./ssh-manager.sh add

echo "--- TEST 2: Add Connection (Encrypted Password) ---"
# Inputs: Alias, Host, User, Port, Auth(3=EncPass), Keyword, Password, Dir, Cmd
printf "test2\n192.168.1.11\ntestuser2\n2222\n3\nsecretkey\npassword456\n\n\n" | ./ssh-manager.sh add

echo "--- TEST 3: Add Connection (SSH Key) ---"
# Inputs: Alias, Host, User, Port, Auth(1=Key), KeyPath, Dir, Cmd
touch /tmp/id_rsa_test
printf "test3\n192.168.1.12\ntestuser3\n22\n1\n/tmp/id_rsa_test\n\n\n" | ./ssh-manager.sh add

echo "--- TEST 4: List Connections ---"
./ssh-manager.sh list

echo "--- TEST 5: Edit Connection (Wizard) ---"
# Edit 'test1'. Inputs: Host(enter), User(enter), Port(enter), Dir(/var/www), Cmd(enter), ChangeAuth(n)
printf "\n\n\n/var/www\n\nn\n" | ./ssh-manager.sh edit test1

echo "--- TEST 6: Verify Edit ---"
./ssh-manager.sh list

echo "--- TEST 7: Delete Connection ---"
# Inputs: Confirm(s)
printf "s\n" | ./ssh-manager.sh delete test2

echo "--- TEST 8: Final List ---"
./ssh-manager.sh list

# Cleanup
rm "$CONNECTIONS_PATH"
rm /tmp/id_rsa_test
mv "$CONFIG_DIR/config.bak" "$CONFIG_DIR/config" 2>/dev/null
