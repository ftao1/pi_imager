# pi_imager

## Bash script to write Pi OS bookworm to SD Card with customisations.

## Pre-amble
I wanted a quicker CLI way to write Pi images to SD Card that has customisations I wanted but was lacking in the
official Pi Imager.
The official Imager already has a lot of customisation, but lacks console enablement and I didn't want to
keep manually adding it after an image burn.

The script is self-explanatory and prompts you for values such as user, password, wifi details and attempts to
provide the IP address of the Pi once its up so you can ssh to it.

## Testing
The script has been tested for Pi Zero W, Pi 3 and Pi 4 all running Bookworm 32bit and 64bit versions.

## Usage
The script has been designed to work with Bookworm for the time being.
```bash
git clone https://github.com/ftao1/pi_imager.git
cd pi_imager
sudo pi_imager
```

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
Depending on where you are, you will probably want to change the locale info. This file once confgured is save in the
boot partition and read on first boot.

## NOTES:
I've added a few default values to speed up my processes so they may not work for you. You will need to change:
```bash
DEFAULT_SSID="home"
IMAGE_FILENAME="2024-07-04-raspios-bookworm-arm64-lite.img"
```

Set your own Wi-Fi SSID and your choice of default image.


## License

MIT

## Author

These configurations are maintained by F.Tao.
