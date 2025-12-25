#!/bin/bash

# Docker SFTP Test Environment Setup Script

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=========================================="
echo "  SFTP Docker Test Environment Setup"
echo "=========================================="
echo

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "   Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    echo "   Visit: https://docs.docker.com/compose/install/"
    exit 1
fi

echo "✅ Docker and Docker Compose are installed"
echo

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p "$SCRIPT_DIR/sftp_test_files"
mkdir -p "$SCRIPT_DIR/ssh_keys"
mkdir -p "$SCRIPT_DIR/logs"
mkdir -p "$SCRIPT_DIR/performance_results"
echo "✅ Directories created"
echo

# Generate test files
echo "📄 Generating test files..."
echo "This may take a moment..."

if [ ! -f "$SCRIPT_DIR/sftp_test_files/.generated" ]; then
    for size in 1 5 10 20 50; do
        for i in {1..10}; do
            local filename="test_${size}mb_${i}.dat"
            if [ ! -f "$SCRIPT_DIR/sftp_test_files/$filename" ]; then
                dd if=/dev/urandom of="$SCRIPT_DIR/sftp_test_files/$filename" \
                   bs=1M count=$size 2>/dev/null &
            fi
        done
    done
    wait
    touch "$SCRIPT_DIR/sftp_test_files/.generated"
    echo "✅ Test files generated (50 files: 1MB, 5MB, 10MB, 20MB, 50MB)"
else
    echo "✅ Test files already exist"
fi
echo

# Create environment file
cat > "$SCRIPT_DIR/.env.docker" << 'EOF'
# Docker SFTP Test Environment Configuration
SFTP_HOST=localhost
SFTP_PORT=2222
SFTP_USER=testuser
SFTP_PASSWORD=testpass
SFTP_MAX_CONCURRENCY=128
SFTP_BUFFER_SIZE=524288
SFTP_CHUNK_SIZE=16777216
EOF

echo "📝 Created .env.docker configuration file"
echo

# Create test script
cat > "$SCRIPT_DIR/test_docker_sftp.sh" << 'EOF'
#!/bin/bash

# Test Docker SFTP Connection

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/.env.docker"

echo "Testing SFTP connection to ${SFTP_HOST}:${SFTP_PORT}..."

# Test with sshpass if available
if command -v sshpass &> /dev/null; then
    sshpass -p "${SFTP_PASSWORD}" sftp -o StrictHostKeyChecking=no \
        -P ${SFTP_PORT} ${SFTP_USER}@${SFTP_HOST} \
        << 'END'
ls -lh
quit
END
else
    echo "⚠️  sshpass not installed. Manual connection required:"
    echo ""
    echo "   sftp -P ${SFTP_PORT} ${SFTP_USER}@${SFTP_HOST}"
    echo "   Password: ${SFTP_PASSWORD}"
    echo ""
fi
EOF

chmod +x "$SCRIPT_DIR/test_docker_sftp.sh"
echo "✅ Created test_docker_sftp.sh script"
echo

# Start Docker containers
echo "🐳 Starting Docker SFTP server..."
if docker compose version &> /dev/null; then
    docker compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
else
    docker-compose -f "$SCRIPT_DIR/docker-compose.yml" up -d
fi

# Wait for server to be ready
echo "⏳ Waiting for SFTP server to be ready..."
sleep 5

# Check if container is running
if docker ps | grep -q sftp-test-server; then
    echo "✅ SFTP server is running"
    echo
    echo "=========================================="
    echo "  Setup Complete!"
    echo "=========================================="
    echo
    echo "SFTP Server Details:"
    echo "  Host: localhost"
    echo "  Port: 2222"
    echo "  Username: testuser"
    echo "  Password: testpass"
    echo
    echo "Test files location: ./sftp_test_files/"
    echo
    echo "Next steps:"
    echo "  1. Test connection: ./test_docker_sftp.sh"
    echo "  2. Run performance tests: ./quick_batch_test_refactored.sh"
    echo "  3. View logs: docker logs -f sftp-test-server"
    echo
    echo "To stop the server:"
    echo "  docker compose -f docker-compose.yml down"
    echo
else
    echo "❌ Failed to start SFTP server"
    echo "Check logs: docker logs sftp-test-server"
    exit 1
fi
