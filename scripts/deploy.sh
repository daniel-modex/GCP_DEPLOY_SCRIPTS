#!/usr/bin/env bash
set -e

CONFIG_FILE=$1

if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
  echo "Error: Configuration file '$CONFIG_FILE' not found."
  exit 1
fi

source "$CONFIG_FILE"

# Required validation
if [ -z "$VM_NAME" ] || [ -z "$ZONE" ]; then
  echo "Error: VM_NAME and ZONE are required in $CONFIG_FILE"
  exit 1
fi

echo "=== Processing VM Deployment: ${VM_NAME} (${ZONE}) ==="

# Build optional gcloud flags array
GCLOUD_FLAGS=()

# Optional 1: Machine Type (Defaults to e2-micro if omitted)
GCLOUD_FLAGS+=( "--machine-type=${MACHINE_TYPE:-e2-micro}" )

# Optional 2: OS Image Settings
GCLOUD_FLAGS+=( "--image-family=${IMAGE_FAMILY:-ubuntu-2204-lts}" )
GCLOUD_FLAGS+=( "--image-project=${IMAGE_PROJECT:-ubuntu-os-cloud}" )

# Optional 3: Labels
if [ -n "$LABELS" ]; then
  GCLOUD_FLAGS+=( "--labels=${LABELS}" )
fi

# Optional 4: Persistent Disk Attachment
if [ "$ATTACH_DISK" = "true" ] && [ -n "$DISK_NAME" ]; then
  # Create disk if it doesn't already exist
  if ! gcloud compute disks describe "$DISK_NAME" --zone="$ZONE" >/dev/null 2>&1; then
    echo "Creating persistent disk: $DISK_NAME..."
    gcloud compute disks create "$DISK_NAME" \
        --size="${DISK_SIZE:-10GB}" \
        --type="${DISK_TYPE:-pd-standard}" \
        --zone="$ZONE" \
        ${LABELS:+--labels="$LABELS"}
  fi
  GCLOUD_FLAGS+=( "--disk=name=$DISK_NAME,mode=rw,boot=no,auto-delete=no" )
fi

# Optional 5: Startup Script
if [ -n "$STARTUP_SCRIPT_PATH" ] && [ -f "$STARTUP_SCRIPT_PATH" ]; then
  echo "Attaching startup script: $STARTUP_SCRIPT_PATH"
  GCLOUD_FLAGS+=( "--metadata-from-file=startup-script=$STARTUP_SCRIPT_PATH" )
fi

# Redeployment Handling: Delete existing VM if it exists
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" >/dev/null 2>&1; then
  echo "VM $VM_NAME already exists. Redeploying instance..."
  gcloud compute instances delete "$VM_NAME" --zone="$ZONE" --quiet --keep-disks=all
fi

# Create VM with dynamically built flags
echo "Provisioning instance $VM_NAME..."
gcloud compute instances create "$VM_NAME" \
    --zone="$ZONE" \
    "${GCLOUD_FLAGS[@]}"

echo "=== Successfully deployed $VM_NAME ==="