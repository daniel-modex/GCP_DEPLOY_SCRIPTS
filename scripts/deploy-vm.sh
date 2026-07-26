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

GCLOUD_FLAGS=()

# Machine Type
GCLOUD_FLAGS+=( "--machine-type=${MACHINE_TYPE:-e2-micro}" )

# OS Image Settings
GCLOUD_FLAGS+=( "--image-family=${IMAGE_FAMILY:-ubuntu-2204-lts}" )
GCLOUD_FLAGS+=( "--image-project=${IMAGE_PROJECT:-ubuntu-os-cloud}" )

# Labels & Tags
if [ -n "$LABELS" ]; then
  GCLOUD_FLAGS+=( "--labels=${LABELS}" )
fi

if [ -n "$TAGS" ]; then
  GCLOUD_FLAGS+=( "--tags=${TAGS}" )
fi

# Persistent Disk
if [ "$ATTACH_DISK" = "true" ] && [ -n "$DISK_NAME" ]; then
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

# Startup Script
if [ -n "$STARTUP_SCRIPT_PATH" ] && [ -f "$STARTUP_SCRIPT_PATH" ]; then
  echo "Attaching startup script: $STARTUP_SCRIPT_PATH"
  GCLOUD_FLAGS+=( "--metadata-from-file=startup-script=$STARTUP_SCRIPT_PATH" )
else
  echo "WARNING: Startup script path '$STARTUP_SCRIPT_PATH' was not found or not specified!"
fi

# Inject raw JSON secrets payload directly into Instance Metadata
if [ -n "${APP_SECRETS_ENCODED:-}" ]; then
  echo "Attaching base64 encoded secrets JSON payload via metadata..."
  GCLOUD_FLAGS+=( "--metadata=APP_SECRETS_JSON=${APP_SECRETS_ENCODED}" )
else
  echo "WARNING: APP_SECRETS_ENCODED not provided!"
fi

# Redeployment Handling
if gcloud compute instances describe "$VM_NAME" --zone="$ZONE" >/dev/null 2>&1; then
  echo "VM $VM_NAME already exists. Redeploying instance..."
  gcloud compute instances delete "$VM_NAME" --zone="$ZONE" --quiet --keep-disks=all
fi

echo "=== Deploying VM: ${VM_NAME} in Zone: ${ZONE} ==="
gcloud compute instances create "$VM_NAME" \
    --zone="$ZONE" \
    "${GCLOUD_FLAGS[@]}"

echo "=== Successfully deployed $VM_NAME ==="