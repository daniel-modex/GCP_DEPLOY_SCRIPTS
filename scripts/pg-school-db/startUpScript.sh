#!/usr/bin/env bash
set -euo pipefail

# Configuration
MOUNT_POINT="/mnt/disks/db"
POSTGRES_DB_NAME="schooldb"
POSTGRES_USER="test.user.dev"
POSTGRES_PASSWORD="ForNowIwiLLkEEpThis" 
POSTGRES_PORT="5432"

echo "=== Starting PostgreSQL & Persistent Disk Setup ==="

# 1. Update system and install Docker
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release

if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
fi

# 2. Identify the attached secondary persistent disk (non-boot disk)
# GCP attaches additional disks typically as /dev/sdb or /dev/nvme0n2 depending on machine family
TARGET_DEVICE=""
for dev in /dev/sd[b-z] /dev/nvme[0-9]n[2-9]; do
    if [ -b "$dev" ]; then
        TARGET_DEVICE="$dev"
        break
    fi
done

if [ -z "$TARGET_DEVICE" ]; then
    echo "ERROR: No attached persistent disk found!"
    exit 1
fi

echo "Found attached target disk at: $TARGET_DEVICE"

# 3. Format disk if it does not have a filesystem yet
if ! blkid "$TARGET_DEVICE" | grep -q "TYPE="; then
    echo "Disk $TARGET_DEVICE is unformatted. Formatting with ext4..."
    mkfs.ext4 -m 0 -F -E lazy_itable_init=0,lazy_journal_init=0,discard "$TARGET_DEVICE"
else
    echo "Disk $TARGET_DEVICE is already formatted."
fi

# 4. Create mount directory and mount disk
mkdir -p "$MOUNT_POINT"

if ! mountpoint -q "$MOUNT_POINT"; then
    echo "Mounting $TARGET_DEVICE to $MOUNT_POINT..."
    mount -o discard,defaults "$TARGET_DEVICE" "$MOUNT_POINT"
fi

# Ensure persistent mount across system reboots
UUID=$(blkid -s UUID -o value "$TARGET_DEVICE")
if ! grep -q "$UUID" /etc/fstab; then
    echo "Adding mount entry to /etc/fstab..."
    echo "UUID=$UUID $MOUNT_POINT ext4 discard,defaults,nofail 0 2" >> /etc/fstab
fi

# Set proper permissions for PostgreSQL data directory
mkdir -p "$MOUNT_POINT/data"
chmod 700 "$MOUNT_POINT/data"

# 5. Launch PostgreSQL Docker Container
if docker ps -a --format '{{.Names}}' | grep -q "^postgres-db$"; then
    echo "PostgreSQL container already exists. Restarting..."
    docker restart postgres-db
else
    echo "Spinning up new PostgreSQL container..."
    docker run -d \
        --name postgres-db \
        --restart always \
        -p "${POSTGRES_PORT}:5432" \
        -e POSTGRES_DB="$POSTGRES_DB_NAME" \
        -e POSTGRES_USER="$POSTGRES_USER" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -v "$MOUNT_POINT/data:/var/lib/postgresql/data" \
        postgres:16-alpine
fi

echo "=== PostgreSQL Setup Complete! ==="