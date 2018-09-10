presence
=======

***Note: as of `presence` 0.5.1, triggered scans, guest scanning, and beacon scanning are removed from `presence.sh` for simplification. Please consider using [monitor](http://github.com/andrewjfreyer/monitor) instead for beacon scanning and detection and for generic device detection. It is unlikely that `presence` will receive substantive updates after version 0.5.1.***

____


***TL;DR***: *Bluetooth-based presence detection useful for [mqtt-based](http://mqtt.org) home automation. More granular, responsive, and reliable than device-reported GPS. Cheaper, more reliable, more configurable, and less mqtt-spammy than Happy Bubbles. Does not require any app to be running or installed. Does not require device pairing. Designed to run as service on a [Raspberry Pi Zero W](https://www.raspberrypi.org/products/raspberry-pi-zero-w/).*

Note that the more frequently you scan for devices, the more 2.4GHz bandwidth you will use. This script may cause interference with Wi-Fi or other bluetooth devices for particularly short delays between scans. 

<h1>Summary</h1>

A JSON-formatted MQTT message is reported to a broker whenever a specified bluetooth device responds to a **name** query. If the device responds, the JSON message includes the name of the device and a **confidence** of 100. 

After a delay, another **name** query is sent and, if the device does not respond, a verification-of-absence loop begins that queries for the device (on a shorter interval) a set number of times. Each time, the device does not respond, the **confidence** is reduced, eventually to 0. 

A configuration file defines 'owner devices' that contains the mac addresses of the devices you'd like to regularly ping to determine presence. 

Topics are formatted like this:

     location/pi_zero_location/00:00:00:00:00:00 

Messages are JSON formatted and contain **name** and **confidence** fields, including a javascript-formatted timestamp and a duration of a particular scan (in ms):

     { confidence : 100, name : Andrew’s iPhone, scan_duration_ms: 500, timestamp : Sat Apr 21 2018 11:52:04 GMT-0600 (MDT)}
     { confidence : 0, name : Andrew’s iPhone or Unknown, scan_duration_ms: 5000, timestamp : Sat Apr 21 2018 11:52:04 GMT-0600 (MDT)}

___

<h1>Example Use with Home Assistant</h1>

The presence script can be used as an input to a number of [mqtt sensors](https://www.home-assistant.io/components/sensor.mqtt/) in [Home Assistant.](https://www.home-assistant.io). Output from these sensors can be averaged to give a highly-accurate numerical occupancy confidence. 

In order to detect presence in a home that has three floors and a garage, we might include one Raspberry Pi per floor. For average houses, a single well-placed sensor can probably work, but for more reliability at the edges of the house, more sensors are better. 


```
- platform: mqtt
  state_topic: 'location/first floor/00:00:00:00:00:00'
  value_template: '{{ value_json.confidence }}'
  unit_of_measurement: '%'
  name: 'Andrew First Floor'

- platform: mqtt
  state_topic: 'location/second floor/00:00:00:00:00:00'
  value_template: '{{ value_json.confidence }}'
  unit_of_measurement: '%'
  name: 'Andrew Second Floor'

- platform: mqtt
  state_topic: 'location/third floor/00:00:00:00:00:00'
  value_template: '{{ value_json.confidence }}'
  unit_of_measurement: '%'
  name: 'Andrew Third Floor'

- platform: mqtt
  state_topic: 'location/garage/00:00:00:00:00:00'
  value_template: '{{ value_json.confidence }}'
  unit_of_measurement: '%'
  name: 'Andrew Garage'
```

These sensors can be combined/averaged using a [min_max](https://www.home-assistant.io/components/sensor.min_max/):

```
- platform: min_max
  name: "Andrew Home Occupancy Confidence"
  type: mean
  round_digits: 0
  entity_ids:
    - sensor.andrew_garage
    - sensor.andrew_third_floor
    - sensor.andrew_second_floor
    - sensor.andrew_first_floor
```

So, as a result of this combination, we use the entity **sensor.andrew_home_occupancy_confidence** in automations to control the state of an **input_boolean** that represents a very high confidence of a user being home or not. 

As an example:

```
- alias: Andrew Occupancy 
  hide_entity: true
  trigger:
    - platform: numeric_state
      entity_id: sensor.andrew_home_occupancy_confidence
      above: 10
  action:
    - service: homeassistant.turn_on
      data:
        entity_id: input_boolean.andrew_occupancy
```

___


<h1>Installation Instructions (Raspbian Jessie Lite Stretch):</h1>

<h2>Setup of SD Card</h2>

1. Download latest version of **jessie lite stretch** [here](https://downloads.raspberrypi.org/raspbian_lite_latest)

2. Download etcher from [etcher.io](https://etcher.io)

3. Image **jessie lite stretch** to SD card. [Instructions here.](https://www.raspberrypi.org/magpi/pi-sd-etcher/)

4. Mount **boot** partition of imaged SD card (unplug it and plug it back in)

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

<h2>Configuration and Setup of Raspberry Pi Zero W</h2>

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
sudo reboot
```

5. **[BLUETOOTH]** Install Bluetooth Firmware:
```
#install bluetooth drivers for Pi Zero W
sudo apt-get install pi-bluetooth

#verify that bluetooth is working
sudo service bluetooth start
sudo service bluetooth status
```

6. **[OPTIONAL: BLUEZ UPGRADE]** Compile/install latest **bluez** 

This is not strictly required anymore, as **pi-bluetooth** appears to have been updated to support bluez 0.5.43.

```

#purge old bluez
sudo apt-get --purge remove bluez

#get latest version number from: https://www.kernel.org/pub/linux/bluetooth/
#current version as of this writing is 5.49
cd ~; wget https://www.kernel.org/pub/linux/bluetooth/bluez-5.49.tar.xz
tar xvf bluez-5.49.tar.xz

#update errythang again
sudo apt-get update

#install necessary packages
sudo apt-get install libusb-dev libdbus-1-dev libglib2.0-dev libudev-dev libical-dev libreadline-dev

#move into new unpacked directory
cd bluez-5.49

#set exports
export LDFLAGS=-lrt

#configure 
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --enable-library -disable-systemd

#make & install
make
sudo make install

#cleanup
cd ~
rm -r bluez-5.49/
rm bluez-5.49.tar.xz

#update again
sudo apt-get update
sudo apt-get upgrade

#verify bluez version 
bluetoothd -v
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
cd ~
sudo apt-get install git

#clone this repo
git clone git://github.com/andrewjfreyer/presence

#enter presence directory
cd presence/
```

10. **[CONFIGURE PRESENCE]** create file named **mqtt_preferences** and include content:
```
nano mqtt_preferences
```

Then...

```
mqtt_address="ip.address.of.broker"
mqtt_port="optional broker network port number. Defaults to 1883"
mqtt_user="your broker username"
mqtt_password="your broker password"
mqtt_topicpath="location"
mqtt_room="your pi's location"
```

11. **[CONFIGURE PRESENCE]** create file named **owner_devices** and include mac addresses of devices on separate lines. 

```
nano owner_devices
```

Then...

```
00:00:00:00:00 #comments 
00:00:00:00:00
```

12. **[CONFIGURE SERVICE]** Create file at **/etc/systemd/system/presence.service** and include content:

```
sudo nano /etc/systemd/system/presence.service
```

Then...

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

That's it. Your broker should be receiving messages and the presence service will restart each time the Raspberry Pi boots.  

