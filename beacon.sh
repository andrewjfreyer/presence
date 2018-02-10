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

Version=0.1.2
Base="/home/andrewjfreyer/presence"

# ----------------------------------------------------------------------------------------
# Configuration Scrupt
# ----------------------------------------------------------------------------------------

MQTT_CONFIG=$Base/mqtt_preferences ; [ -f $MQTT_CONFIG ] && source $MQTT_CONFIG
DELAY_CONFIG=$Base/behavior_preferences ; [ -f $DELAY_CONFIG ] && source $DELAY_CONFIG

# ----------------------------------------------------------------------------------------
# Load Beacons
# ----------------------------------------------------------------------------------------

if [ -f owner_beacons ]; then 
	IFS=$'\n' read -d '' -r -a owner_beacons < "$Base/owner_beacons"
fi 

if [ -f guest_beacons ]; then 
	IFS=$'\n' read -d '' -r -a guest_beacons < "$Base/guest_beacons"
fi 

#Number of clients that are monitored
numberOfOwners=$((${#owner_beacons[@]}))
numberOfGuests=$((${#guest_beacons[@]}))

#return if we don't have beacons to detect
if [ "$numberOfOwners" == "0" ] && [ "$numberOfGuests" == "0" ]; then 
	echo "No registered beacons. Exiting."
	exit 0
fi 

# ----------------------------------------------------------------------------------------
# Main Recursion
# ----------------------------------------------------------------------------------------

#record timestamps
ownerDeviceTimeStampArray=()

#refersh differnce
LAUNCHTIME=$(date +%s)

#main recursion 

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
					# Determine whether device is guest or owner
					# ----------------------------------------------------------------------------------------
					key="$UUID-$MAJOR-$MINOR"
					JSON_MSG="{\"confidence\":\"100\",\"name\":\"$key\",\"power\":\"$POWER\"}"
					found=0
		
					#iterate through owners
					for index in "${!owner_beacons[@]}"
					do
						#obtain individual address
						currentDeviceUUID="${owner_beacons[$index]}"

						if [ "$currentDeviceUUID" == "$key" ]; then 
							#device match found

							#send message via MQTT of beacon
							/usr/local/bin/mosquitto_pub -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath/owner/beacon/$key" -m "$JSON_MSG"

							#mark found
							found=1

							#mark timestamp last seen 
							ownerDeviceTimeStampArray[$index]=$(date +%s)
							break
						fi
					done

					#only if we did not discover an owner device, look for guest devices
					if [ "$found" == "0" ]; then 
						for index in "${!guest_beacons[@]}"
						do
							#obtain individual address
							currentDeviceUUID="${guest_beacons[$index]}"

							if [ "$currentDeviceUUID" == "$key" ]; then 
								#send message via MQTT of beacon
								/usr/local/bin/mosquitto_pub -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath/guest/beacon" -m "$JSON_MSG"
								break
							fi
						done
					fi
				else
					#THROTTLING 
					ENDTIME=$(date +%s)
					INTERVAL=$((ENDTIME - LAUNCHTIME))

					#only perform these calculations every few second
					if [ $((INTERVAL % 15 )) == 0 ]; then 
						#determine whether enough time has elapsed for each owner device
						for index in "${!ownerDeviceTimeStampArray[@]}"
						do
							#get time of this beacon
							STARTTIME="${ownerDeviceTimeStampArray[$index]}"
							ENDTIME=$(date +%s)

							#compare lapse since this beacon was last seen
							DIFFERENCE=$((ENDTIME - STARTTIME))

							#determine percentage confidence 
							if [ "$DIFFERENCE" -gt "$timeoutUntilAway" ]; then 
								percentage=0
							else 
                                percentage=$(( 100 - (100 * "$DIFFERENCE" / "$timeoutUntilAway"))) 
							fi 

							#get UUID
							currentDeviceUUID="${owner_beacons[$index]}"

							#update message
							JSON_MSG="{\"confidence\":\"$percentage\",\"name\":\"$currentDeviceUUID\",\"power\":\"$POWER\"}"
							/usr/local/bin/mosquitto_pub -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath/owner/beacon/$key" -m "$JSON_MSG"
						done

						#sleep until next interval
						sleep 1
					fi 
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
	# ----------------------------------------------------------------------------------------
	# Need to launch LESCAN at least once
	# ----------------------------------------------------------------------------------------

 	sudo hcitool lescan --duplicates 1>/dev/null &


	sudo hcidump --raw | bash $Base/beacon.sh parse $1
fi
