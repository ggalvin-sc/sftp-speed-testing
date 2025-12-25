# SFTP Drive Mount & Monitoring System

## 🎯 What This Does

This creates a **virtual drive** on your system that connects to an SFTP server:

- ✅ Mount SFTP as a local drive (like a USB drive)
- ✅ Auto-mounts on system boot
- ✅ Auto-restarts if connection fails
- ✅ Continuous monitoring with alerts
- ✅ Desktop notifications for all events
- ✅ Complete logging for troubleshooting
- ✅ Automatic log rotation

## 🚀 Quick Start

```bash
# Run the setup script (requires sudo)
sudo ./sftp-drive-setup.sh
```

**The script will:**
1. Install dependencies (sshfs, curl, notify-send)
2. Ask for your SFTP credentials
3. Setup SSH key authentication (recommended)
4. Create mount/unmount scripts
5. Create systemd services for auto-start and monitoring
6. Start everything automatically

## 📁 What You Get

### **Mounted Drive**
```
~/sftp-drive/          # Your SFTP server appears here!
```

You can:
- `ls ~/sftp-drive/` - List remote files
- `cp file.txt ~/sftp-drive/` - Copy files to SFTP
- `cd ~/sftp-drive/` - Navigate like a local directory
- Open it in your file manager (Nautilus, Dolphin, etc.)

### **Services**

#### 1. **sftp-drive@user.service** - Main Mount Service
- Mounts SFTP on boot
- Auto-restarts on failure (retries 3 times with 10s delay)
- Restarts after network issues
- Logs: `logs/sftp-service.log`

#### 2. **sftp-monitor@user.service** - Monitor Service
- Checks every 5 minutes if drive is mounted
- Checks if sshfs process is running
- Checks disk space availability
- Sends desktop notifications for issues
- Logs all alerts: `logs/sftp-alerts.log`

## 🎛️ Control Commands

### **Manual Mount/Unmount**

```bash
# Mount the drive
./sftp-mount.sh

# Unmount the drive
./sftp-umount.sh
```

### **Service Control**

```bash
# Check status
systemctl status sftp-drive@$USER

# Start service
systemctl start sftp-drive@$USER

# Stop service
systemctl stop sftp-drive@$USER

# Restart service
systemctl restart sftp-drive@$USER

# Enable/disable auto-start on boot
systemctl enable sftp-drive@$USER
systemctl disable sftp-drive@$USER

# Check monitor status
systemctl status sftp-monitor@$USER
```

## 📊 Logging & Monitoring

### **Log Files**

All logs are in `./logs/`:

| Log File | Purpose |
|----------|---------|
| `sftp-mount.log` | Mount/unmount operations |
| `sftp-service.log` | systemd service output |
| `sftp-service-error.log` | Service errors |
| `sftp-monitor.log` | Monitoring activity |
| `sftp-monitor-error.log` | Monitor errors |
| `sftp-alerts.log` | All alerts and notifications |

### **View Logs**

```bash
# Follow mount log in real-time
tail -f logs/sftp-mount.log

# View service logs
journalctl -u sftp-drive@$USER -f

# View recent alerts
tail -20 logs/sftp-alerts.log

# View all logs at once
tail -f logs/*.log
```

### **What Gets Logged**

Every log entry includes:
- ✅ Timestamp (YYYY-MM-DD HH:MM:SS)
- ✅ Event type (mount, unmount, error, alert)
- ✅ Detailed message
- ✅ Success/failure status

**Example:**
```
[2025-12-25 14:30:15] Attempting to mount SFTP: user@server.com:/ -> /home/user/sftp-drive
[2025-12-25 14:30:17] ✅ Successfully mounted
[2025-12-25 14:35:22] ALERT: SFTP Drive Lost - Drive no longer mounted
[2025-12-25 14:35:23] Attempting to mount SFTP: user@server.com:/ -> /home/user/sftp-drive
[2025-12-25 14:35:25] ✅ Successfully mounted
```

## 🔔 Notifications

### **Desktop Notifications**

You'll get pop-up notifications for:

| Event | Urgency | Example |
|-------|--------|---------|
| Mount success | Normal | "SFTP Drive Connected - Mounted at ~/sftp-drive" |
| Mount failure | Critical | "SFTP Drive Error - Failed to mount. Check log" |
| Connection lost | Critical | "SFTP Drive Lost - Drive no longer mounted" |
| Auto-reconnect | Normal | "SFTP Drive Reconnected" |
| Low disk space | Warning | "SFTP Drive Low Space - Less than 1GB available" |
| Service stopped | Warning | "SFTP Drive Disconnected - Unmounted" |

**View notification history:**
```bash
cat logs/sftp-alerts.log
```

## 🛠️ Troubleshooting

### **Drive Won't Mount**

1. **Check logs:**
   ```bash
   tail -50 logs/sftp-mount.log
   journalctl -u sftp-drive@$USER -n 50
   ```

2. **Common issues:**

   **Password prompt:** SSH key not set up correctly
   ```bash
   # Test SSH connection
   ssh -p 22 user@server.com
   ```

   **Connection refused:** Wrong host/port or firewall
   ```bash
   # Test connectivity
   ping server.com
   telnet server.com 22
   ```

   **Permission denied:** Wrong username or key
   ```bash
   # Check SSH key
   ls -la ~/.ssh/sftp_mount_key*
   ```

3. **Manual mount for debugging:**
   ```bash
   ./sftp-mount.sh
   ```

### **Service Won't Start**

```bash
# Check service status
systemctl status sftp-drive@$USER

# View service logs
journalctl -u sftp-drive@$USER -n 100 --no-pager

# Check for errors
systemctl daemon-reload
systemctl reset-failed sftp-drive@$USER
systemctl restart sftp-drive@$USER
```

### **Monitor Not Alerting**

```bash
# Check monitor is running
systemctl status sftp-monitor@$USER

# View monitor logs
tail -f logs/sftp-monitor.log

# Check alerts log
cat logs/sftp-alerts.log
```

### **High CPU Usage**

sshfs can use CPU when:
- Transferring large files
- Scanning directories with many files
- Network is slow

**Solutions:**
- Add `-o cache_timeout=30` to mount options
- Reduce `ServerAliveInterval` (currently 15s)
- Check network speed

## 🔒 Security

### **SSH Keys vs Passwords**

**SSH Keys (Recommended):**
- ✅ More secure
- ✅ No password in files
- ✅ No password prompts
- ✅ Can't be guessed

**Passwords (Not Recommended):**
- ⚠️ Stored in `.env` file (chmod 600)
- ⚠️ Can be brute-forced
- ⚠️ Must be changed periodically

### **File Permissions**

All credential files have `chmod 600` (owner read/write only):
```bash
-rw------- 1 user user .env
-rw------- 1 user user ~/.ssh/sftp_mount_key
```

## 📈 Performance

### **Tuning Options**

Edit the mount command in `sftp-mount.sh`:

```bash
# For faster directory listings
-o cache_timeout=60

# For large file transfers
-o big_writes

# For slow networks
-o reconnect,ServerAliveInterval=30,ServerAliveCountMax=2

# For better performance
-o Ciphers=aes128-gcm@openssh.com
```

### **Expected Performance**

| Network Speed | Expected Transfer Time |
|---------------|------------------------|
| 100 Mbps | ~1 GB/min |
| 1 Gbps | ~10 GB/min |
| 10 Gbps | ~100 GB/min |

## 🔄 Auto-Restart Behavior

The service will:
1. **First failure:** Restart after 10 seconds
2. **Second failure:** Restart after 10 seconds
3. **Third failure:** Stop trying (prevents infinite loops)
4. **After 60 seconds:** Reset counter and try again

This prevents endless restart loops while giving recovery chances.

## 📱 Integration

### **File Managers**

The mounted drive appears in:
- **Nautilus (GNOME):** Under "Network" or sidebar
- **Dolphin (KDE):** Under "Network" or sidebar
- **Thunar (XFCE):** Under "Network" or sidebar
- **Nemo (Cinnamon):** Under "Network" or sidebar

### **Applications**

Any application can access files at `~/sftp-drive/`:
```bash
# Backup to SFTP
rsync -av ~/Documents/ ~/sftp-drive/backup/

# Video player
vlc ~/sftp-drive/videos/movie.mp4

# Text editor
nano ~/sftp-drive/config.txt
```

### **Scripts**

```bash
#!/bin/bash
# Backup script example

SOURCE="/home/user/projects"
DEST="/home/user/sftp-drive/backups"

rsync -av --delete "$SOURCE/" "$DEST/"

if [ $? -eq 0 ]; then
    echo "Backup successful" | tee -a logs/backup.log
else
    echo "Backup FAILED" | tee -a logs/backup.log
    notify-send "Backup Failed" "Check logs for details"
fi
```

## 🗑️ Uninstallation

```bash
# Stop and disable services
systemctl stop sftp-monitor@$USER
systemctl disable sftp-monitor@$USER
systemctl stop sftp-drive@$USER
systemctl disable sftp-drive@$USER

# Remove service files
sudo rm /etc/systemd/system/sftp-drive@$USER.service
sudo rm /etc/systemd/system/sftp-monitor@$USER.service

# Reload systemd
sudo systemctl daemon-reload

# Unmount drive
./sftp-umount.sh

# Remove mount point
rmdir ~/sftp-drive

# Optional: Remove scripts
rm sftp-mount.sh sftp-umount.sh sftp-monitor.sh
```

## 🆚 Comparison: Original vs. New Features

| Feature | Original Testing Suite | SFTP Drive System |
|---------|----------------------|-------------------|
| Purpose | Performance benchmarking | Production file access |
| Mount as drive | ❌ No | ✅ Yes |
| Auto-start on boot | ❌ No | ✅ Yes |
| Auto-restart | ❌ No | ✅ Yes (3x retry) |
| Monitoring | During tests only | ✅ Continuous (5min intervals) |
| Notifications | ❌ No | ✅ Desktop notifications |
| Logging | Test logs only | ✅ Complete event logging |
| Log rotation | ❌ No | ✅ Automatic (10MB) |
| Real-time access | ❌ No | ✅ Yes (like local drive) |

## 💡 Use Cases

**Perfect for:**
- ✅ Regular backups to SFTP server
- ✅ Accessing remote files like local storage
- ✅ Automated sync scripts
- ✅ Media servers (Plex, Jellyfin)
- ✅ Development environments
- ✅ Document management

**Not ideal for:**
- ❌ High-frequency random writes (use database instead)
- ❌ Real-time collaboration (use Nextcloud instead)
- ❌ Locking requirements (SFTP doesn't support file locking)

## 🎓 Tips & Tricks

1. **Create desktop shortcut:**
   ```bash
   ln -s ~/sftp-drive ~/Desktop/SFTP\ Drive
   ```

2. **Add to bookmarks:**
   Most file managers allow you to bookmark `~/sftp-drive`

3. **Automate backups:**
   ```bash
   # Add to crontab
   crontab -e
   # Add: 0 2 * * * /path/to/backup-script.sh
   ```

4. **Monitor disk usage:**
   ```bash
   df -h ~/sftp-drive
   ```

5. **Speed test:**
   ```bash
   # Create test file
   dd if=/dev/zero of=~/sftp-drive/test.img bs=1M count=100
   # Time it
   time dd if=~/sftp-drive/test.img of=/dev/null bs=1M
   ```

---

## 📞 Need Help?

1. Check logs: `tail -f logs/*.log`
2. Check service status: `systemctl status sftp-drive@$USER`
3. Review this guide
4. Run `./bin/validate_tests.sh` for health check

Enjoy your SFTP drive! 🚀
