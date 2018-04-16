presence
=======

***TL;DR***: *Bluetooth-based presence detection useful for [mqtt-based](http://mqtt.org) home automation. More granular, responsive, and reliable than device-reported GPS, does not require any app to be running or installed, does not require device pairing. Designed to run as service on a [Raspberry Pi Zero W](https://www.raspberrypi.org/products/raspberry-pi-zero-w/).*

<h1>Summary</h1>

A JSON-formatted MQTT message is reported to a broker whenever a specified bluetooth device responds to a **name** query. If the device responds, the JSON message includes the name of the device and a **confidence** of 100. 

After a delay, another **name** query is sent and, if the device does not respond, a verification-of-absence loop begins that queries for the device (on a shorter interval) a set number of times. Each time, the device does not respond, the **confidence** is reduced, eventually to 0. 

A configuration file defines 'owner devices' and another defines 'guest devices.' The script only scans for guest devices when not scanning for owner devices; detection of owner devices is prioritized over detection of guest devices. 

Topics are formatted like this:

     location/owner/pi_zero_location/00:00:00:00:00:00 
     location/guest/pi_zero_location/00:00:00:00:00:00

Messages are JSON formatted and contain only **name** and **confidence** fields:

     { name : "Andrew's iPhone", confidence : 100}
     { name : "", confidence : 0}

<h1>Installation Instructions for fresh install of Raspbian Jessie Stretch:</h1>

<h2>Setup of SD Card</h2>

1. Download latest version of **jessie lite stretch** [here](https://downloads.raspberrypi.org/raspbian_lite_latest)

2. Download etcher from [etcher.io](https://etcher.io)

3. Image **jessie lite stretch** to SD card

4. Mount **boot** partition of imaged SD card

5. **[ENABLE SSH]** Create blank file, without any extension, in the root directory called **ssh**

6. **[SETUP WIFI]** Create **wpa_supplicant.conf** file in root directory and add Wi-Fi details for home Wi-Fi:

```
country=US
    ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
    update_config=1

network={
    ssid="Your Network Name"
    psk="Your Network Password"
    key_mgmt=WPA-PSK
}
```

 7. **[FIRST STARTUP]** Insert SD card and power on Raspberry Pi Zero W. On first boot, the newly-created **wpa_supplicant.conf** file and **ssh** will be moved to appropriate directories. Find the IP address of the Pi via your router. One method is scanning for open ssh ports (port 22) on your local network:
```
nmap 192.168.1.0/24 -p 22
```

<h2>Configuration and Setup of Raspberry Pi Zero Z</h2>

1. SSH into the Raspberry Pi (password: raspberry):
```
ssh pi@theipaddress
```

2. Change the default password:
```
sudo passwd pi
```

3. **[PREPARATION]** Update and upgrade:

```
sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get dist-upgrade -y
sudo rpi-update
```

4. **[BLUEZ]** Compile/install latest **bluez**
```

#purge old bluez
sudo apt-get --purge remove bluez

#get latest version number from: https://www.kernel.org/pub/linux/bluetooth/
cd ~; wget https://www.kernel.org/pub/linux/bluetooth/bluez-XX.XX.tar.xz
tar xvf bluez-X.XX.tar.xz

#install necessary packages
sudo apt-get install libusb-dev libdbus-1-dev libglib2.0-dev libudev-dev libical-dev libreadline-dev

#move into new unpacked directory
cd bluez-X.XX

#set exports
export LDFLAGS=-lrt

#configure 
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-library -disable-systemd

#make & install
make
sudo make install

#cleanup
cd ~
rm -r bluez-X.XX/
rm bluez-X.XX.tar.xz

#update again
sudo apt-get update
sudo apt-get upgrade -y
```

6. **[BLUETOOTH]** Install Bluetooth Firmware:
```

#select the option to keep the 'bluez' that is already installed
sudo apt-get install pi-bluetooth

#verify that bluetooth is working
sudo service bluetooth start
sudo service bluetooth status
```

7. **[REBOOT]**
```
sudo reboot
```

8. **[INSTALL MOSQUITTO]**
```

# get repo key
wget http://repo.mosquitto.org/debian/mosquitto-repo.gpg.key

#add repo
sudo apt-key add mosquitto-repo.gpg.key

#download appropriate lists file 
cd /etc/apt/sources.list.d/
sudo wget http://repo.mosquitto.org/debian/mosquitto-stretch.list

#update caches and install 
apt-cache search mosquitto
sudo apt-get update
sudo aptitude install libmosquitto-dev mosquitto mosquitto-clients
```


9. **[INSTALL PRESENCE]**
```
#install git
sudo apt-get install git
cd ~

#clone this repo
git clone git://github.com/andrewjfreyer/presence

#enter presence directory
cd presence/
```

10. **[CONFIGURE PRESENCE]** create file named **mqtt_preferences** and include content:
```

mqtt_address="ip.address.of.broker"
mqtt_user="your broker username"
mqtt_password="your broker password"
mqtt_topicpath="location"
mqtt_room="your pi's location"
```

11. **[CONFIGURE PRESENCE]** create file named **owner_devices** and include mac addresses of devices on separate lines. Do the same with a file named **guest_devices**. Leave either or both files empty if tracking isn't required.
```

00:00:00:00:00
00:00:00:00:00
```

12. **[CONFIGURE SERVICE]** Create file at **/etc/systemd/system/presence.service** and include content:
```
[Unit]
Description=Presence service

[Service]
User=root
ExecStart=/bin/bash /home/pi/presence/presence.sh &
WorkingDirectory=/home/pi/presence
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target

```

13. **[CONFIGURE SERVICE]** Enable service by:
```
sudo systemctl enable presence.service
sudo systemctl start presence.service
```

That's it. Your broker should be receiving messages. 

