#!/bin/bash

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║           SFTP SETUP WIZARD v1.0                             ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo

# Get SFTP Host
read -p "SFTP Server hostname or IP [localhost]: " SFTP_HOST
SFTP_HOST=${SFTP_HOST:-localhost}

# Get SFTP Port
read -p "SFTP Port [22]: " SFTP_PORT
SFTP_PORT=${SFTP_PORT:-22}

# Get Username
read -p "SFTP Username [$USER]: " SFTP_USER
SFTP_USER=${SFTP_USER:-$USER}

# Get Remote Path
read -p "Remote path to mount [/]: " SFTP_REMOTE_PATH
SFTP_REMOTE_PATH=${SFTP_REMOTE_PATH:-/}

# Get Mount Point
read -p "Where to mount SFTP drive [$HOME/sftp-drive]: " MOUNT_POINT
MOUNT_POINT=${MOUNT_POINT:-$HOME/sftp-drive}

# Choose Auth Method
echo
echo "Authentication Method:"
echo "  1) SSH Key (Recommended)"
echo "  2) Password"
read -p "Choose [1/2]: " auth_choice

if [ "$auth_choice" = "1" ]; then
    # SSH Key
    read -p "Generate new SSH key? [Y/n]: " gen_key
    if [[ ! "$gen_key" =~ ^[Nn]$ ]]; then
        KEY_NAME="sftp_connection"
        SSH_KEY_PATH="$HOME/.ssh/$KEY_NAME"
        ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" >/dev/null 2>&1
        echo
        echo "SSH key generated: $SSH_KEY_PATH"
        echo
        echo "IMPORTANT: Add this public key to your SFTP server:"
        cat "${SSH_KEY_PATH}.pub"
        echo
        echo "Run this on your SFTP server:"
        echo "  mkdir -p ~/.ssh"
        echo "  chmod 700 ~/.ssh"
        echo "  echo \"$(cat ${SSH_KEY_PATH}.pub)\" >> ~/.ssh/authorized_keys"
        echo "  chmod 600 ~/.ssh/authorized_keys"
        echo
        read -p "Press Enter after adding the key..."
    fi
else
    # Password
    read -sp "SFTP Password: " SFTP_PASSWORD
    echo
    read -sp "Confirm Password: " SFTP_PASSWORD_CONFIRM
    echo
    
    while [ "$SFTP_PASSWORD" != "$SFTP_PASSWORD_CONFIRM" ]; do
        echo "Passwords do not match!"
        read -sp "SFTP Password: " SFTP_PASSWORD
        echo
        read -sp "Confirm Password: " SFTP_PASSWORD_CONFIRM
        echo
    done
    SSH_KEY_PATH=""
fi

# Performance settings
read -p "Max concurrent transfers [128]: " SFTP_MAX_CONCURRENCY
SFTP_MAX_CONCURRENCY=${SFTP_MAX_CONCURRENCY:-128}

read -p "Buffer size (bytes) [524288]: " BUFFER_SIZE
BUFFER_SIZE=${BUFFER_SIZE:-524288}

read -p "Chunk size (bytes) [16777216]: " CHUNK_SIZE
CHUNK_SIZE=${CHUNK_SIZE:-16777216}

# Show summary
echo
echo "═══════════════════════════════════════════════════════════════"
echo "Configuration Summary:"
echo "═══════════════════════════════════════════════════════════════"
echo "  Host: $SFTP_HOST:$SFTP_PORT"
echo "  User: $SFTP_USER"
echo "  Path: $SFTP_REMOTE_PATH"
echo "  Mount: $MOUNT_POINT"
if [ -n "$SSH_KEY_PATH" ]; then
    echo "  Auth: SSH Key ($SSH_KEY_PATH)"
else
    echo "  Auth: Password (hidden)"
fi
echo "  Max Concurrency: $SFTP_MAX_CONCURRENCY"
echo "═══════════════════════════════════════════════════════════════"
echo

read -p "Save configuration? [Y/n]: " save_config
if [[ ! "$save_config" =~ ^[Nn]$ ]]; then
    # Create .env file
    cat > .env << ENVEOF
# SFTP Configuration
# Generated: $(date)
# DO NOT commit to version control!

SFTP_HOST=$SFTP_HOST
SFTP_PORT=$SFTP_PORT
SFTP_USER=$SFTP_USER
SFTP_REMOTE_PATH=$SFTP_REMOTE_PATH
MOUNT_POINT=$MOUNT_POINT
SFTP_MAX_CONCURRENCY=$SFTP_MAX_CONCURRENCY
SFTP_BUFFER_SIZE=$BUFFER_SIZE
SFTP_CHUNK_SIZE=$CHUNK_SIZE
ENVEOF

    if [ -n "$SSH_KEY_PATH" ]; then
        echo "SFTP_KEY_PATH=$SSH_KEY_PATH" >> .env
    else
        echo "SFTP_PASSWORD=$SFTP_PASSWORD" >> .env
    fi

    # Secure it
    chmod 600 .env
    
    # Add to gitignore
    if [ -f .gitignore ]; then
        if ! grep -q "^\.env$" .gitignore; then
            echo ".env" >> .gitignore
        fi
    else
        echo ".env" > .gitignore
    fi
    
    echo
    echo "✓ Configuration saved to .env"
    echo "✓ File permissions: 600 (read/write for owner only)"
    echo "✓ Added to .gitignore"
    echo
    echo "Next steps:"
    echo "  1. Setup SFTP drive: sudo ./sftp-drive-setup.sh"
    echo "  2. Setup monitoring: sudo ./sftp-transfer-monitor.sh"
    echo "  3. Test: source .env && ./test-sftp-transfers.sh"
    echo
    echo "Your credentials are saved in: .env"
else
    echo "Configuration not saved."
    exit 0
fi
