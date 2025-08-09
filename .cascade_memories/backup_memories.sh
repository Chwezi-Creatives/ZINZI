#!/bin/bash

# Configuration
BACKUP_DIR=".cascade_memories"
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_FILE="$BACKUP_DIR/memories_$TIMESTAMP.md"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Start the backup file with a header
echo "# Cascade AI Memory Backup" > "$BACKUP_FILE"
echo "## Backup created: $(date)" >> "$BACKUP_FILE"
echo "" >> "$BACKUP_FILE"

# Get all memory IDs and their metadata
MEMORY_IDS=$(cascade list-memories --format=json | jq -r '.[].id' 2>/dev/null)

if [ -z "$MEMORY_IDS" ]; then
  echo "No memories found to back up."
  exit 0
fi

# Counter for memory numbering
COUNT=1

# Loop through each memory and save its content
for ID in $MEMORY_IDS; do
  # Get memory details
  MEMORY_JSON=$(cascade get-memory "$ID" --format=json 2>/dev/null)
  
  if [ $? -eq 0 ]; then
    # Extract memory details
    TITLE=$(echo "$MEMORY_JSON" | jq -r '.title // "Untitled Memory"')
    CREATED_AT=$(echo "$MEMORY_JSON" | jq -r '.createdAt // "Unknown date"')
    TAGS=$(echo "$MEMORY_JSON" | jq -r '.tags | join(", ") // ""')
    CONTENT=$(echo "$MEMORY_JSON" | jq -r '.content')
    
    # Add memory to backup file
    echo "## $COUNT. $TITLE" >> "$BACKUP_FILE"
    echo "**ID:** $ID  " >> "$BACKUP_FILE"
    echo "**Created:** $CREATED_AT  " >> "$BACKUP_FILE"
    
    if [ -n "$TAGS" ]; then
      echo "**Tags:** $TAGS  " >> "$BACKUP_FILE"
    fi
    
    echo "" >> "$BACKUP_FILE"
    echo "$CONTENT" >> "$BACKUP_FILE"
    echo "" >> "$BACKUP_FILE"
    echo "---" >> "$BACKUP_FILE"
    echo "" >> "$BACKUP_FILE"
    
    echo "Backed up memory: $TITLE"
    COUNT=$((COUNT+1))
  fi
done

# Keep only the 10 most recent backups
(cd "$BACKUP_DIR" && ls -t memories_*.md | tail -n +11 | xargs rm -f 2>/dev/null)

echo ""
echo "Backup complete. Saved to: $BACKUP_FILE"
