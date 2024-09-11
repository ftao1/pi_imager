#!/bin/bash

#set -xv


# =============== Root Check ===============
# Check if the script is being run with root privileges
if [[ $(id -u) -ne 0 ]] ; then
    echo " This script can only be run as root. Please run as root"
    exit -1
fi


# =============== Variable Declarations ===============
# Define variables for SD card, mount points, and default settings
declare -A PI_OS_VERSIONS
CLEANUP_DONE=false
NETWORK_CHECKED=false
SDCARD=$(fdisk -l | grep Disk | grep mmc | awk '{print $2}' | sed 's/://')
MOUNT_POINT_BOOT="/mnt/sdcard_boot"
MOUNT_POINT_ROOT="/mnt/sdcard_root"
CONFIG_FILE="$MOUNT_POINT_BOOT/config.txt"
DEFAULT_HOSTNAME="raspberrypi"
DEFAULT_PI_PASSWORD="raspberry"
DEFAULT_SSID="home"
IMAGES_DIR="./images"



# Temporary files and mounted partitions to clean up
MOUNTED_PARTITIONS=()

# =============== Function Definitions ===============

# Function: cleanup
# Purpose: Remove temporary files and unmount partitions
cleanup() {
    # Prevent multiple executions
    if $CLEANUP_DONE; then
        return
    fi
    CLEANUP_DONE=true

    echo "Performing cleanup..."

    # Unmount any mounted partitions
    for partition in "${MOUNTED_PARTITIONS[@]}"; do
        if mountpoint -q "$partition"; then
            echo "Unmounting $partition"
            umount "$partition" || echo "Failed to unmount $partition"
        fi
    done

    # Remove SHA256 checksum files
    for file in "$IMAGES_DIR"/*.sha256; do
        if [ -f "$file" ]; then
            echo "Removing SHA256 file: $file"
            rm -f "$file" || echo "Failed to remove $file"
        fi
    done

    # Remove any leftover .xz files
    for file in "$IMAGES_DIR"/*.xz; do
        if [ -f "$file" ]; then
            echo "Removing compressed file: $file"
            rm -f "$file" || echo "Failed to remove $file"
        fi
    done

    # Optional: List remaining files in IMAGES_DIR
    echo "Remaining files in $IMAGES_DIR:"
    ls -lh "$IMAGES_DIR"

    echo "Cleanup completed."
}

# Modify the trap command
trap 'cleanup; exit 130' INT
trap cleanup EXIT


# Function: decompress_image_with_progress
# Purpose: Decompress the .xz image file with a progress bar
decompress_image_with_progress() {
    local compressed_file="$1"
    local decompressed_file="${compressed_file%.xz}"
    local total_size

    # Try to get the uncompressed size in bytes
    total_size=$(xz --robot -l "$compressed_file" | awk -F'\t' '/totals/ {print $5}')

    # If total_size is empty or not a number, use a fallback method
    if ! [[ "$total_size" =~ ^[0-9]+$ ]]; then
        # Estimate the uncompressed size (assuming a compression ratio of about 3:1)
        total_size=$(stat -c %s "$compressed_file")
        total_size=$((total_size * 3))
    fi

    echo "Decompressing image..."
    xz -dc "$compressed_file" | pv -s "$total_size" > "$decompressed_file"

    # Check if the decompressed file exists and has a non-zero size
    if [ -s "$decompressed_file" ]; then
        echo
        echo "Image successfully decompressed."
        rm "$compressed_file"
        IMAGE_FILENAME="$decompressed_file"
    else
        echo "Error: Failed to decompress the image."
        exit 1
    fi
}


# Function: print_instructions
# Purpose: Display welcome message and script capabilities to the user
print_instructions() {
    clear
    echo "Welcome to SDCard writer and customiser for Raspberry Pi OS!"
    echo "============================================================"
    echo "This script allows the following customisations:"
    echo "1. Setting hostname"
    echo "2. Setting username and password"
    echo "3. Configure WiFi LAN SSID and password"
    echo "4. Enabling SSH"
    echo "5. Enabling UART Console"
    echo "6. Writing Pi OS Image of your choice to the SDCard"
    echo "   (Both 32-bit and 64-bit versions available)"
    echo
    echo "NOTE: Please ensure you choose the correct image for your Pi model."
    echo "32-bit versions are for older models (Pi Zero, Pi 1, Pi 2, Pi 3)."
    echo "64-bit versions are recommended for newer models (Pi 3+, Pi 4, Pi 400, Pi 5)."
    echo
}


# Function: get_hostname
# Purpose: Prompt user for a custom hostname or use the default
get_hostname() {
    echo
    read -p "Enter the hostname for the Raspberry Pi (Press Enter to use default '$DEFAULT_HOSTNAME'): " PI_HOSTNAME
    if [ -z "$PI_HOSTNAME" ]; then
        PI_HOSTNAME="$DEFAULT_HOSTNAME"
        echo "Using default hostname: $PI_HOSTNAME"
    else
        echo "Hostname set to: $PI_HOSTNAME"
    fi
}


# Function: get_pi_user_password
# Purpose: Set up username and password for the Pi user account
get_pi_user_password() {
    # Prompt for the username, defaulting to 'pi'
    echo
    read -p "Enter the username (Press Enter to use default 'pi'): " PI_USERNAME
    if [ -z "$PI_USERNAME" ]; then
        PI_USERNAME="pi"
        echo "Using default username: $PI_USERNAME"
    else
        echo "Username set to: $PI_USERNAME"
    fi

    # Prompt for the password and hash it
    while true; do
        echo
        read -sp "Enter password for the '$PI_USERNAME' user (Press Enter to use default '$DEFAULT_PI_PASSWORD'): " PI_PASSWORD
        echo
        if [ -z "$PI_PASSWORD" ]; then
            PI_PASSWORD="$DEFAULT_PI_PASSWORD"
            echo "Default password 'raspberry' will be used."
        else
            # Confirm the password
            read -sp "Confirm password: " PI_PASSWORD_CONFIRM
            echo
            if [ "$PI_PASSWORD" != "$PI_PASSWORD_CONFIRM" ]; then
                echo "Passwords do not match. Please try again."
                continue
            fi
        fi

        # Hash the password (either user-provided or default)
        HASHED_PI_PASSWORD=$(openssl passwd -6 "$PI_PASSWORD")
        if [ -n "$HASHED_PI_PASSWORD" ]; then
            echo "Password hash generated successfully."
            break
        else
            echo "Failed to generate hashed password. Please try again."
        fi
    done

}


# Function: get_wifi_ssid
# Purpose: Prompt user for WiFi SSID
get_wifi_ssid() {
    echo
    read -p "Enter the WiFi SSID (Press Enter to use default [$DEFAULT_SSID]): " SSID
    if [ -z "$SSID" ]; then
        SSID="$DEFAULT_SSID"
        echo "Default SSID '$DEFAULT_SSID' will be used."
    fi
}


# Function: get_wifi_password
# Purpose: Prompt user for WiFi password and generate PSK
get_wifi_password() {
    echo
    while true; do
        read -sp "Enter WiFi Password for SSID $SSID: " WIFI_PASSWORD
        echo
        if [ -z "$WIFI_PASSWORD" ]; then
            echo "Password cannot be empty and must be at least 8 characters. Please try again."
        else
            PSK_HASH=$(wpa_passphrase "$SSID" "$WIFI_PASSWORD" | grep -oP '(?<=psk=)[a-f0-9]{64}')
            if [ -n "$PSK_HASH" ]; then
                echo "WiFi password accepted."
                break
            else
                echo "Failed to generate a valid PSK. Please try again."
            fi
        fi
    done
}


# Function: check_packages_installed
# Purpose: Ensure required packages are installed
check_packages_installed() {
for PACKAGE in dcfldd parted curl wget xz-utils pv; do
    if ! dpkg -s "${PACKAGE}" &>/dev/null; then
        echo "Installing "${PACKAGE}" "
        apt install "${PACKAGE}" -y
    fi
done
}

# Function: check_cached_images
# Purpose: Check for existing cached Raspberry Pi OS images
check_cached_images() {
    if [ ! -d "$IMAGES_DIR" ]; then
        mkdir -p "$IMAGES_DIR"
    fi
    local cached_image="$IMAGES_DIR/${PI_OS_FILENAME%.xz}"
    if [ -f "$cached_image" ]; then
        echo
        echo "Found cached image: $cached_image"
        IMAGE_FILENAME="$cached_image"
        return 0
    fi
    return 1
}


# Function: list_cached_images
# Purpose: Display a list of cached Raspberry Pi OS images
list_cached_images() {
    echo "Cached Raspberry Pi OS images:"
    local images=("$IMAGES_DIR"/*.img)
    if [ ${#images[@]} -eq 0 ] || [ "${images[0]}" = "$IMAGES_DIR/*.img" ]; then
        echo "No cached images found."
        return 1
    fi
    for i in "${!images[@]}"; do
        echo "$((i+1)). $(basename "${images[i]}")"
    done
    return 0
}


# Function: download_and_prepare_image
# Purpose: Download, verify, and decompress the latest Raspberry Pi OS image
download_and_prepare_image() {
    local image_url="${PI_OS_BASE}${PI_OS_FILENAME}"
    local sha256_url="${PI_OS_BASE}${PI_OS_SHA256}"
    local compressed_image="$IMAGES_DIR/${PI_OS_FILENAME}"
    local decompressed_image="${compressed_image%.xz}"

    if [ ! -d "$IMAGES_DIR" ]; then
        mkdir -p "$IMAGES_DIR"
    fi

    echo "Downloading latest Raspberry Pi OS image..."
    wget -q --show-progress -O "$compressed_image" "$image_url" || { echo "Failed to download image"; return 1; }

    echo "Downloading SHA256 checksum..."
    wget -q --show-progress -O "${compressed_image}.sha256" "$sha256_url" || { echo "Failed to download SHA256"; return 1; }

    echo "Verifying image integrity..."
    (cd "$IMAGES_DIR" && sha256sum -c "${PI_OS_FILENAME}.sha256") || { echo "SHA256 verification failed"; return 1; }

    if [[ "$PI_OS_FILENAME" == *.xz ]]; then
        decompress_image_with_progress "$compressed_image"
    else
        IMAGE_FILENAME="$compressed_image"
    fi

    echo "Image prepared successfully: $IMAGE_FILENAME"
}


# Function: get_latest_pi_os_versions
# Purpose: Retrieve the latest Raspberry Pi OS versions from the official download page
get_latest_pi_os_versions() {
    local base_url="https://downloads.raspberrypi.com"
    declare -gA PI_OS_VERSIONS
    echo
    echo "Retrieving latest Raspberry Pi OS versions..."

    for variant in "lite" "full"; do
        for arch in "arm64" "armhf"; do
            local download_page="${base_url}/raspios_${variant}_${arch}/images/"
            
            local page_content=$(curl -s "$download_page")
            local latest_version=$(echo "$page_content" | grep -oP '(?<=href=")[^"]*(?=/)' | grep -E '^raspios_.*[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort -V | tail -n 1)
            
            if [ -n "$latest_version" ]; then
                local image_page="${download_page}${latest_version}/"
                local image_page_content=$(curl -s "$image_page")
                local image_filename=$(echo "$image_page_content" | grep -oP '(?<=href=")[^"]*(?=")' | grep -E '\.img\.xz$' | head -n 1)
                
                if [ -n "$image_filename" ]; then
                    PI_OS_VERSIONS["${variant}_${arch}_base"]="${image_page}"
                    PI_OS_VERSIONS["${variant}_${arch}_filename"]="${image_filename}"
                    PI_OS_VERSIONS["${variant}_${arch}_sha256"]="${image_filename}.sha256"
                    echo "Found: Raspberry Pi OS ${variant^} (${arch}) - ${image_filename}"
                else
                    echo "Error: Failed to find image filename for ${variant} ${arch}"
                    return 1
                fi
            else
                echo "Error: Failed to find latest version for ${variant} ${arch}"
                return 1
            fi
        done
    done

    if [ ${#PI_OS_VERSIONS[@]} -ne 12 ]; then
        echo "Error: Failed to retrieve all necessary Raspberry Pi OS versions."
        return 1
    fi

    echo "Successfully retrieved all latest Raspberry Pi OS versions."
    return 0
}


# Function: use_default_versions
# Purpose: Set default Raspberry Pi OS versions when network retrieval fails
use_default_versions() {
    echo "Setting default Raspberry Pi OS versions..."
    # Set default versions here (update these periodically)
    PI_OS_VERSIONS["lite_arm64_base"]="https://downloads.raspberrypi.com/raspios_lite_arm64/images/raspios_lite_arm64-2024-07-04/"
    PI_OS_VERSIONS["lite_arm64_filename"]="2024-07-04-raspios-bookworm-arm64-lite.img.xz"
    PI_OS_VERSIONS["lite_arm64_sha256"]="2024-07-04-raspios-bookworm-arm64-lite.img.xz.sha256"
    
    PI_OS_VERSIONS["full_arm64_base"]="https://downloads.raspberrypi.com/raspios_full_arm64/images/raspios_full_arm64-2024-07-04/"
    PI_OS_VERSIONS["full_arm64_filename"]="2024-07-04-raspios-bookworm-arm64-full.img.xz"
    PI_OS_VERSIONS["full_arm64_sha256"]="2024-07-04-raspios-bookworm-arm64-full.img.xz.sha256"
    
    PI_OS_VERSIONS["lite_armhf_base"]="https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2024-07-04/"
    PI_OS_VERSIONS["lite_armhf_filename"]="2024-07-04-raspios-bookworm-armhf-lite.img.xz"
    PI_OS_VERSIONS["lite_armhf_sha256"]="2024-07-04-raspios-bookworm-armhf-lite.img.xz.sha256"
    
    PI_OS_VERSIONS["full_armhf_base"]="https://downloads.raspberrypi.com/raspios_full_armhf/images/raspios_full_armhf-2024-07-04/"
    PI_OS_VERSIONS["full_armhf_filename"]="2024-07-04-raspios-bookworm-armhf-full.img.xz"
    PI_OS_VERSIONS["full_armhf_sha256"]="2024-07-04-raspios-bookworm-armhf-full.img.xz.sha256"

    echo "Default versions set."
}


# Function: fetch_latest_os_versions
# Purpose: Attempt to fetch the latest OS versions or use defaults if network is unavailable
fetch_latest_os_versions() {
    if check_network_if_needed; then
        get_latest_pi_os_versions
    else
        echo "Network unavailable. Using default Raspberry Pi OS versions."
        use_default_versions
    fi
}


# Function: get_pi_os_image
# Purpose: Allow user to select a Raspberry Pi OS image or download a new one
get_pi_os_image() {
    echo
    echo "Available Raspberry Pi OS versions:"
    echo "1. Raspberry Pi OS Lite (64-bit) - Default"
    echo "2. Raspberry Pi OS Full (64-bit)"
    echo "3. Raspberry Pi OS Lite (32-bit)"
    echo "4. Raspberry Pi OS Full (32-bit)"
    read -p "Enter your choice (1-4, default is 1): " OS_CHOICE

    case $OS_CHOICE in
        2)
            PI_OS_BASE=${PI_OS_VERSIONS["full_arm64_base"]}
            PI_OS_FILENAME=${PI_OS_VERSIONS["full_arm64_filename"]}
            PI_OS_SHA256=${PI_OS_VERSIONS["full_arm64_sha256"]}
            echo;echo "Selected: Raspberry Pi OS Full (64-bit)"
            ;;
        3)
            PI_OS_BASE=${PI_OS_VERSIONS["lite_armhf_base"]}
            PI_OS_FILENAME=${PI_OS_VERSIONS["lite_armhf_filename"]}
            PI_OS_SHA256=${PI_OS_VERSIONS["lite_armhf_sha256"]}
            echo;echo "Selected: Raspberry Pi OS Lite (32-bit)"
            ;;
        4)
            PI_OS_BASE=${PI_OS_VERSIONS["full_armhf_base"]}
            PI_OS_FILENAME=${PI_OS_VERSIONS["full_armhf_filename"]}
            PI_OS_SHA256=${PI_OS_VERSIONS["full_armhf_sha256"]}
            echo;echo "Selected: Raspberry Pi OS Full (32-bit)"
            ;;
        *)
            PI_OS_BASE=${PI_OS_VERSIONS["lite_arm64_base"]}
            PI_OS_FILENAME=${PI_OS_VERSIONS["lite_arm64_filename"]}
            PI_OS_SHA256=${PI_OS_VERSIONS["lite_arm64_sha256"]}
            echo;echo "Selected: Raspberry Pi OS Lite (64-bit) - Default"
            ;;
    esac

    if [[ $OS_CHOICE == "3" || $OS_CHOICE == "4" ]]; then
        echo "Note: 32-bit versions are recommended for older Raspberry Pi models (Pi Zero, Pi 1, Pi 2, and Pi 3)."
        echo "For newer models (Pi 3+, Pi 4, Pi 400, Pi 5), the 64-bit version is recommended for better performance."
    fi


    # Check network connectivity after OS selection
    if ! check_network_if_needed; then
        echo "Network check failed. Exiting."
        exit 1
    fi


    while true; do
        echo "Enter the name of the Raspberry Pi OS image file [$PI_OS_FILENAME]"
        read -p "Type 'list' to see cached images, or press Enter to check for cached/download latest: " PI_OS_IMAGE
        
        if [ "$PI_OS_IMAGE" = "list" ]; then
            list_cached_images
            continue
        elif [ -z "$PI_OS_IMAGE" ]; then
            if check_cached_images; then
                PI_OS_IMAGE="$IMAGE_FILENAME"
                echo "Using cached image: $PI_OS_IMAGE"
                break
            else
                echo "No cached image found. Attempting to download the latest version."
                if download_and_prepare_image; then
                    PI_OS_IMAGE="$IMAGE_FILENAME"
                    echo
                    echo "Using downloaded image: $PI_OS_IMAGE"
                    break
                else
                    echo "Failed to download and prepare the image. Please try again or specify a local image file."
                fi
            fi
        elif [ -f "$IMAGES_DIR/$PI_OS_IMAGE" ]; then
            echo "Image file '$PI_OS_IMAGE' found."
            IMAGE_FILENAME="$IMAGES_DIR/$PI_OS_IMAGE"
            break
        else
            echo "File '$PI_OS_IMAGE' does not exist in the images directory. Please try again."
        fi
    done
}


# Function: check_sdcard_presence
# Purpose: Verify that an SD card is inserted and detected
check_sdcard_presence() {
    # echo
    if [ -z "$SDCARD" ]; then
        echo "No SD card detected. Please insert an SD card and try again."
        exit 1
    fi
    echo "Detected SD card: $SDCARD"
    # echo
}


# Function: confirm_sdcard_device
# Purpose: Confirm with the user that the correct SD card device is selected
confirm_sdcard_device() {
    echo
    read -p "Is this the correct SD card device path? [$SDCARD] (y/n) : " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        echo "Operation aborted."
        exit 1
    fi
}


# Function: unmount_sdcard_partitions
# Purpose: Safely unmount any mounted partitions on the SD card
unmount_sdcard_partitions() {
    # Check if any partitions are mounted and inform the user
    if mount | grep -q "${SDCARD}p1" || mount | grep -q "${SDCARD}p2"; then
        echo;echo "Partitions on the SD card (${SDCARD}) are currently mounted."
        echo "Attempting to unmount partitions..."

        # Attempt to unmount partition p1 if mounted
        if mount | grep -q "${SDCARD}p1"; then
            echo "Unmounting ${SDCARD}p1..."
            umount "${SDCARD}p1" || { echo "Failed to unmount ${SDCARD}p1. Exiting."; exit 1; }
        fi

        # Attempt to unmount partition p2 if mounted
        if mount | grep -q "${SDCARD}p2"; then
            echo "Unmounting ${SDCARD}p2..."
            umount "${SDCARD}p2" || { echo "Failed to unmount ${SDCARD}p2. Exiting."; exit 1; }
        fi

        echo "All mounted partitions on ${SDCARD} have been successfully unmounted."
    else
        echo "No partitions on ${SDCARD} are currently mounted."
    fi
}


# Function: write_image_to_sdcard
# Purpose: Write the selected Raspberry Pi OS image to the SD card
write_image_to_sdcard() {
    # Confirm with the user before proceeding
    echo -e "\nStarting imaging process.\nCopying '$IMAGE_FILENAME' to SD card '${SDCARD}'."
    echo; echo "This will ERASE ALL data on the SD card."
    read -p "Do you want to continue? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Imaging process aborted."
        exit 1
    fi

    # Get the total size of the image
    local total_size=$(stat -c %s "$IMAGE_FILENAME")

    echo -e "\nWriting image to SD card. Please wait..."
    
    # Use pv to show progress and dcfldd to write the image
    pv -s $total_size "$IMAGE_FILENAME" | dcfldd of="$SDCARD" bs=4M

    if [ ${PIPESTATUS[1]} -eq 0 ]; then
        echo -e "\nImage successfully written to ${SDCARD}."
    else
        echo -e "\nError: Failed to write image to ${SDCARD}. Please check the SD card and try again."
        exit 1
    fi
}


# Function: mount_sdcard_partitions
# Purpose: Mount the SD card partitions for further configuration
mount_sdcard_partitions() {
    local mount_error=false

    # Check if mount points exist, create them if they do not
    for mount_point in "$MOUNT_POINT_BOOT" "$MOUNT_POINT_ROOT"; do
        if [ ! -d "$mount_point" ]; then
            echo "Creating mount point: $mount_point"
            if ! mkdir -p "$mount_point"; then
                echo "Error: Failed to create mount point $mount_point"
                return 1
            fi
        fi
    done

    # Mount boot partition
    if ! mountpoint -q "$MOUNT_POINT_BOOT"; then
        echo "Mounting boot partition (${SDCARD}p1) to $MOUNT_POINT_BOOT"
        if ! mount "${SDCARD}p1" "$MOUNT_POINT_BOOT"; then
            echo "Error: Failed to mount ${SDCARD}p1 to $MOUNT_POINT_BOOT"
            mount_error=true
        fi
    else
        echo "$MOUNT_POINT_BOOT is already mounted."
    fi

    # Mount root partition
    if ! mountpoint -q "$MOUNT_POINT_ROOT"; then
        echo "Mounting root partition (${SDCARD}p2) to $MOUNT_POINT_ROOT"
        if ! mount "${SDCARD}p2" "$MOUNT_POINT_ROOT"; then
            echo "Error: Failed to mount ${SDCARD}p2 to $MOUNT_POINT_ROOT"
            mount_error=true
        fi
    else
        echo "$MOUNT_POINT_ROOT is already mounted."
    fi

    # Check if any mount errors occurred
    if [ "$mount_error" = true ]; then
        echo "One or more partitions failed to mount. Aborting."
        # Attempt to unmount any successfully mounted partitions
        unmount_sdcard_partitions
        return 1
    fi

    echo "SD card partitions mounted successfully."
    return 0
}


# Function: enable_console
# Purpose: Enable console access on the Raspberry Pi
enable_console() {
    echo
    echo "Enabling console"
    echo "dtoverlay=pi3-disable-bt" >> $CONFIG_FILE
    echo "enable_uart=1" >> $CONFIG_FILE
}


# Function: generate_custom_toml
# Purpose: Create a custom configuration file for Raspberry Pi OS
generate_custom_toml() {
    CUSTOM_TOML_FILE="$MOUNT_POINT_BOOT/custom.toml"

    echo "Creating custom.toml file at $CUSTOM_TOML_FILE..."

    cat <<EOF > "$CUSTOM_TOML_FILE"
# Raspberry Pi OS custom.toml
config_version = 1

[system]
hostname = "$PI_HOSTNAME"

[user]
name = "$PI_USERNAME"
password = "$HASHED_PI_PASSWORD"
password_encrypted = true

[ssh]
enabled = true
password_authentication = true

[wlan]
ssid = "$DEFAULT_SSID"
password = "$PSK_HASH"
password_encrypted = true
hidden = false
country = "GB"

[locale]
keymap = "gb"
timezone = "Europe/London"
EOF

    if [ $? -eq 0 ]; then
        echo "custom.toml successfully created."
    else
        echo "Error: Failed to create custom.toml. Please check the process and try again."
        exit 1
    fi
}

# Function: ping_until_alive
# Purpose: Continuously ping the newly configured Raspberry Pi until it responds
ping_until_alive() {
    echo
    echo "Your SDCARD is now ready to be used in your Pi. Remove the SDCARD and insert it into the Pi."
    echo "Power up the Pi and wait for a few minutes. If your Pi is older (e.g., Pi 2 or Pi Zero W), you may have to wait longer."
    echo

    read -p "Do you want to ping the new Raspberry Pi host to check if it's online? (y/n): " PING_CONFIRM

    if [[ ! "$PING_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Skipping the ping test."
        return
    fi

    echo
    read -p "Press Enter once the Raspberry Pi is powered on and connected to the network to start pinging..."

    local timeout=1200  # Set the timeout limit in seconds (20 minutes)
    local interval=5   # Time interval between pings in seconds
    local elapsed=0

    echo "Pinging $PI_HOSTNAME.local to check if it's online..."
    echo "Timeout set to 20 minutes to accommodate older Pi models."
    echo

    while true; do
        # Ping the hostname, limiting the number of pings to 1 and suppressing output
        if ping -c 1 -W 1 "$PI_HOSTNAME.local" > /dev/null 2>&1; then
            echo -e "\n$PI_HOSTNAME.local is online!"

            # Extract the IP address from the ping output
            IP_ADDRESS=$(ping -c 1 "$PI_HOSTNAME.local" | grep -oE '(([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])' | head -n 1)
            echo "Raspberry Pi IP address is: $IP_ADDRESS"

            # Provide SSH connection instructions
            echo -e "\nYou can now SSH into the Raspberry Pi using one of the following commands:"
            echo "ssh $PI_USERNAME@$PI_HOSTNAME.local"
            echo "ssh $PI_USERNAME@$IP_ADDRESS"
            echo
            echo "Thank you for using this Pi imaging script!"
            echo

            break
        else
            echo "Waiting for $PI_HOSTNAME.local to come online... ($elapsed/$timeout seconds)"
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))

        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Timeout reached. $PI_HOSTNAME.local did not respond within 20 minutes."
            echo "The Raspberry Pi might still be setting up. You can try manually pinging or connecting to it later."
            exit 1
        fi
    done
}

# Function: check_sdcard_size
# Purpose: Ensure the SD card meets the minimum size requirement
check_sdcard_size() {
    local min_size=$((16 * 1024 * 1024 * 1024))  # 16GB in bytes
    local sdcard_size=$(blockdev --getsize64 "$SDCARD")
    echo
    echo "Checking SD card size..."
    if [ "$sdcard_size" -lt "$min_size" ]; then
        echo "Error: SD card is too small. Minimum required size is 16GB."
        echo "Current SD card size: $(numfmt --to=iec-i --suffix=B $sdcard_size)"
        return 1
    fi
    echo "SD card size is sufficient: $(numfmt --to=iec-i --suffix=B $sdcard_size)"
    return 0
}

# Function: check_disk_space
# Purpose: Ensure there's enough disk space for downloading and writing the image
check_disk_space() {
    local required_space=8589934592  # 8GB in bytes (adjust if needed for largest image)
    local download_space=$(df -B1 "$IMAGES_DIR" | awk 'NR==2 {print $4}')
    echo
    echo "Checking available disk space for download..."
    if [ "$download_space" -lt "$required_space" ]; then
        echo "Error: Not enough space in $IMAGES_DIR for downloading the image."
        echo "Available: $(numfmt --to=iec-i --suffix=B $download_space)"
        echo "Required: $(numfmt --to=iec-i --suffix=B $required_space)"
        return 1
    fi
    echo "Sufficient disk space available for download: $(numfmt --to=iec-i --suffix=B $download_space)"
    return 0
}

# Function: ensure_sufficient_disk_space
# Purpose: Check for sufficient disk space and exit if not enough
ensure_sufficient_disk_space() {
    if ! check_sdcard_size; then
        echo "SD card does not meet minimum size requirements. Exiting."
        exit 1
    fi

    if ! check_disk_space; then
        echo "Insufficient disk space for download. Exiting."
        exit 1
    fi
}


# Function: check_network_if_needed
# Purpose: Check network connectivity if it hasn't been checked before
check_network_if_needed() {
    if [ -z "$NETWORK_CHECKED" ]; then
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            NETWORK_CHECKED=true
            return 0
        else
            echo "Network connection failed. Please check your internet connection."
            return 1
        fi
    fi
    return 0
}


# Function: ensure_network_connectivity
# Purpose: Ensure network connectivity is available for operations that require it
ensure_network_connectivity() {
    if ! check_network_if_needed; then
        echo "Network check failed. Exiting."
        exit 1
    fi
}


# MAIN
print_instructions
check_sdcard_presence
ensure_sufficient_disk_space
get_hostname
get_pi_user_password
get_wifi_ssid
get_wifi_password
check_packages_installed
fetch_latest_os_versions
get_pi_os_image
confirm_sdcard_device
unmount_sdcard_partitions
write_image_to_sdcard
mount_sdcard_partitions
enable_console
generate_custom_toml
unmount_sdcard_partitions
ping_until_alive
cleanup
