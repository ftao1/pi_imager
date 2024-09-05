#!/bin/bash

#set -xv


#=============== Check if root is running script ===============
#
if [[ $(id -u) -ne 0 ]] ; then
    echo " This script can only be run as root. Please run as root"
    exit -1
fi


# Variables
SDCARD=$(fdisk -l | grep Disk | grep mmc | awk '{print $2}' | sed 's/://')
MOUNT_POINT_BOOT="/mnt/sdcard_boot"
MOUNT_POINT_ROOT="/mnt/sdcard_root"
CONFIG_FILE="$MOUNT_POINT_BOOT/config.txt"
DEFAULT_HOSTNAME="raspberrypi"
DEFAULT_PI_PASSWORD="raspberry"
DEFAULT_SSID="home"
IMAGE_FILENAME="2024-07-04-raspios-bookworm-arm64-lite.img"


# Function to provide instructions and usage
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
    echo
    echo "NOTE: Please ensure you provide a valid image for your Pi. Older Pi's only work with"
    echo "the 32bit version of Pi OS."
    echo
}


# Function to prompt for the hostname and confirm it
get_hostname() {
    read -p "Enter the hostname for the Raspberry Pi (Press Enter to use default '$DEFAULT_HOSTNAME'): " PI_HOSTNAME
    if [ -z "$PI_HOSTNAME" ]; then
        PI_HOSTNAME="$DEFAULT_HOSTNAME"
        echo "Using default hostname: $PI_HOSTNAME"
    else
        echo "Hostname set to: $PI_HOSTNAME"
    fi
}


# Function to prompt for username, pi user password, confirm it, and hash it
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

    # Prompt for the password
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


# Function to prompt for SSID
get_wifi_ssid() {
    echo
    read -p "Enter the WiFi SSID (Press Enter to use default [$DEFAULT_SSID]): " SSID
    if [ -z "$SSID" ]; then
        SSID="$DEFAULT_SSID"
        echo "Default SSID '$DEFAULT_SSID' will be used."
    fi
}


# Function to prompt for WiFi password and generate the PSK
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
    echo $PSK_HASH
}


# Function to check packages are installed
check_packages_installed() {
for PACKAGE in dcfldd parted; do
    if ! dpkg -s "${PACKAGE}" &>/dev/null; then
        echo "Installing "${PACKAGE}" "
        apt install "${PACKAGE}" -y
    fi
done
}


# Function to prompt for the Pi OS image file and check for its existence
get_pi_os_image() {
    echo
    while true; do
        read -p "Enter the name of the Raspberry Pi OS image file ["$IMAGE_FILENAME"]: " PI_OS_IMAGE
        # Use the default image if the user doesn't provide one
        if [ -z "$PI_OS_IMAGE" ]; then
            PI_OS_IMAGE="$IMAGE_FILENAME"
            echo "No image file name provided."
            echo "Default image '$PI_OS_IMAGE' will be used."
        fi

        # Check if the image file exists
        if [ -f "$PI_OS_IMAGE" ]; then
            echo "Image file '$PI_OS_IMAGE' found."
            break
        else
            echo "File '$PI_OS_IMAGE' does not exist in the current directory. Please try again."
        fi
    done
}


# Function to check if an SD card is present
check_sdcard_presence() {
    echo
    if [ -z "$SDCARD" ]; then
        echo "No SD card detected. Please insert an SD card and try again."
        exit 1
    fi
    echo "Detected SD card: $SDCARD"
    echo
}


# Function to confirm the SD card device path with the user
confirm_sdcard_device() {
    read -p "Is this the correct SD card device path? [$SDCARD] (y/n) : " CONFIRM
    if [[ "$CONFIRM" != "y" ]]; then
        echo "Operation aborted."
        exit 1
    fi
}


# Function to unmount SD card partitions and inform the user
unmount_sdcard_partitions() {
    MOUNTED=false

    # Check if any partitions are mounted and inform the user
    if mount | grep -q "${SDCARD}p1" || mount | grep -q "${SDCARD}p2"; then
        echo "Partitions on the SD card (${SDCARD}) are currently mounted."
        echo "Attempting to unmount partitions..."

        # Attempt to unmount partition p1 if mounted
        if mount | grep -q "${SDCARD}p1"; then
            echo "Unmounting ${SDCARD}p1..."
            umount "${SDCARD}p1" || { echo "Failed to unmount ${SDCARD}p1. Exiting."; exit 1; }
            MOUNTED=true
        fi

        # Attempt to unmount partition p2 if mounted
        if mount | grep -q "${SDCARD}p2"; then
            echo "Unmounting ${SDCARD}p2..."
            umount "${SDCARD}p2" || { echo "Failed to unmount ${SDCARD}p2. Exiting."; exit 1; }
            MOUNTED=true
        fi

        # Final feedback if partitions were successfully unmounted
        if [ "$MOUNTED" = true ]; then
            echo "All mounted partitions on ${SDCARD} have been successfully unmounted."
        fi
    else
        echo "No partitions on ${SDCARD} are currently mounted."
    fi
}


# Function to write the Pi OS image to the SD card
write_image_to_sdcard() {
    # Confirm with the user before proceeding
    echo -e "\nStarting imaging process.\nCopying '$PI_OS_IMAGE' to SD card '${SDCARD}'."
    echo "This will ERASE ALL data on the SD card."
    read -p "Do you want to continue? (y/n): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Imaging process aborted."
        exit 1
    fi

    # Write the image to the SD card using dcfldd
    echo -e "\nWriting image to SD card. Please wait..."
    dcfldd if="$PI_OS_IMAGE" of="$SDCARD" status=progress

    if [ $? -eq 0 ]; then
        echo -e "\nImage successfully written to ${SDCARD}."
    else
        echo -e "\nError: Failed to write image to ${SDCARD}. Please check the SD card and try again."
        exit 1
    fi
}


# Function to mount SD card partitions
mount_sdcard_partitions() {
    # Check if mount points exist, create them if they do not
    if [ ! -d "$MOUNT_POINT_BOOT" ]; then
        echo "Creating mount point for boot partition: $MOUNT_POINT_BOOT"
        mkdir -p "$MOUNT_POINT_BOOT"
    fi

    if [ ! -d "$MOUNT_POINT_ROOT" ]; then
        echo "Creating mount point for root partition: $MOUNT_POINT_ROOT"
        mkdir -p "$MOUNT_POINT_ROOT"
    fi

    # Check if the SD card partitions are already mounted
    if mountpoint -q "$MOUNT_POINT_BOOT"; then
        echo "$MOUNT_POINT_BOOT is already mounted."
    else
        echo "Mounting boot partition ($SDCARD"p1") to $MOUNT_POINT_BOOT"
        mount "${SDCARD}p1" "$MOUNT_POINT_BOOT"
        if [ $? -ne 0 ]; then
            echo "Failed to mount $SDCARD"p1" to $MOUNT_POINT_BOOT"
            exit 1
        fi
    fi

    if mountpoint -q "$MOUNT_POINT_ROOT"; then
        echo "$MOUNT_POINT_ROOT is already mounted."
    else
        echo "Mounting root partition ($SDCARD"p2") to $MOUNT_POINT_ROOT"
        mount "${SDCARD}p2" "$MOUNT_POINT_ROOT"
        if [ $? -ne 0 ]; then
            echo "Failed to mount $SDCARD"p2" to $MOUNT_POINT_ROOT"
            exit 1
        fi
    fi
}


# Function to enable console on the boot partition
enable_console() {
    echo "Enabling console"
    echo "dtoverlay=pi3-disable-bt" >> $CONFIG_FILE
    echo "enable_uart=1" >> $CONFIG_FILE
}


# Function to generate the custom.toml file for Raspberry Pi OS configuration
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


# Function to continuously ping the hostname until a response is received
ping_until_alive() {

    echo
    echo "Your SDCARD is now ready to be used in your Pi. Remove the SDCARD and insert it into the Pi."
    echo "Power up the Pi and wait for a few minutes. If your Pi is older, you may have to wait longer."
    echo

    read -p "Do you want to ping the new Raspberry Pi host to check if it's online? (y/n): " PING_CONFIRM

    if [[ ! "$PING_CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Skipping the ping test."
        return
    fi

    echo
    read -p "Press Enter once the Raspberry Pi is powered on and connected to the network to start pinging..."

    local timeout=600  # Set the timeout limit in seconds (10 minutes)
    local interval=5   # Time interval between pings in seconds
    local elapsed=0

    echo "Pinging $PI_HOSTNAME.local to check if it's online..."
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
            echo "Timeout reached. $PI_HOSTNAME.local did not respond."
            exit 1
        fi
    done
}

# MAIN
print_instructions
check_sdcard_presence
get_hostname
get_pi_user_password
get_wifi_ssid
get_wifi_password
check_packages_installed
get_pi_os_image
confirm_sdcard_device
unmount_sdcard_partitions
write_image_to_sdcard
mount_sdcard_partitions
enable_console
generate_custom_toml
unmount_sdcard_partitions
ping_until_alive
