# 🔐 SFTP Setup - Where to Save Credentials

## 🎯 **The Easy Way - Interactive Wizard**

**Just run this command:**

```bash
./interactive-setup.sh
```

**The wizard will:**
- ✅ Ask you questions in the terminal
- ✅ Save everything securely
- ✅ Set up SSH keys automatically
- ✅ Add credentials to .gitignore
- ✅ Set proper permissions (chmod 600)

---

## 📝 **What You'll Be Asked**

### **Step 1: Connection Info**
```
→ SFTP Server hostname or IP [localhost]:
→ SFTP Port [22]:
→ SFTP Username [your-user]:
→ Remote path to mount [/]:
```

### **Step 2: Authentication**
```
Choose Authentication Method:
  1) SSH Key (Recommended - More Secure)
  2) Password (Less Secure - Easier Setup)

→ Enter choice [1-2]:
```

**If SSH Key:**
```
→ Generate a new SSH key? [Y/n]:
→ Key name [sftp_connection]:
```

**If Password:**
```
→ SFTP Password:
→ Confirm SFTP Password:
```

### **Step 3: Mount Point**
```
→ Where to mount SFTP drive [/home/user/sftp-drive]:
```

### **Step 4: Performance**
```
→ Buffer size (bytes) [524288]:
→ Chunk size (bytes) [16777216]:
→ Use default performance settings? [Y/n]:
```

### **Step 5: Features**
```
→ Enable SFTP drive mounting? [Y/n]:
→ Enable continuous monitoring? [Y/n]:
→ Enable transfer failure detection? [Y/n]:
→ Auto-start on system boot? [Y/n]:
```

### **Step 6: Confirm & Save**
```
Configuration Summary:
  Host: server.com:22
  User: myuser
  ...

→ Save this configuration? [Y/n]:
```

---

## 📁 **Where Credentials Are Saved**

### **Primary Location: `.env` file**

```bash
# File: .env (auto-created in sftp directory)
# Permissions: 600 (owner read/write only)
# Added to: .gitignore (never committed)

# Connection Settings
SFTP_HOST=your-server.com
SFTP_PORT=22
SFTP_USER=your-username
SFTP_REMOTE_PATH=/

# Authentication (only one of these)
SFTP_KEY_PATH=/home/user/.ssh/sftp_connection
# OR
# SFTP_PASSWORD=your-password

# Mount Point
MOUNT_POINT=/home/user/sftp-drive

# Performance Settings
SFTP_MAX_CONCURRENCY=128
SFTP_BUFFER_SIZE=524288
SFTP_CHUNK_SIZE=16777216
```

---

## 🔒 **Security Features**

✅ **Automatic Security:**
- `chmod 600 .env` - Only you can read/write
- Added to `.gitignore` - Never committed to git
- SSH keys recommended - More secure than passwords
- SSH key passphrase option - Extra security layer

✅ **No Hardcoded Credentials:**
- All credentials in `.env` file
- Scripts source `.env` to get values
- Can easily change without editing scripts

---

## 🚀 **Quick Start**

### **Option 1: Interactive Setup (Recommended)**

```bash
# Run the wizard
./interactive-setup.sh

# Answer the questions
# Everything is saved automatically!
```

### **Option 2: Manual Setup**

```bash
# Create .env file
cat > .env << 'EOF'
SFTP_HOST=your-server.com
SFTP_PORT=22
SFTP_USER=your-username
SFTP_PASSWORD=your-password
MOUNT_POINT=/home/user/sftp-drive
EOF

# Secure it
chmod 600 .env

# Add to gitignore
echo ".env" >> .gitignore
```

### **Option 3: Environment Variables**

```bash
# Export in terminal
export SFTP_HOST=your-server.com
export SFTP_USER=your-username
export SFTP_PASSWORD=your-password

# Or add to ~/.bashrc
echo 'export SFTP_HOST=your-server.com' >> ~/.bashrc
echo 'export SFTP_USER=your-username' >> ~/.bashrc
source ~/.bashrc
```

---

## 📋 **Example Session**

```bash
$ ./interactive-setup.sh

╔═══════════════════════════════════════════════════════════════╗
║           SFTP SETUP WIZARD v1.0                             ║
╚═══════════════════════════════════════════════════════════════╝

This wizard will help you:
  • Configure SFTP connection settings
  • Setup credentials (password or SSH key)
  • Choose features to enable
  • Save everything securely

Press Enter to continue...

═══════════════════════════════════════════════════════════════
STEP 1: SFTP Connection Settings
═══════════════════════════════════════════════════════════════

▶ Basic Connection Info

→ SFTP Server hostname or IP [localhost]: myserver.com
→ SFTP Port [22]: 2222
→ SFTP Username [john]: myuser
→ Remote path to mount [/]: /uploads

✓ Connection: myuser@myserver.com:2222/uploads

Press Enter to continue...

═══════════════════════════════════════════════════════════════
STEP 2: Authentication
═══════════════════════════════════════════════════════════════

▶ Choose Authentication Method

How do you want to authenticate?
  1) SSH Key (Recommended - More Secure)
  2) Password (Less Secure - Easier Setup)
→ Enter choice [1-2]: 1

▶ SSH Key Authentication

→ Generate a new SSH key? [Y/n]: Y
→ Key name [sftp_connection]: my_sftp_key

✓ Key generated successfully!

IMPORTANT: Add this public key to your SFTP server:

ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAb7x... user@host

Run this on your SFTP server:
  mkdir -p ~/.ssh
  chmod 700 ~/.ssh
  echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAb7x..." >> ~/.ssh/authorized_keys
  chmod 600 ~/.ssh/authorized_keys

Press Enter after adding the key to your server...

═══════════════════════════════════════════════════════════════
STEP 3: Mount Settings
═══════════════════════════════════════════════════════════════

▶ Local Mount Point

→ Where to mount SFTP drive [/home/john/sftp-drive]:

✓ Created mount point: /home/john/sftp-drive

═══════════════════════════════════════════════════════════════
STEP 4: Performance Settings
═══════════════════════════════════════════════════════════════

▶ Transfer Optimization

→ Buffer size (bytes) [524288]:
→ Chunk size (bytes) [16777216]:

✓ Buffer size: 512KiB
✓ Chunk size: 16MiB

→ Use default performance settings? [Y/n]: Y

═══════════════════════════════════════════════════════════════
STEP 5: Choose Features
═══════════════════════════════════════════════════════════════

▶ Enable Features

→ Enable SFTP drive mounting? [Y/n]: Y
→ Enable continuous monitoring? [Y/n]: Y
→ Enable transfer failure detection? [Y/n]: Y
→ Auto-start on system boot? [Y/n]: Y

═══════════════════════════════════════════════════════════════
STEP 6: Save Configuration
═══════════════════════════════════════════════════════════════

▶ Configuration Summary

Connection:
  Host: myserver.com:2222
  User: myuser
  Path: /uploads
  Mount: /home/john/sftp-drive

Authentication:
  Method: SSH Key
  Key: /home/john/.ssh/my_sftp_key

Performance:
  Max concurrency: 128
  Buffer size: 512KiB
  Chunk size: 16MiB

Features:
  Drive mount: y
  Monitoring: y
  Transfer monitoring: y
  Auto-start: y

→ Save this configuration? [Y/n]: Y

▶ Saving Configuration

✓ Configuration saved to: .env
✓ File permissions set to 600 (read/write for owner only)
✓ Added .env to .gitignore

╔═══════════════════════════════════════════════════════════════╗
║                 Setup Complete!                               ║
╚═══════════════════════════════════════════════════════════════╝

Your credentials are saved in: .env
File permissions: 600 (read/write for owner only)
Added to .gitignore: Never will be committed to git

Next Steps:

1. Setup SFTP drive mount:
   sudo ./sftp-drive-setup.sh

2. Setup transfer monitoring:
   sudo ./sftp-transfer-monitor.sh

3. Test your configuration:
   source .env
   ./test-sftp-transfers.sh
```

---

## 🔐 **View/Edit Credentials Later**

```bash
# View credentials
cat .env

# Edit credentials
nano .env

# Or re-run wizard (overwrites .env)
./interactive-setup.sh

# Check .env is secure
ls -la .env
# Should show: -rw------- (600 permissions)
```

---

## ✅ **Summary**

**One command to setup everything:**

```bash
./interactive-setup.sh
```

**What it does:**
1. ✅ Asks questions in terminal
2. ✅ Saves to `.env` file
3. ✅ Sets permissions to 600
4. ✅ Adds to .gitignore
5. ✅ Generates SSH keys if needed
6. ✅ Shows next steps

**Where credentials go:**
- 📁 File: `./.env`
- 🔒 Permissions: `600` (owner only)
- 🚫 Git: Never committed (in .gitignore)

**That's it!** No manual editing, just answer questions and everything is saved securely! 🎉
