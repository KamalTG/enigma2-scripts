#!/bin/sh

# Define log file
LOG_FILE="$HOME/external_mover.log"

# Redirect all output (stdout & stderr) to log file and display it on screen
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
    echo "Script started at $(date)"
echo "=========================================="
