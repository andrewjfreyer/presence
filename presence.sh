
#!/bin/bash

# ----------------------------------------------------------------------------------------
# GENERAL INFORMATION
# ----------------------------------------------------------------------------------------
#
# Written by Andrew J Freyer
# GNU General Public License
#
# ----------------------------------------------------------------------------------------
#
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# INCLUDES
# ----------------------------------------------------------------------------------------

Version=0.3.4
Base="/home/andrewjfreyer/presence"

#load preferences if present
MQTT_CONFIG=$Base/mqtt_preferences ; [ -f $MQTT_CONFIG ] && source $MQTT_CONFIG

# ----------------------------------------------------------------------------------------
# Set Program Variables
# ----------------------------------------------------------------------------------------

#or load from a source file
DELAY_CONFIG=$Base/behavior_preferences ; [ -f $DELAY_CONFIG ] && source $DELAY_CONFIG

#current guest
currentGuestIndex=0

# ----------------------------------------------------------------------------------------
# SCAN FOR GUEST DEVICES DURING OWNER DEVICE TIMEOUTS
# ----------------------------------------------------------------------------------------

function scanForGuests () {
	#to determine correct exit time for while loop
	STARTTIME=$(date +%s)

	#init end time
	ENDTIME=0

	#this time
	seen=()

	#if we have guest devices to scan for, then scan for them!
	if [ ! -z "$macaddress_guests" ]; then 

		#calculate 
		DIFFERENCE=$((ENDTIME - STARTTIME))

		#start while loop during owner scans
		while [ $DIFFERENCE -lt $delayBetweenOwnerScansWhenPresent ]
		do

			#cache bluetooth results 
			nameScanResult=""

			#obtain individual address
			currentGuestDeviceAddress="${macaddress_guests[$currentGuestIndex]}"

			#check if seen
			if [ "${seen[$currentGuestIndex]}" == "1" ]; then 
				
				#calculate remainder of delay
				DELAY=$((delayBetweenOwnerScansWhenPresent - DIFFERENCE)) 

				#delay
				sleep $DELAY 

				break
			fi

			#mark as seen
			seen[$currentGuestIndex]=1

			#obtain results and append each to the same
			nameScanResult=$(scan $currentGuestDeviceAddress)
			
			#this device name is present
			if [ "$nameScanResult" != "" ]; then
				#publish the presence of the guest 
				publish "/guest/$mqtt_room/$currentGuestDeviceAddress" '100' "$nameScanResult"
			fi

			#iterate the current guest that we're looking for
			currentGuestIndex=$((currentGuestIndex+1))

			#correct the guest index
			if [ "$numberOfGuests" == "$currentGuestIndex" ]; then 
				currentGuestIndex=0
			fi

			#sleep between guest scans
			sleep $delayBetweenGuestScans 

			#set endtime 
			ENDTIME=$(date +%s)

			#refersh differnce
			DIFFERENCE=$((ENDTIME - STARTTIME)) 
		done

	else
		sleep $1
    fi
}

# ----------------------------------------------------------------------------------------
# Scan script
# ----------------------------------------------------------------------------------------

function scan () {
	if [ ! -z "$1" ]; then 
		echo $(hcitool name "$1" 2>&1 | grep -v 'not available')
	fi
}

# ----------------------------------------------------------------------------------------
# Publish Message
# device mac address; percentage
# ----------------------------------------------------------------------------------------

function publish () {
	if [ ! -z "$1" ]; then 
		#echo "$1 {'confidence':'$2','name':'$3'}"
		$(which mosquitto_pub) -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath$1" -m "{\"confidence\":\"$2\",\"name\":\"$3\"}"
	fi
}

# ----------------------------------------------------------------------------------------
# Preliminary Notifications
# ----------------------------------------------------------------------------------------

#Fill Address Array
IFS=$'\n' read -d '' -r -a macaddress_guests < "$Base/guest_devices"
IFS=$'\n' read -d '' -r -a macaddress_owners < "$Base/owner_devices"

#Number of clients that are monitored
numberOfOwners=$((${#macaddress_owners[@]}))
numberOfGuests=$((${#macaddress_guests[@]}))

# ----------------------------------------------------------------------------------------
# Main Loop
# ----------------------------------------------------------------------------------------

deviceStatusArray=()
deviceNameArray=()

#begin the operational loop
while (true); do	

	#--------------------------------------
	#	UPDATE STATUS OF ALL USERS
	#--------------------------------------
	for index in "${!macaddress_owners[@]}"
	do
		#cache bluetooth results 
		nameScanResult=""

		#obtain individual address
		currentDeviceAddress="${macaddress_owners[$index]}"

		#obtain results and append each to the same
		nameScanResult=$(scan $currentDeviceAddress)
		
		#this device name is present
		if [ "$nameScanResult" != "" ]; then

			#no duplicate messages
			publish "/owner/$mqtt_room/$currentDeviceAddress" '100' "$nameScanResult"

			#user status			
			deviceStatusArray[$index]="100"

			#set name array
			deviceNameArray[$index]="$nameScanResult"

			#we're sure that we're home, so scan for guests
			scanForGuests $delayBetweenOwnerScansWhenPresent

		else
			#user status			
			status="${deviceStatusArray[$index]}"

			if [ -z "$status" ]; then 
				status="0"
			fi 

			#should verify absense
			for repetition in $(seq 1 $verifyByRepeatedlyQuerying); 
			do 
				#get percentage
				percentage=$(($status * ( $verifyByRepeatedlyQuerying - $repetition) / $verifyByRepeatedlyQuerying))

				#perform scan
				nameScanResultRepeat=$(scan $currentDeviceAddress)

				#checkstan
				if [ "$nameScanResultRepeat" != "" ]; then
					#we know that we must have been at a previously-seen user status
					publish "/owner/$mqtt_room/$currentDeviceAddress" '100' "$nameScanResult"

					deviceStatusArray[$index]="100"
					deviceNameArray[$index]="$nameScanResult"

					scanForGuests $delayBetweenOwnerScansWhenPresent
					break
				fi 

				#update percentage
				deviceStatusArray[$index]="$percentage"
				expectedName="${deviceNameArray[$index]}"

				#report confidence drop
				publish "/owner/$mqtt_room/$currentDeviceAddress" "$percentage" "$expectedName"

				#set to percentage
				deviceStatusArray[$index]="$percentage"

				#delay default time
				scanForGuests $delayBetweenOwnerScansWhenAway
			done

			#publication of zero confidence in currently-tested device
			if [ "${deviceStatusArray[$index]}" == "0" ]; then 
				publish "/owner/$mqtt_room/$currentDeviceAddress" '0'
			fi

			#continue with scan list
			scanForGuests $delayBetweenOwnerScansWhenAway
		fi
	done
done
