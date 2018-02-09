
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
Version=0.2.5

#load preferences if present
MQTT_CONFIG=mqtt_preferences ; [ -f $MQTT_CONFIG ] && source $MQTT_CONFIG

# ----------------------------------------------------------------------------------------
# Set Program Variables
# ----------------------------------------------------------------------------------------

delayBetweenOwnerScansWhenAway=7		#high number advised for bluetooth hardware 
delayBetweenOwnerScansWhenPresent=30	#high number advised for bluetooth hardware 
delayBetweenGuestScans=5				#high number advised for bluetooth hardware 
verifyByRepeatedlyQuerying=5 			#lower means more false rejection 

#or load from a source file
DELAY_CONFIG=behavior_preferences ; [ -f $DELAY_CONFIG ] && source $DELAY_CONFIG

#current guest
currentGuestIndex=0

# ----------------------------------------------------------------------------------------
# 	INCREMENT A WIFI BLUETOOTH ADDRESS AND RETURN
# ----------------------------------------------------------------------------------------

function incrementWiFiMacAddress () {
	if [ ! -z "$1" ]; then 

		#receive
		addr="$1"
		#trim to last two
		trim=${addr:15:2} #(echo "$addr" | tail -c 3)
		prefix=${addr:0:14}

		#math it
		mac_decimal=$(echo "obase=10;ibase=16; $trim" | bc ) # to convert to decimal
		mac_incremented=$(expr "$mac_decimal" + 1 ) # to add one 
		mac_hex_incremented=$(echo "obase=16;ibase=10; $mac_incremented" | bc ) # to convert to decimal

		#output variables
		bt_addr="$prefix:$(printf '%02x' 0x$mac_hex_incremented)"

		echo "$bt_addr"
	fi
}

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
				publish "/guest/$currentGuestDeviceAddress" '100' "$nameScanResult"
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
		echo "$1 {'confidence':'$2','name':'$3'}"
		/usr/local/bin/mosquitto_pub -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath$1" -m "{'confidence':'$2','name':'$3'}"
	fi
}

# ----------------------------------------------------------------------------------------
# ARGV processing 
# ----------------------------------------------------------------------------------------

#argv updates
if [ ! -z "$1" ]; then 
	#very rudamentary process here, only limited support for input functions
	case "$1" in
		-version )
			echo "$Version"
			exit 1
		;;
	    -b|-bluetooth )
			case "$2" in 
				-g|-guest )
					echo "$3" >> guest_devices
					exit 1
				;;
				-o|-owner )
					echo "$3" >> owner_devices
					exit 1
				;;
			esac
		;;
		-w|-wifi )
			case "$2" in 
				-g|-guest )
					incrementWiFiMacAddress "$3" >> guest_devices
					exit 1
				;;
				-o|-owner )
					incrementWiFiMacAddress "$3" >> owner_devices
					exit 1
				;;
			esac
		;;
	esac
fi 

# ----------------------------------------------------------------------------------------
# Preliminary Notifications
# ----------------------------------------------------------------------------------------

#Fill Address Array
if [ -f macaddress_guests ]; then 
	IFS=$'\n' read -d '' -r -a macaddress_guests < "guest_devices"
fi 

IFS=$'\n' read -d '' -r -a macaddress_owners < "owner_devices"

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

			#publish message
			publish "/owner/scan/$currentDeviceAddress" '100' "$nameScanResult"

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
					publish "/owner/scan/$currentDeviceAddress" '100' "$nameScanResult"

					deviceStatusArray[$index]="100"
					deviceNameArray[$index]="$nameScanResult"

					scanForGuests $delayBetweenOwnerScansWhenPresent
					break
				fi 

				#if we have 0, then we know we haven't been found yet
				if [ "${deviceStatusArray[$index]}" == "0" ]; then 
					break
				fi  

				#update percentage
				deviceStatusArray[$index]="$percentage"
				expectedName="${deviceNameArray[$index]}"

				#report confidence drop
				publish "/owner/scan/$currentDeviceAddress" "$percentage" "$expectedName"

				#set to percentage
				deviceStatusArray[$index]="$percentage"

				#delay default time
				scanForGuests $delayBetweenOwnerScansWhenAway
			
			done

			#publication of zero confidence in currently-tested device
			if [ "${deviceStatusArray[$index]}" == "0" ]; then 
				publish "/owner/scan/$currentDeviceAddress" '0'
			fi

			#continue with scan list
			scanForGuests $delayBetweenOwnerScansWhenAway
		fi
	done
done
