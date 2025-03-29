#!/bin/sh

# Define log file
LOG_FILE="/var/log/external_mover.log"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Redirect all output (stdout & stderr) to log file and display it on screen
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Script started at $(date)"
echo "=========================================="

# Function to log messages with timestamps
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Function to check if user provided the -y parameter
is_auto_yes() {
    for arg in "$@"; do
        if [ "$arg" = "-y" ]; then
            return 0  # True if -y is found
        fi
    done
    return 1  # False if -y is not found
}

# Check if the -y flag is provided
auto_yes=0
is_auto_yes "$@" && auto_yes=1

log "Checking available external devices..."

# Get filesystem details (Filesystem, Size, Mounted On) for /dev/ devices
mapfile -t filesystems < <(df -h | awk 'NR>1 && $1 ~ /^\/dev\// {print $1, $2, $NF}')

# Check if any filesystems were found
if [ ${#filesystems[@]} -eq 0 ]; then
    log "No external devices found. Exiting."
    exit 1
fi

# Display filesystem list
echo "-------------------------------------------------"
printf "%-5s %-20s %-10s %s\n" "No." "Filesystem" "Size" "Mounted On"
echo "-------------------------------------------------"

count=0
for fs in "${filesystems[@]}"; do
    ((count++))
    f_device=$(echo "$fs" | awk '{print $1}')
    f_size=$(echo "$fs" | awk '{print $2}')
    f_mount=$(echo "$fs" | awk '{print $3}')
    printf "%-5s %-20s %-10s %s\n" "$count)" "$f_device" "$f_size" "$f_mount"
done
echo "-------------------------------------------------"

# Ask user to select a filesystem
while true; do
    echo "Please enter the number of the filesystem you want to choose:"
    read choice </dev/tty

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#filesystems[@]} ]; then
        echo "Invalid choice. Please select a valid number."
        continue
    fi

    selected_fs=$(echo "${filesystems[$((choice - 1))]}" | awk '{print $1}')
    selected_mount=$(echo "${filesystems[$((choice - 1))]}" | awk '{print $3}')

    echo "You selected: $selected_fs mounted on $selected_mount. Confirm? (y/n)"
    if [ "$auto_yes" -ne 1 ]; then
        read confirm </dev/tty
    else
        confirm="y"
    fi
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        log "Selected filesystem: $selected_fs mounted on $selected_mount"
        break
    fi
done

# Stop enigma
init 4
log "Enigma stopped."

# Unmount the selected device
if mount | grep -q "$selected_fs"; then
    log "Unmounting $selected_fs..."
    umount "$selected_fs"
    if [ $? -ne 0 ]; then
        log "Error: Failed to unmount $selected_fs. Exiting."
        exit 1
    fi
    log "$selected_fs unmounted successfully."
else
    log "$selected_fs is not mounted, skipping unmount."
fi

# Confirm formatting
echo "Are you sure you want to format $selected_fs? This will erase all data! (yes/no)"
if [ "$auto_yes" -ne 1 ]; then
    read confirm_format </dev/tty
else
    confirm_format="yes"
fi
if [[ ! "$confirm_format" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    log "Formatting cancelled."
    exit 1
fi

# Format the device
log "Formatting $selected_fs as ext4..."
mkfs.ext4 -F "$selected_fs" > /dev/null 2>&1
if [ $? -ne 0 ]; then
    log "Error: Formatting failed. Exiting."
    exit 1
fi
log "Formatting completed successfully."

# Remove then create mount point and mount the device
log "Removing directory: $selected_mount"
rm -rf "$selected_mount"
log "Creating mount point: $selected_mount"
mkdir -p "$selected_mount"

log "Mounting $selected_fs to $selected_mount..."
mount "$selected_fs" "$selected_mount"
if [ $? -ne 0 ]; then
    log "Error: Mount failed. Exiting."
    exit 1
fi
log "Mount successful."

# Function to move directories to USB
move_to_usb() {
    local source_dir="$1"
    local target_dir="$2"

    source_dir="${source_dir%/}"
    target_dir="${target_dir%/}"

    if [ ! -d "$source_dir" ]; then
        log "Error: Source directory $source_dir does not exist. Skipping."
        return 1
    fi

    if [ -L "$source_dir" ]; then
        log "$source_dir is already a symbolic link. Exiting function."
        return
    fi

    mkdir -p "$target_dir"
    log "Copying $source_dir to $target_dir..."
    cp -r "$source_dir/"* "$target_dir/"

    if diff -qr "$source_dir" "$target_dir" > /dev/null 2>&1; then
        rm -rf "$source_dir"
        ln -s "$target_dir" "$source_dir"
        if [ -L "$source_dir" ] && [ "$(readlink "$source_dir")" = "$target_dir" ]; then
            log "Successfully moved and linked $source_dir to $target_dir."
        else
            log "Error: Failed to create symbolic link for $source_dir. Skipping."
        fi
    else
        log "Error: Copy verification failed for $source_dir. Skipping."
        rm -rf "$target_dir"
    fi
}

source_dirs=(
    "/usr/lib/enigma2"
    "/usr/share/enigma2"
)

for dir in /usr/lib/python*/; do
    source_dirs+=("$dir")
done

for source_dir in "${source_dirs[@]}"; do
    target_dir="$selected_mount${source_dir}"
    echo "Move $source_dir to $target_dir? (y/n)"
    if [ "$auto_yes" -ne 1 ]; then
        read confirm_move </dev/tty
    else
        confirm_move="y"
    fi
    if [[ "$confirm_move" =~ ^[Yy]$ ]]; then
        move_to_usb "$source_dir" "$target_dir"
    else
        log "Skipping $source_dir."
    fi
done

init 3
log "Enigma is restarting..."

echo "=========================================="
echo "Script completed at $(date)"
echo "=========================================="
