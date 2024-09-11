# pi_imager

## Bash script to write Pi OS Bookworm to SD Card with customisations.

## Preamble
I wanted a quicker CLI way to write Pi images to SD Card that has customisations I wanted but was lacking in the
official Pi Imager.
The official Imager already has a lot of customisation, but lacks console enablement and I didn't want to
keep manually adding it after an image burn.

The script is self-explanatory and prompts you for values such as user, password, wifi details and attempts to
provide the IP address of the Pi once its up so you can ssh to it.

## Testing
The script has been tested for Pi Zero W, Pi Zero 2W, Pi 3 and Pi 4 all running Bookworm 32bit and 64bit versions.

## Usage
The script has been designed to work with Pi OS Bookworm only.
```bash
git clone https://github.com/ftao1/pi_imager.git
cd pi_imager
sudo ./pi_imager.sh
```
The script is interactive and will prompt for values for user, password, Wi-Fi SSID, Wi-Fi password. It will also
enable SSH, and the console for boards that have the GPIO. Once the info has been gathered, the config file is
saved to the boot partition. Upon first time boot, the script will attempt to get the IP of the Pi to make it
easy to ssh to.

## Pi First Boot Customisations changes for Bookworm
In the past versions of Pi OS, the way to customise the image on first boot was to add various files to the boot
partition such as ssh, wpa_supplicant. Bookworm on the other hand does away with this and instead uses a config file
called "**custom.toml**". This file contains most of the configs a user might need eg default user, ssh, Wi-Fi details etc.
The custom.toml file in this script looks like this:
```bash
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
```
Depending on where you are, you will probably want to change the locale info. This file once confgured, is saved in the
boot partition and read on first boot.

## NOTES:
I've added a default values to speed up my processes so they may not work for you. You will need to change:
```bash
DEFAULT_SSID="home"
```
Set your own Wi-Fi SSID and your choice of default image.

The script was developed on a laptop with built in SD Card reader with default device `/dev/mmcblk0`. This
device is used in the script.


## License

MIT

## Author

These configurations are maintained by F.Tao.
