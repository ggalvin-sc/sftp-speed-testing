# SFTP Speed Testing Tools

A comprehensive collection of bash scripts for testing SFTP connection speeds and managing SFTP mounts with auto-restart capabilities.

## Features

- **Speed Testing**: Test download/upload speeds with detailed performance reports
- **Read-Only Testing**: Safe testing that doesn't modify server files
- **Auto-Mount SFTP**: Mount SFTP as a local drive with systemd
- **Auto-Restart**: Automatically restart failed connections
- **Monitoring**: Track transfers and get notifications for failures
- **Interactive Setup**: Easy credential configuration wizard

## Requirements

- bash
- sshpass (for automated authentication)
- sshfs (for mounting SFTP as drive)
- systemd (for auto-start/restart services)

## Installation

1. Clone this repository
2. Install dependencies:
```bash
sudo apt-get install sshpass sshfs
```

3. Run the interactive setup:
```bash
./interactive-setup.sh
```

## Usage

### Quick Speed Test

Test your SFTP download speed:
```bash
./data-speed-test.sh
```

### Mount SFTP as Drive

Mount SFTP as a local drive with auto-restart:
```bash
sudo ./sftp-drive-setup.sh
```

### Monitor Transfers

Start monitoring for failed transfers:
```bash
./sftp-transfer-monitor.sh
```

## Scripts

- `interactive-setup.sh` - Interactive credential setup wizard
- `data-speed-test.sh` - Test download speed from data directory
- `sftp-drive-setup.sh` - Mount SFTP as local drive with systemd
- `sftp-transfer-monitor.sh` - Monitor transfers and alert on failures
- `lib/sftp_test_lib.sh` - Shared library with common functions

## Configuration

Credentials are stored in `.env` file:
```bash
SFTP_HOST=your-server.com
SFTP_PORT=22
SFTP_USER=username
SFTP_PASSWORD='your-password'
```

**Note**: The `.env` file is excluded from git for security.

## Test Results Example

```
Files downloaded: 5
  Success: 5

Total size: 640 MB
Total time: 29s
Average speed: 22.07 MB/s

Performance Rating: ★★★★☆ GOOD
  - Fast connection (20-50 MB/s)
```

## License

MIT

## Contributing

Feel free to submit issues and pull requests!
