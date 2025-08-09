"""
Cascade AI Memory Backup Script

This script backs up all Cascade AI memories to markdown files in the .cascade_memories directory.
It can be run manually or scheduled to run periodically.
"""

import os
import json
import subprocess
from datetime import datetime
from pathlib import Path

# Configuration
BACKUP_DIR = Path(__file__).parent / ".cascade_memories"
MAX_BACKUPS = 10  # Keep this many most recent backups

def get_memories():
    """Retrieve all memories from Cascade AI."""
    try:
        result = subprocess.run(
            ["cascade", "list-memories", "--format=json"],
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print(f"Error retrieving memories: {e}")
        return []

def get_memory_details(memory_id):
    """Get details for a specific memory."""
    try:
        result = subprocess.run(
            ["cascade", "get-memory", memory_id, "--format=json"],
            capture_output=True,
            text=True,
            check=True
        )
        return json.loads(result.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as e:
        print(f"Error retrieving memory {memory_id}: {e}")
        return None

def create_backup():
    """Create a backup of all memories."""
    # Create backup directory if it doesn't exist
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    
    # Generate backup filename with timestamp
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    backup_file = BACKUP_DIR / f"memories_{timestamp}.md"
    
    # Get all memories
    memories = get_memories()
    
    if not memories:
        print("No memories found to back up.")
        return
    
    # Write backup file
    with open(backup_file, 'w', encoding='utf-8') as f:
        f.write(f"# Cascade AI Memory Backup\n")
        f.write(f"## Backup created: {datetime.now().isoformat()}\n\n")
        
        for i, memory in enumerate(memories, 1):
            memory_id = memory.get('id')
            memory_details = get_memory_details(memory_id)
            
            if not memory_details:
                continue
                
            title = memory_details.get('title', 'Untitled Memory')
            created_at = memory_details.get('createdAt', 'Unknown date')
            tags = ", ".join(memory_details.get('tags', []))
            content = memory_details.get('content', '')
            
            f.write(f"## {i}. {title}\n")
            f.write(f"**ID:** {memory_id}  \n")
            f.write(f"**Created:** {created_at}  \n")
            
            if tags:
                f.write(f"**Tags:** {tags}  \n")
                
            f.write("\n")
            f.write(f"{content}\n")
            f.write("\n---\n\n")
            
            print(f"Backed up memory: {title}")
    
    # Clean up old backups
    cleanup_old_backups()
    
    print(f"\nBackup complete. Saved to: {backup_file}")

def cleanup_old_backups():
    """Keep only the most recent backup files."""
    try:
        backup_files = sorted(
            BACKUP_DIR.glob("memories_*.md"),
            key=os.path.getmtime,
            reverse=True
        )
        
        for old_file in backup_files[MAX_BACKUPS:]:
            old_file.unlink()
            print(f"Removed old backup: {old_file}")
    except Exception as e:
        print(f"Error cleaning up old backups: {e}")

if __name__ == "__main__":
    create_backup()
