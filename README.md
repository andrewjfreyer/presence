presence
=======

***TL;DR***: *Bluetooth-based presence detection useful for [mqtt-based](http://mqtt.org) home automation. More granular, responsive, and reliable than device-reported GPS, does not require any app to be running or installed, does not require device pairing. Designed to run as service on a [Raspberry Pi Zero W](https://www.raspberrypi.org/products/raspberry-pi-zero-w/).*

<h1>Summary</h1>

A JSON-formatted MQTT message is reported to a broker whenever a specified bluetooth device responds to a **name** query. If the device responds, the JSON message includes the name of the device and a **confidence** of 100. 

After a delay, another **name** query is sent and, if the device does not respond, a verification-of-absence loop begins that queries for the device (on a shorter interval) a set number of times. Each time, the device does not respond, the **confidence** is reduced, eventually to 0. 

A configuration file defines 'owner devices' and another defines 'guest devices.' The script only scans for guest devices when not scanning for owner devices. 

Topics are formatted like this:

     location/owner/pi_zero_location/00:00:00:00:00:00 
     location/guest/pi_zero_location/00:00:00:00:00:00

Messages are JSON formatted and contain only **name** and **confidence** fields:

     { name : "Andrew's iPhone", confidence : 100}
     { name : "", confidence : 0}

<h1>Installation Instructions for fresh install of Raspbian Jessie Stretch:</h1>

*COMING SOON...*

   





