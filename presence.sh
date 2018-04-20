
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
# INCLUDES & VARIABLES
# ----------------------------------------------------------------------------------------

Version=0.4.01

#base directory regardless of installation
Base=$(dirname "$(readlink -f "$0")")
MQTTPubPath=$(which mosquitto_pub)

#color output 
RED='\033[0;31m'
NC='\033[0m'

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

	#delay type
	delayToImplement=$1

	#if we have guest devices to scan for, then scan for them!
	if [ ! -z "$macaddress_guests" ]; then 

		#calculate 
		DIFFERENCE=$((ENDTIME - STARTTIME))

		#start while loop during owner scans; using a while loop here instead of 
		#a for loop so that we can exit the loop on time without missing
		#guest scans. For example, if the owner loop only permits 5 seconds to scan, 
		#we might only be able to scan one guest at a time per call of 
		#this function. 

		while [ $DIFFERENCE -lt $delayToImplement ]
		do

			#calculate remainder of delay
			MAX_DELAY=$((delayToImplement - DIFFERENCE)) 

			#cache bluetooth results 
			nameScanResult=""

			#obtain individual address
			currentGuestDeviceAddress="${macaddress_guests[$currentGuestIndex]}"

			(>&2 echo "Delay: $currentGuestDeviceAddress")

			#check if we've already scanned this device recently
			if [ "${seen[$currentGuestIndex]}" == "1" ]; then 

				##make sure that we're not implementing a negative delay
				MAX_DELAY=$(( MAX_DELAY > 0 ? MAX_DELAY : 0 ))

				#delay to the max value
				sleep $MAX_DELAY 

				#we have already been notified of this guest device already in this loop; time to break
				break
			fi
			
			#iterate the current guest that we're looking for
			currentGuestIndex=$((currentGuestIndex+1))
			
			#correct the guest index

			if [ "$currentGuestIndex" -gt "$(( numberOfGuests - 1 ))" ] ; then 
				currentGuestIndex=0
			fi

			#mark as seen
			seen[$currentGuestIndex]=1

			#mark beginning of scan operation
			STARTSCAN_GUEST=$(date +%s%N)

			#obtain results and append each to the same
			nameScanResult=$(scan $currentGuestDeviceAddress)
			
			#mark end of scan operation
			ENDSCAN_GUEST=$(date +%s%N)
			
			#calculate difference
			SCAN_DURATION_GUEST=$(( (ENDSCAN_GUEST - STARTSCAN_GUEST) / 1000000 )) 
			
			#this device name is present
			if [ "$nameScanResult" != "" ]; then
				#publish the presence of the guest 
				publish "/guest/$mqtt_room/$currentGuestDeviceAddress" '100' "$nameScanResult" "$SCAN_DURATION_GUEST"
			else
				publish "/guest/$mqtt_room/$currentGuestDeviceAddress" '0' "$nameScanResult" "$SCAN_DURATION_GUEST"
			fi

			#set endtime 
			ENDTIME=$(date +%s)

			#refersh differnce
			DIFFERENCE=$((ENDTIME - STARTTIME)) 

		done

		#calculate final max delay
		MAX_DELAY=$((delayToImplement - DIFFERENCE)) 

		#less than zero? 
		MAX_DELAY=$(( MAX_DELAY > 0 ? MAX_DELAY : 0 ))

		#sleep the maximum delay 
		sleep $MAX_DELAY

	else
		#default sleep; no guest devices
		sleep $1
    fi
}

# ----------------------------------------------------------------------------------------
# Array Contains
# ----------------------------------------------------------------------------------------

function arrayContainsElement () {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

# ----------------------------------------------------------------------------------------
# Scan script
# ----------------------------------------------------------------------------------------

function scan () {
	if [ ! -z "$1" ]; then 
		result=$(hcitool name "$1" 2>&1 | grep -v 'not available')
		echo "$result" 
	fi
}

# ----------------------------------------------------------------------------------------
# Publish Message
# device mac address; percentage
# ----------------------------------------------------------------------------------------

function publish () {
	if [ ! -z "$1" ]; then 

		#set name for 'unkonwn'
		name="$3"

		#if no name, return "unknown"
		if [ -z "$3" ]; then 
			name="Unknown"
		fi 

		#timestamp
		stamp=$(date "+%a %b %d %Y %H:%M:%S GMT%z (%Z)")

		#debugging 
		(>&2 echo "Message: $1 $2 $3 $4 $stamp")
		#post to mqtt
		$MQTTPubPath -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath$1" -m "{\"confidence\":\"$2\",\"name\":\"$name\",\"scan_duration_ms\":\"$4\",\"timestamp\":\"$stamp\"}"
	fi
}

# ----------------------------------------------------------------------------------------
# Preliminary Notifications
# ----------------------------------------------------------------------------------------

#Fill Address Array]
macaddress_guests=($(cat "$Base/guest_devices" | grep -oiE "([0-9a-f]{2}:){5}[0-9a-f]{2}" ))
macaddress_owners=($(cat "$Base/owner_devices" | grep -oiE "([0-9a-f]{2}:){5}[0-9a-f]{2}" ))

#Number of clients that are monitored
numberOfOwners=$((${#macaddress_owners[@]}))
numberOfGuests=$((${#macaddress_guests[@]}))

# ----------------------------------------------------------------------------------------
# Main Loop
# ----------------------------------------------------------------------------------------

beaconArray=()			#stores idenfiers that record which macs are associated with beacons
deviceStatusArray=()	#stores status for each bluetooth devices
deviceNameArray=()		#stores device names for both beacons and bluetooth devices

# ----------------------------------------------------------------------------------------
# Check user 
# ----------------------------------------------------------------------------------------

IS_ROOT=1

if [[ $EUID -ne 0 ]] && [ "$beaconScanEnabled" == 1 ] ; then
  	echo -e "${RED}WARNING: ${NC}Beacon detection requires root; man hcitool for detail."
  	echo -e "Any BTLE Beacon MAC addresses in the 'owner_devices' configuration" 
  	echo -e "file will be treated as standard bluetooth devices and will likely"
  	echo -e "always return a confidence of 0. Performance may be degraded for "
  	echo -e "other devices." 
  	echo -e "" 
   	IS_ROOT=0
fi

#begin the operational loop
while true; do 

	#--------------------------------------
	#	OPEN SCANNING FOR BLUETOOTH LE DEVICES
	#--------------------------------------
	if [ "$IS_ROOT" == 1 ] && [ "$beaconScanEnabled" == 1 ] ; then 
		BEACONS_RAW=$(sudo timeout --signal SIGINT $beaconScanInterval hcitool lescan --duplicates 2>&1)
		BEACONS_NOW=$(echo "$BEACONS_RAW" | grep -Ei "([0-9a-f]{2}:){5}[0-9a-f]{2}" | sort -u)

		#check interface health, restore if necessary
		if [ "$BEACONS_RAW" == "Set scan parameters failed: Input/output error" ];then
			echo -e "${RED}WARNING: ${NC}Bluetooth interface went down. Restoring now."
			sudo hciconfig hci0 down
			sudo hciconfig hci0 up
		fi

	else
		BEACONS_NOW=""
	fi 

	#--------------------------------------
	#	UPDATE STATUS OF ALL USERS WITH NAME QUERY
	#--------------------------------------
	for index in "${!macaddress_owners[@]}"
	do
		#clear per-loop variables
		nameScanResult=""

		#obtain individual address
		currentDeviceAddress="${macaddress_owners[$index]}"

		#was found? 
		IS_BEACON=$(echo "$BEACONS_NOW" | grep -ic $currentDeviceAddress)

		#check for additional blank lines in address file
		if [ -z "$currentDeviceAddress" ]; then 
			continue
		fi

		#test if current device was found on a beacon scan

		if [ "$IS_BEACON" == 0 ]; then  
			#mark beginning of scan operation
			STARTSCAN=$(date +%s%N)

			#obtain results and append each to the same
			nameScanResult=$(scan $currentDeviceAddress)
			
			#mark end of scan operation
			ENDSCAN=$(date +%s%N)
			
			#calculate difference
			SCAN_DURATION=$(( (ENDSCAN - STARTSCAN) / 1000000 )) 
		else

			#set the name as the device addres
			nameScanResult="$currentDeviceAddress"

			#set scan duration to timeout
			SCAN_DURATION="$((beaconScanInterval * 1000))"

			#set beacon array so that we can ignore if beacon leaves
			beaconArray[$index]=1

		fi 
		#echo to stderr for debug and testing
		#(>&2 echo "Duration: $SCAN_DURATION ms")

		#this device name is present
		if [ "$nameScanResult" != "" ]; then

			#no duplicate messages
			publish "/owner/$mqtt_room/$currentDeviceAddress" '100' "$nameScanResult" "$SCAN_DURATION"

			#user status			
			deviceStatusArray[$index]="100"

			#set name array
			deviceNameArray[$index]="$nameScanResult"

		else

			#Handle beacons first
			was_beacon="${beaconArray[$index]}"

			#if this was previously marked as a beacon, skip name scanning
			if [ "$was_beacon" == '1' ]; then 
				#no duplicate messages
				publish "/owner/$mqtt_room/$currentDeviceAddress" '0' "$nameScanResult" "$SCAN_DURATION"

				#user status			
				deviceStatusArray[$index]="0"

				#set name array
				deviceNameArray[$index]="$nameScanResult"

				#next mac address
				continue
			fi 

			#if we do not have a beacon...

			#user status			
			status="${deviceStatusArray[$index]}"

			if [ -z "$status" ]; then 
				status="0"
			fi 

			#by default, set repetition to preference
			repetitions="$verifyByRepeatedlyQuerying"

			#if we are just starting or, alternatively, we have recorded the status 
			#of not home already, only scan one more time. 
			if [ "$status" == 0 ];then 
				repetitions=1
			fi 

			#should verify absense
			for repetition in $(seq 1 $repetitions); 
			do 

				#get percentage
				percentage=$(($status * ( $repetitions - $repetition) / $repetitions))

				#only scan if our status is not already 0
				if [ "$status" != 0 ];then 

					#mark beginning of scan operation
					STARTSCAN=$(date +%s%N)

					#perform scan
					nameScanResultRepeat=$(scan $currentDeviceAddress)

					#mark end of scan operation
					ENDSCAN=$(date +%s%N)
					
					#calculate difference
					SCAN_DURATION=$(( (ENDSCAN - STARTSCAN) / 1000000 )) 

				fi 
				#(>&2 echo "Duration: $SCAN_DURATION ms")

				#checkstan
				if [ "$nameScanResultRepeat" != "" ]; then
					#we know that we must have been at a previously-seen user status
					deviceStatusArray[$index]="100"

					#update name array
					deviceNameArray[$index]="$nameScanResultRepeat"

					publish "/owner/$mqtt_room/$currentDeviceAddress" '100' "$nameScanResultRepeat" "$SCAN_DURATION"

				else
					#update status array
					deviceStatusArray[$index]="$percentage"

					#retreive last-known name for publication
					expectedName="${deviceNameArray[$index]}"

					#report confidence drop
					publish "/owner/$mqtt_room/$currentDeviceAddress" "$percentage" "$expectedName" "$SCAN_DURATION"
				fi 
			done
		fi
	done

	#check status array for any device marked as 'home'
	if [ "$(arrayContainsElement "100" ${deviceStatusArray[@]})" == 0 ]; then 
		scanForGuests $delayBetweenOwnerScansWhenPresent
	else
		scanForGuests $delayBetweenOwnerScansWhenAway
	fi 
done

