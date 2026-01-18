#!/bin/bash

REMOTE_PATH="/data/user/0/com.example.frienance/app_flutter/cache/"
LOCAL_PATH="/home/nambui/Dev/Frienance/lib/cache/output"

# Check if file exists on emulator
if adb shell [ -d "$REMOTE_PATH" ]; then
    echo "File found. Pulling to local machine..."
    adb pull "$REMOTE_PATH" "$LOCAL_PATH"
else
    echo "Error: File $REMOTE_PATH not found on emulator."
fi