
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

#version number
Version=0.4.05

#color output 
ORANGE='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'

#base directory regardless of installation
Base=$(dirname "$(readlink -f "$0")")
MQTTPubPath=$(which mosquitto_pub)

#load preferences if present
MQTT_CONFIG=$Base/mqtt_preferences ; [ -f $MQTT_CONFIG ] && source $MQTT_CONFIG

# ----------------------------------------------------------------------------------------
# Set Program Variables
# ----------------------------------------------------------------------------------------

#startup message
echo -e "${GREEN}presence $Version ${NC} - Started"

#or load from a source file
if [ ! -f "$Base/behavior_preferences" ]; then 
	echo -e "${GREEN}presence $Version ${RED}WARNING:  ${NC}Behavior preferences are not defined in:"
	echo -e "/behavior_preferences. Creating file and setting default values."
  	echo -e "" 

  	#default values
  	echo "nameScanTimeout=3"						>> "$Base/behavior_preferences"
  	echo "delayBetweenOwnerScansWhenAway=8" 		>> "$Base/behavior_preferences"
	echo "delayBetweenOwnerScansWhenPresent=45"		>> "$Base/behavior_preferences"
	echo "verifyByRepeatedlyQuerying=7"				>> "$Base/behavior_preferences"
	echo "verificationLoopDelay=3"					>> "$Base/behavior_preferences"
	echo "beaconScanInterval=5"						>> "$Base/behavior_preferences"
	echo "beaconScanEnabled=0"						>> "$Base/behavior_preferences"

fi  

#set preferences from file
DELAY_CONFIG="$Base/behavior_preferences" ; [ -f $DELAY_CONFIG ] && source $DELAY_CONFIG

#current guest
currentGuestIndex=0

# ----------------------------------------------------------------------------------------
# ERROR CHECKING FOR BEHAVIOR PREFERENCES 
# ----------------------------------------------------------------------------------------

#name scan timeout
if [[ "$nameScanTimeout" -lt 2 ]]; then 
	echo -e "${GREEN}presence $Version - ${RED}WARNING:"
	echo -e "${NC}Name scan timeout is relatively low at $(( nameScanTimeout > 0 ? nameScanTimeout : 0)). New bluetooth "
	echo -e "devices may take more time than this to be discovered."
fi 

#name scan timeout
if [[ "$nameScanTimeout" -gt 5 ]]; then 
	echo -e "${GREEN}presence $Version - ${RED}WARNING:"
	echo -e "${NC}Name scan timeout is relatively high at $(( nameScanTimeout > 0 ? nameScanTimeout : 0)). Built-in"
	echo -e "timeout, by default, is around five seconds."
fi 

#owner scans when away
if [[ "$delayBetweenOwnerScansWhenAway" -lt 5 ]]; then 
	echo -e "${GREEN}presence $Version - ${RED}WARNING:"
	echo -e "${NC}Delay between owner scans when away is relatively"
	echo -e "low at $(( delayBetweenOwnerScansWhenAway > 0 ? delayBetweenOwnerScansWhenAway : 0)). This may slow down the server because the BT hardware"
	echo -e "will be actively scanning more frequently. Consider increasing"
	echo -e "this value. The greater this value, the more time it will take"
	echo -e "to recognize when a device has arrived."
fi 

#owner scans when present
if [[ "$delayBetweenOwnerScansWhenPresent" -lt 20 ]]; then 
	echo -e "${GREEN}presence $Version - ${RED}WARNING:"
	echo -e "${NC}Delay between owner scans when present is relatively"
	echo -e "low at $(( delayBetweenOwnerScansWhenPresent > 0 ? delayBetweenOwnerScansWhenPresent : 0)). This may slow down the server because the BT hardware"
	echo -e "will be actively scanning more frequently. Consider increasing"
	echo -e "this value. The greater this value, the more time it will take"
	echo -e "to recognize that a devices has left."
fi 

#verification loop size
if [[ "$verifyByRepeatedlyQuerying" -lt 5 ]]; then 
	echo -e "${GREEN}presence $Version - ${RED}WARNING:"
	echo -e "${NC}Verification loop (i.e., verifyByRepeatedlyQuerying) is relatively"
	echo -e "low at $(( verifyByRepeatedlyQuerying > 0 ? verifyByRepeatedlyQuerying : 0)). This can increase the risk of false exit events."
	echo -e "The greater this value, the lower the probability of false exit events."
fi 

#verification loop delay
if [[ "$verificationLoopDelay" -lt 2 ]]; then 
	echo -e "${GREEN}presence $Version - ${RED}WARNING:"
	echo -e "${NC}Verification loop delay is relatively short or"
	echo -e "low at $verificationLoopDelay. This can increase the risk of false exit events."
	echo -e "The greater this value, the lower the probability of "
	echo -e "false exit events."
fi 

#beacons
if [[ "$beaconScanInterval" -lt 5 ]] && [[ "$beaconScanEnabled" == 1 ]]; then 
	echo -e "${GREEN}presence $Version - ${RED}WARNING:"
	echo -e "${NC}Beacon scan interval is relatively low at $(( beaconScanInterval > 0 ? beaconScanInterval : 0)). This reduces the changes"
	echo -e "that a beacon will be broadcasting when this script is listening."
	echo -e "The greater this value, the greater the liklihood that a present beacon"
	echo -e "will be recognized."
fi 

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

		#Print Delay for debugging
		(>&2 echo -e "${ORANGE} DEBUG Appropriate Delay: $MAX_DELAY")

		#sleep the maximum delay 
		sleep $MAX_DELAY

	else
		#error corrections; need to have minimum delay
		MAX_DELAY=$(( delayToImplement > 0 ? delayToImplement : 5))

		#Print Delay for debugging
		(>&2 echo -e "${ORANGE} DEBUG Appropriate Delay: $MAX_DELAY")

		#default sleep; no guest devices
		sleep $MAX_DELAY
    fi
}

# ----------------------------------------------------------------------------------------
# Scan script
# ----------------------------------------------------------------------------------------

function scan () {
	if [ ! -z "$1" ]; then 
		result=$(timeout --signal SIGINT $nameScanTimeout hcitool name "$1" 2>&1 | grep -v 'not available')
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
		(>&2 echo "$mqtt_topicpath$1 { confidence : $2, name : $3, scan_duration_ms: $4, timestamp : $stamp}")

		#post to mqtt
		$MQTTPubPath -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath$1" -m "{\"confidence\":\"$2\",\"name\":\"$name\",\"scan_duration_ms\":\"$4\",\"timestamp\":\"$stamp\"}"
	fi
}

# ----------------------------------------------------------------------------------------
# Preliminary Notifications
# ----------------------------------------------------------------------------------------

#Fill Address Array with support for comments
macaddress_guests=($(cat "$Base/guest_devices" | grep -oiE "([0-9a-f]{2}:){5}[0-9a-f]{2}" ))
macaddress_owners=($(cat "$Base/owner_devices" | grep -oiE "([0-9a-f]{2}:){5}[0-9a-f]{2}" ))

#Number of clients that are monitored
numberOfOwners=$((${#macaddress_owners[@]}))
numberOfGuests=$((${#macaddress_guests[@]}))

# ----------------------------------------------------------------------------------------
# Main Loop
# ----------------------------------------------------------------------------------------

beaconDeviceArray=()	#stores idenfiers that record which macs are associated with beacons
deviceStatusArray=()	#stores status for each bluetooth devices
deviceNameArray=()		#stores device names for both beacons and bluetooth devices
oneDeviceHome=0

# ----------------------------------------------------------------------------------------
# Check user 
# ----------------------------------------------------------------------------------------

IS_ROOT=1

if [[ $EUID -ne 0 ]] && [ "$beaconScanEnabled" == 1 ] ; then
  	echo -e "${GREEN}presence $Version ${RED}WARNING:  ${NC}Beacon detection requires root; man hcitool for detail."
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
			echo -e "${GREEN}presence $Version ${RED}WARNING:  ${NC}Bluetooth interface went down. Restoring now..."
			sudo hciconfig hci0 down
			sleep 1
			sudo hciconfig hci0 up
		fi
	else

		#if we do not have beacon detection enabled, set the array to blank
		BEACONS_NOW=""
	fi 

	#reset at least one device home
	oneDeviceHome=0

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
			### NON BEACON ###

			#mark beginning of scan operation
			STARTSCAN=$(date +%s%N)

			#obtain results and append each to the same
			nameScanResult=$(scan $currentDeviceAddress)
			
			#mark end of scan operation
			ENDSCAN=$(date +%s%N)
			
			#calculate difference
			SCAN_DURATION=$(( (ENDSCAN - STARTSCAN) / 1000000 )) 
		else
			### BEACON ###

			#set the name as the device addres
			nameScanResult="$currentDeviceAddress"

			#set scan duration to timeout
			SCAN_DURATION="$((beaconScanInterval * 1000))"

			#set beacon array so that we can ignore if beacon leaves
			beaconDeviceArray[$index]=1

		fi 
		#echo to stderr for debug and testing
		#(>&2 echo "Duration: $SCAN_DURATION ms")

		#this device name is present
		if [ "$nameScanResult" != "" ]; then

			#no duplicate messages
			publish "/owner/$mqtt_room/$currentDeviceAddress" '100' "$nameScanResult" "$SCAN_DURATION"

			#user status			
			deviceStatusArray[$index]="100"

			#set at least one device home
			oneDeviceHome=1

			#set name array
			deviceNameArray[$index]="$nameScanResult"

		else

			#Handle beacons first
			was_beacon="${beaconDeviceArray[$index]}"

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
				#verification loop delay
				sleep "$verificationLoopDelay"

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

				#check scan 
				if [ "$nameScanResultRepeat" != "" ]; then
					#we know that we must have been at a previously-seen user status
					deviceStatusArray[$index]="100"

					#update name array
					deviceNameArray[$index]="$nameScanResultRepeat"

					publish "/owner/$mqtt_room/$currentDeviceAddress" '100' "$nameScanResultRepeat" "$SCAN_DURATION"

					#set at least one device home
					oneDeviceHome=1

					#must break confidence scanning loop; 100' iscovered
					break

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
	if [ "$oneDeviceHome" == 1 ]; then 
				#Print Delay for debugging
		(>&2 echo -e "${ORANGE}DEBUG Scanning for $numberOfGuests guest devices between owner scans when at least one device is present.")
		scanForGuests $delayBetweenOwnerScansWhenPresent
	else
		(>&2 echo "${ORANGE}DEBUG Scanning for $numberOfGuests guest devices between scans when no owner device is present.")
		scanForGuests $delayBetweenOwnerScansWhenAway
	fi 
done

