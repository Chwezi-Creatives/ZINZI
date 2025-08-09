# Cascade AI Memory Backup System

This directory contains tools for backing up and managing Cascade AI memories.

## Files

- `backup_memories.py` - Python script to back up all Cascade AI memories
- `memories_*.md` - Backup files (automatically generated)

## Prerequisites

- Python 3.6+
- Cascade CLI installed and configured

## Usage

### Manual Backup

Run the backup script:

```bash
python .cascade_memories/backup_memories.py
```

### Schedule Automatic Backups (macOS/Linux)

1. Make the script executable:
   ```bash
   chmod +x .cascade_memories/backup_memories.py
   ```

2. Add a cron job to run daily:
   ```bash
   # Edit crontab
   crontab -e
   
   # Add this line to run daily at 2 AM
   0 2 * * * cd /path/to/zinzi && /usr/bin/python3 .cascade_memories/backup_memories.py >> .cascade_memories/backup.log 2>&1
   ```

### Schedule Automatic Backups (Windows)

1. Create a batch file `backup_memories.bat`:
   ```batch
   @echo off
   cd /d "%~dp0"
   python .cascade_memories\backup_memories.py >> .cascade_memories\backup.log 2>&1
   ```

2. Use Windows Task Scheduler to run the batch file daily.

## Backup Retention

- The system keeps the 10 most recent backups
- Older backups are automatically deleted
- Backup files are named with timestamps: `memories_YYYY-MM-DD_HH-MM-SS.md`

## Restoring from Backup

To restore memories from a backup file:

1. Open the desired `.md` backup file
2. Each memory is clearly marked with its title, ID, and content
3. Use the Cascade CLI to recreate memories if needed:
   ```bash
   cascade create-memory --title "Memory Title" --content "Memory content" --tags tag1,tag2
   ```

## Notes

- Backups are stored in `.cascade_memories/`
- This directory is ignored by Git (see `.gitignore`)
- Logs are saved to `.cascade_memories/backup.log`
