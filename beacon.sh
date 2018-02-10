#!/bin/bash

# ----------------------------------------------------------------------------------------
# GENERAL INFORMATION
# ----------------------------------------------------------------------------------------
#
# iBeacon Scan by Radius Networks
#
# Edited by Andrew J Freyer
# version 20180209
# GNU General Public License
#
# ----------------------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------------------

Version=0.1.1
Base="/home/andrewjfreyer/presence"

# ----------------------------------------------------------------------------------------
# Configuration Scrupt
# ----------------------------------------------------------------------------------------

MQTT_CONFIG=$Base/mqtt_preferences ; [ -f $MQTT_CONFIG ] && source $MQTT_CONFIG

# ----------------------------------------------------------------------------------------
# Main Recursion
# ----------------------------------------------------------------------------------------

if [[ $1 == "parse" ]]; then
	packet=""
	capturing=""
	count=0
	while read line
	do
		count=$[count + 1]
		if [ "$capturing" ]; then
			if [[ $line =~ ^[0-9a-fA-F]{2}\ [0-9a-fA-F] ]]; then
				packet="$packet $line"
			else
				# ----------------------------------------------------------------------------------------
				# Beacon Decoding
				# ----------------------------------------------------------------------------------------
				if [[ $packet =~ ^04\ 3E\ 2A\ 02\ 01\ .{26}\ 02\ 01\ .{14}\ 02\ 15 ]]; then
					UUID=`echo $packet | sed 's/^.\{69\}\(.\{47\}\).*$/\1/'`
					MAJOR=`echo $packet | sed 's/^.\{117\}\(.\{5\}\).*$/\1/'`
					MINOR=`echo $packet | sed 's/^.\{123\}\(.\{5\}\).*$/\1/'`
					POWER=`echo $packet | sed 's/^.\{129\}\(.\{2\}\).*$/\1/'`
					UUID=`echo $UUID | sed -e 's/\ //g' -e 's/^\(.\{8\}\)\(.\{4\}\)\(.\{4\}\)\(.\{4\}\)\(.\{12\}\)$/\1-\2-\3-\4-\5/'`
					MAJOR=`echo $MAJOR | sed 's/\ //g'`
					MAJOR=`echo "ibase=16; $MAJOR" | bc`
					MINOR=`echo $MINOR | sed 's/\ //g'`
					MINOR=`echo "ibase=16; $MINOR" | bc`
					POWER=`echo "ibase=16; $POWER" | bc`
					POWER=$[POWER - 256]

					# ----------------------------------------------------------------------------------------
					# Inform MQTT
					# ----------------------------------------------------------------------------------------
		
					#compare UUID to database
					JSON_MSG="{\"confidence\":\"100\",\"name\":\"\",\"uuid\":\"$UUID\",\"major\":\"$MAJOR\",\"minor\":\"$MINOR\",\"power\":\"$POWER\"}"

					#send message via MQTT of beacon
					/usr/local/bin/mosquitto_pub -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath/owner/beacon" -m "$JSON_MSG"

				fi
				capturing=""
				packet=""
			fi
		fi

		if [ ! "$capturing" ]; then
			
			if [[ $line =~ ^\> ]]; then
				packet=`echo $line | sed 's/^>.\(.*$\)/\1/'`
				capturing=1
			fi
		fi
	done
else
	sudo hcidump --raw | ./$0 parse $1
fi
