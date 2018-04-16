presence
=======

Bluetooth Presence Detection 

* Designed to run as service on a [Raspberry Pi Zero W](https://www.raspberrypi.org/products/raspberry-pi-zero-w/)
* Works with any number of devices and reports presence and absence on per-device basis
* Intended to work with a mqtt-based home automation system that would benefit from reliable presence detection
* Intended to be used on multiple [Raspberry Pi Zero Ws](https://www.raspberrypi.org/products/raspberry-pi-zero-w/) distributed at different locations throughout a home. 

<h1>Summary</h1>

A JSON-formatted MQTT message is reported to a specified broker whenever a specified MAC address responds to a **name** query from hcitool. The message includes the name of the device and a **confidence** of 100. After a delay, another **name** query is sent and, if the device does not respond, a verification-of-absence loop begins that queries for the device (on a shorter interval) a set number of times. Each time, the device does not respond, the **confidence** is reduced, eventually to 0. 

A configuration file defines 'owner devices' and another defines 'guest devices.' The script only scans for guest devices when not scanning for owner devices. 

Topics are formatted like this:

     location/owner/pi_zero_location/00:00:00:00:00:00 
     location/guest/pi_zero_location/00:00:00:00:00:00

Messages are JSON formatted and contain only **name** and **confidence** fields:

     { name : "Andrew's iPhone", confidence : 100}
     { name : "", confidence : 0}

<h1>Installation Instructions for fresh install of Raspbian Jessie Stretch:</h1>

*COMING SOON...*

   





