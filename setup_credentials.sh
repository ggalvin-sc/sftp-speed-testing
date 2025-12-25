#!/bin/bash

# SFTP Credentials Setup Helper
# This script helps you securely set up credentials

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "  SFTP Credentials Setup"
echo "=========================================="
echo

# Check if .env exists
if [ -f ".env" ]; then
    echo -e "${YELLOW}⚠️  .env file already exists${NC}"
    echo "Contents of .env (passwords hidden):"
    grep -v "PASSWORD" .env 2>/dev/null || true
    echo
    if ! confirm "Do you want to overwrite it?"; then
        echo "Setup cancelled."
        exit 0
    fi
    rm .env
fi

# Function to ask for confirmation
confirm() {
    local prompt="$1"
    local response

    while true; do
        read -r -p "${prompt} [y/N] " response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    done
}

# Function to get input with default
get_input() {
    local prompt="$1"
    local default="$2"
    local response

    if [ -n "$default" ]; then
        read -r -p "$prompt [$default]: " response
        echo "${response:-$default}"
    else
        read -r -p "$prompt: " response
        echo "$response"
    fi
}

# Function to get password (hidden)
get_password() {
    local prompt="$1"
    local password
    local password_confirm

    while true; do
        read -rs -p "$prompt: " password
        echo
        read -rs -p "Confirm password: " password_confirm
        echo

        if [ "$password" = "$password_confirm" ]; then
            echo "$password"
            break
        else
            echo -e "${RED}Passwords do not match. Try again.${NC}"
        fi
    done
}

echo "Let's set up your SFTP credentials."
echo

# Get connection details
SFTP_HOST=$(get_input "SFTP host" "localhost")
SFTP_PORT=$(get_input "SFTP port" "22")
SFTP_USER=$(get_input "SFTP username" "testuser")

echo
echo "Authentication method:"
echo "  1) Password"
echo "  2) SSH key (recommended)"
echo
read -p "Choose [1/2]: " auth_choice

if [ "$auth_choice" = "2" ]; then
    # SSH key authentication
    SFTP_KEY_PATH=$(get_input "SSH key path" "$HOME/.ssh/id_rsa")

    if [ ! -f "$SFTP_KEY_PATH" ]; then
        echo -e "${YELLOW}⚠️  SSH key not found at: $SFTP_KEY_PATH${NC}"
        if confirm "Would you like to generate a new SSH key?"; then
            key_name=$(get_input "Key name" "sftp_test")
            key_path="$HOME/.ssh/$key_name"

            echo "Generating SSH key..."
            ssh-keygen -t ed25519 -f "$key_path" -N "" || {
                echo -e "${RED}Failed to generate SSH key${NC}"
                echo "Falling back to password authentication..."
                auth_choice="1"
            }

            if [ "$auth_choice" = "2" ]; then
                SFTP_KEY_PATH="$key_path"
                echo
                echo -e "${GREEN}✅ SSH key generated: $key_path${NC}"
                echo -e "${YELLOW}⚠️  IMPORTANT: Copy this public key to your SFTP server:${NC}"
                echo
                cat "${key_path}.pub"
                echo
                echo "Run this on your SFTP server:"
                echo "  mkdir -p ~/.ssh"
                echo "  chmod 700 ~/.ssh"
                echo "  echo \"$(cat ${key_path}.pub)\" >> ~/.ssh/authorized_keys"
                echo
            fi
        else
            auth_choice="1"
        fi
    fi
fi

if [ "$auth_choice" = "1" ]; then
    # Password authentication
    echo
    SFTP_PASSWORD=$(get_password "SFTP password")
fi

# Get performance settings
echo
echo "Performance settings (press Enter for defaults):"
SFTP_MAX_CONCURRENCY=$(get_input "Max concurrency" "128")
SFTP_BUFFER_SIZE=$(get_input "Buffer size (bytes)" "524288")
SFTP_CHUNK_SIZE=$(get_input "Chunk size (bytes)" "16777216")

# Create .env file
echo
echo "Creating .env file..."

cat > .env << EOF
# SFTP Connection Settings
SFTP_HOST=$SFTP_HOST
SFTP_PORT=$SFTP_PORT
SFTP_USER=$SFTP_USER
EOF

if [ "$auth_choice" = "2" ]; then
    echo "SFTP_KEY_PATH=$SFTP_KEY_PATH" >> .env
else
    echo "SFTP_PASSWORD=$SFTP_PASSWORD" >> .env
fi

cat >> .env << EOF

# Performance Settings
SFTP_MAX_CONCURRENCY=$SFTP_MAX_CONCURRENCY
SFTP_BUFFER_SIZE=$SFTP_BUFFER_SIZE
SFTP_CHUNK_SIZE=$SFTP_CHUNK_SIZE

# Paths
SFTP_LOG_PATH=./logs/sftp_transfer.log
EOF

# Secure the file
chmod 600 .env

echo
echo -e "${GREEN}✅ Credentials saved to .env${NC}"
echo
echo "🔒 File permissions set to 600 (read/write for owner only)"
echo

# Create .gitignore if it doesn't exist
if [ ! -f ".gitignore" ]; then
    echo ".env" > .gitignore
    echo "my_test_config.toml" >> .gitignore
    echo "*.log" >> .gitignore
    echo -e "${GREEN}✅ Created .gitignore${NC}"
elif ! grep -q "^\.env$" .gitignore; then
    echo ".env" >> .gitignore
    echo -e "${GREEN}✅ Added .env to .gitignore${NC}"
fi

echo
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo
echo "Your credentials are saved in: .env"
echo
echo "To use these credentials:"
echo "  source .env"
echo "  ./quick_batch_test_refactored.sh"
echo
echo "Or add to your shell profile (~/.bashrc or ~/.zshrc):"
echo "  source /path/to/sftp/.env"
echo
echo "⚠️  SECURITY REMINDER:"
echo "  - Never commit .env to version control"
echo "  - .env has been added to .gitignore"
echo "  - File permissions are set to 600"
echo
