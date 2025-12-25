# SFTP Drive Installation Instructions

## Quick Install

Run this command in your terminal:

```bash
sudo ./mount-sftp-drive.sh
```

## What This Does

1. **Mounts SFTP as a local drive** at `~/SFTP-Drive`
2. **Auto-mounts on system boot**
3. **Auto-mounts when you log in**
4. **Auto-reconnects** if connection drops
5. **Integrates with file manager** (appears in Nautilus sidebar)
6. **Drag & drop support** - use it like a regular drive

## Manual Setup (If Script Fails)

### 1. Install sshfs

```bash
sudo apt-get update
sudo apt-get install -y sshfs
```

### 2. Add your user to fuse group

```bash
sudo usermod -aG fuse $USER
```

### 3. Create mount point

```bash
mkdir -p ~/SFTP-Drive
```

### 4. Test mount (one-time)

```bash
sshfs root@209.159.145.206:/ ~/SFTP-Drive -o password_stdin,allow_other,reconnect << EOF
ESSrkoc!6954O)
