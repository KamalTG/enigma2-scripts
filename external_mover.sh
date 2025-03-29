#!/bin/sh

# Function to check if user provided the -y parameter
is_auto_yes() {
    # Check if -y flag is passed to the script
    for arg in "$@"; do
        if [[ "$arg" == "-y" ]]; then
            return 0  # True if -y is found
        fi
    done
    return 1  # False if -y is not found
}

# Check if the -y flag is provided
auto_yes=0
is_auto_yes "$@" && auto_yes=1

# Get filesystem details (Filesystem, Size, Mounted On) for /dev/ devices, skipping the header
mapfile -t filesystems < <(df -h | awk 'NR>1 && $1 ~ /^\/dev\// {print $1, $2, $NF}')

# Check if any filesystems were found
if [[ ${#filesystems[@]} -eq 0 ]]; then
    echo "No external devices found."
    exit 1
fi

# Display the list with a header
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

# Loop until the user confirms their choice
while true; do
    echo "Please enter the number of the filesystem you want to choose:"
    read choice

    # Validate the input (check if it's a valid number)
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#filesystems[@]})); then
        echo "Invalid choice. Please select a valid number."
        continue
    fi

    # Extract the chosen filesystem device and mount point
    selected_fs=$(echo "${filesystems[$((choice - 1))]}" | awk '{print $1}')
    selected_mount=$(echo "${filesystems[$((choice - 1))]}" | awk '{print $3}')

    # Ask for confirmation
    echo "You selected: $selected_fs mounted on $selected_mount. Confirm? (y/n)"
    [[ "$auto_yes" -eq 1 ]] || read confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        break
    fi
done

# Final confirmation
echo "You selected: $selected_fs mounted on $selected_mount"

# Stop the necessary services
init 4
echo "The device has been stopped gracefully"

# Unmount the device if it's mounted
umount $selected_fs

# Format the device
echo "Are you sure you want to format $selected_fs? This will erase all data! (yes/no)"
[[ "$auto_yes" -eq 1 ]] || read confirm_format
if [[ ! "$confirm_format" =~ ^[Yy]([Ee][Ss])?$ ]]; then
    echo "Formatting cancelled."
    exit 1
fi
echo "Formatting.."
mkfs.ext4 -F "$selected_fs" > /dev/null 2>&1
echo "$selected_fs has been formatted as ext4."

# Create mount point and mount the device
mkdir -p $selected_mount
mount $selected_fs $selected_mount

# Function to move directory to USB
move_to_usb() {
    local source_dir="$1"
    local target_dir="$2"

    # Check if the source directory exists
    if [[ ! -d "$source_dir" ]]; then
        echo "Error: Source directory $source_dir does not exist. Operation canceled."
        return 1
    fi

    # Create the target directory on the selected mount if it doesn't exist
    mkdir -p "$target_dir"
    
    # Copy the contents of the source directory to the target directory
    cp -r "$source_dir/"* "$target_dir/"
    
    # Run diff -qr to compare the source and target directories
    diff_output=$(diff -qr "$source_dir" "$target_dir")
    
    # If diff shows any differences, cancel the deletion and remove copied files
    if [[ -n "$diff_output" ]]; then
        echo "Warning: Some files were not copied correctly."
        echo "$diff_output"
        echo "Aborting deletion of $source_dir and removing copied files."

        # Remove the entire target directory (not just contents)
        rm -rf "$target_dir"
        return 1
    fi
    
    # Remove the original source directory
    rm -rf "$source_dir"
    
    # Create a symbolic link to the target directory
    ln -s "$target_dir" "$source_dir"
    
    echo "$source_dir has been moved to $selected_mount and linked successfully."
}

# Create an array of source directories to move
source_dirs=(
    "/usr/lib/enigma2"
    "/usr/share/enigma2"
)

# Add any /usr/lib/python* directories to the source_dirs array
for dir in /usr/lib/python*/; do
    source_dirs+=("$dir")
done

# Loop through each source directory and ask for user confirmation before moving
for source_dir in "${source_dirs[@]}"; do
    # Set the target directory to match the source directory structure
    target_dir="$selected_mount${source_dir}"

    # Ask the user for confirmation
    echo "You are about to move $source_dir to $target_dir. Do you want to continue? (y/n)"
    [[ "$auto_yes" -eq 1 ]] || read confirm_move
    
    # If user confirms, proceed with the move
    if [[ "$confirm_move" =~ ^[Yy]$ ]]; then
        # Call the move_to_usb function for each directory
        move_to_usb "$source_dir" "$target_dir"
    else
        echo "Skipping $source_dir."
    fi
done

# Restart the necessary services
init 3
echo "The device has been started again.."
