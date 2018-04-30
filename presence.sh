
#!/bin/bash

# ----------------------------------------------------------------------------------------
# GENERAL INFORMATION
# ----------------------------------------------------------------------------------------
#
# Written by Andrew J Freyer
# GNU General Public License
# http://github.com/andrewjfreyer/presence
#
# ----------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------
# INCLUDES & VARIABLES
# ----------------------------------------------------------------------------------------

#VERSION NUMBER
VERSION=0.4.27

#COLOR OUTPUT FOR RICH DEBUG 
ORANGE='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
GREEN='\033[0;32m'
PURPLE='\033[1;35m'

#BASE DIRECTORY REGARDLESS OF INSTALLATION; ELSE MANUALLY SET HERE
base_directory=$(dirname "$(readlink -f "$0")")

#FIND MQTT PATH, ELSE MANUALLY SET HERE
mosquitto_pub_path=$(which mosquitto_pub)
mosquitto_sub_path=$(which mosquitto_sub)

#ERROR CHECKING FOR MOSQUITTO PUBLICATION 
[ -z "$mosquitto_pub_path" ] && echo "Required package 'mosquitto_pub' not found." && exit 1

#CURRENT GUEST THAT CAN ITERATE OVER MULTIPLE INTER-OWNER SCANS 
current_guest_index=0

# ----------------------------------------------------------------------------------------
# LOAD PREFERENCES
# ----------------------------------------------------------------------------------------

#OR LOAD FROM A SOURCE FILE
if [ ! -f "$base_directory/behavior_preferences" ]; then 
	echo -e "${GREEN}presence $VERSION ${RED}WARNING:  ${NC}Behavior preferences are not defined in:${NC}"
	echo -e "/behavior_preferences. Creating file and setting default values.${NC}"
  	echo -e "" 

  	#DEFAULT VALUES
  	echo "name_scan_timeout=5"						>> "$base_directory/behavior_preferences"
  	echo "delay_between_owner_scans_away=6" 		>> "$base_directory/behavior_preferences"
	echo "delay_between_owner_scans_present=30"		>> "$base_directory/behavior_preferences"
	echo "verification_of_away_loop_size=6"			>> "$base_directory/behavior_preferences"
	echo "verification_of_away_loop_delay=3"		>> "$base_directory/behavior_preferences"
	echo "beacon_scan_interval=5"					>> "$base_directory/behavior_preferences"
	echo "beacon_scan_enabled=0"					>> "$base_directory/behavior_preferences"
fi  

# ----------------------------------------------------------------------------------------
# BACKWARD COMPATBILITY FOR BEHAVIOR PREFERENCES
# ----------------------------------------------------------------------------------------
[ -z "$name_scan_timeout" ] && name_scan_timeout=$nameScanTimeout
[ -z "$delay_between_owner_scans_away" ] && delay_between_owner_scans_away=$delayBetweenOwnerScansWhenAway
[ -z "$delay_between_owner_scans_present" ] && delay_between_owner_scans_present=$delayBetweenOwnerScansWhenPresent
[ -z "$verification_of_away_loop_size" ] && verification_of_away_loop_size=$verifyByRepeatedlyQuerying
[ -z "$verification_of_away_loop_delay" ] && verification_of_away_loop_delay=$verificationLoopDelay
[ -z "$beacon_scan_interval" ] && beacon_scan_interval=$beaconScanInterval
[ -z "$beacon_scan_enabled" ] && beacon_scan_enabled=$beaconScanEnabled

if [ ! -z $nameScanTimeout ];then 
	echo -e "${GREEN}presence $VERSION - ${RED}WARNING:$"
	echo -e "Please update behavior_preferences variable naming scheme by deleting the existing file."
fi 

# ----------------------------------------------------------------------------------------
# VARIABLE DEFINITIONS 
# ----------------------------------------------------------------------------------------

#SET PREFERENCES FROM FILE
DELAY_CONFIG="$base_directory/behavior_preferences" ; [ -f $DELAY_CONFIG ] && source $DELAY_CONFIG

#LOAD PREFERENCES IF PRESENT
MQTT_CONFIG=$base_directory/mqtt_preferences ; [ -f $MQTT_CONFIG ] && source $MQTT_CONFIG

#FILL ADDRESS ARRAY WITH SUPPORT FOR COMMENTS
macaddress_guests=($(cat "$base_directory/guest_devices" | grep -oiE "([0-9a-f]{2}:){5}[0-9a-f]{2}" ))
macaddress_owners=($(cat "$base_directory/owner_devices" | grep -oiE "([0-9a-f]{2}:){5}[0-9a-f]{2}" ))

#NUMBER OF CLIENTS THAT ARE MONITORED
number_of_owners=$((${#macaddress_owners[@]}))
number_of_guests=$((${#macaddress_guests[@]}))

# ----------------------------------------------------------------------------------------
# HELP TEXT
# ----------------------------------------------------------------------------------------

show_help_text() {
	echo "Usage:"
	echo "  presence -h 		show usage information"
	echo "  presence -d 		print debug messages and mqtt messages"
	echo "  presence -b 		binary output only; either 100 or 0 confidence"
	echo "  presence -c 		only post confidence status changes for owners/guests"
	echo "  presence -t <1,2>	trigger mode; only scan in response to MQTT message posted"
	echo "			to '$mqtt_topicpath/scan'. The payload of the message can"
	echo "			include a 'duration' value to define how long the looping"
	echo "			detection should continue. Default is 120 seconds."
	echo ""
	echo "			Mode 1: require a trigger for each scan"  
	echo "			Mode 2: require a trigger to scan only when at least"  
	echo "			one owner is home. When all owners are gone,"
	echo "			scanning is periodic (behavior_preferences)"
	echo "  presence -V		print version"
}

# ----------------------------------------------------------------------------------------
# PROCESS OPTIONS (technique: https://stackoverflow.com/questions/192249/how-do-i-parse-command-line-arguments-in-bash)
# ----------------------------------------------------------------------------------------

OPTIND=1

# INITIALIZE OUR OWN VARIABLES:
debug=0
binary_only=0
changes_only=0
trigger_only_on_message=0
trigger_mode=0

while getopts "h?Vdbct:" opt; do
    case "$opt" in
    h|\?)
        show_help_text
        exit 0
        ;;
    V)  
		echo "$VERSION"
		exit 0
		;;
    d)  debug=1
		;;
    b)  binary_only=1
		;;
	c)  changes_only=1
		;;
	t)  	
	    trigger_mode=$OPTARG
      	trigger_only_on_message=1
		;;
    esac
done

#RESET OPTION INDEX
shift $((OPTIND-1))

#SHIFT IF NECESSARY
[ "$1" = "--" ] && shift

# ----------------------------------------------------------------------------------------
# DEBUG FUNCTION
# ----------------------------------------------------------------------------------------

debug_echo () {
	if [ "$debug" == "1" ]; then 
		(>&2 echo -e "${ORANGE}DEBUG MSG:	$1${NC}")
	fi 
}

# ----------------------------------------------------------------------------------------
# ERROR CHECKING 
# ----------------------------------------------------------------------------------------

#NAME SCAN TIMEOUT
if [[ "$name_scan_timeout" -lt 3 ]]; then 
	echo -e "${GREEN}presence $VERSION - ${RED}WARNING:"
	echo -e "Name scan timeout is relatively low at $(( name_scan_timeout > 0 ? name_scan_timeout : 0)). New bluetooth "
	echo -e "devices may take more time than this to be discovered.${NC}"
fi 

#NAME SCAN TIMEOUT
if [[ "$name_scan_timeout" -gt 5 ]]; then 
	echo -e "${GREEN}presence $VERSION - ${RED}WARNING:"
	echo -e "Name scan timeout is relatively high at $(( name_scan_timeout > 0 ? name_scan_timeout : 0)). Built-in"
	echo -e "timeout, by default, is around five to six seconds.${NC}"
fi 

#OWNER SCANS WHEN AWAY
if [[ "$delay_between_owner_scans_away" -lt 5 ]]; then 
	echo -e "${GREEN}presence $VERSION - ${RED}WARNING:$"
	echo -e "Delay between owner scans when away is relatively"
	echo -e "low at $(( delay_between_owner_scans_away > 0 ? delay_between_owner_scans_away : 0)). This may slow down the server because the BT hardware"
	echo -e "will be actively scanning more frequently. Consider increasing"
	echo -e "this value. The greater this value, the more time it will take"
	echo -e "to recognize when a device has arrived.${NC}"
fi 

#OWNER SCANS WHEN PRESENT
if [[ "$delay_between_owner_scans_present" -lt 20 ]]; then 
	echo -e "${GREEN}presence $VERSION - ${RED}WARNING:"
	echo -e "Delay between owner scans when present is relatively"
	echo -e "low at $(( delay_between_owner_scans_present > 0 ? delay_between_owner_scans_present : 0)). This may slow down the server because the BT hardware"
	echo -e "will be actively scanning more frequently. Consider increasing"
	echo -e "this value. The greater this value, the more time it will take"
	echo -e "to recognize that a devices has left.${NC}"
fi 

#VERIFICATION LOOP SIZE
if [[ "$verification_of_away_loop_size" -lt 5 ]]; then 
	echo -e "${GREEN}presence $VERSION - ${RED}WARNING:"
	echo -e "Verification loop (i.e., verification_of_away_loop_size) is relatively"
	echo -e "low at $(( verification_of_away_loop_size > 0 ? verification_of_away_loop_size : 0)). This can increase the risk of false exit events."
	echo -e "The greater this value, the lower the probability of false exit events.${NC}"
fi 

#VERIFICATION LOOP DELAY
if [[ "$verification_of_away_loop_delay" -lt 2 ]]; then 
	echo -e "${GREEN}presence $VERSION - ${RED}WARNING:"
	echo -e "Verification loop delay is relatively short or"
	echo -e "low at $verification_of_away_loop_delay. This can increase the risk of false exit events."
	echo -e "The greater this value, the lower the probability of "
	echo -e "false exit events.${NC}"
fi 

#BEACONS
if [[ "$beacon_scan_interval" -lt 5 ]] && [[ "$beacon_scan_enabled" == 1 ]]; then 
	echo -e "${GREEN}presence $VERSION - ${RED}WARNING:"
	echo -e "Beacon scan interval is relatively low at $(( beacon_scan_interval > 0 ? beacon_scan_interval : 0)). This reduces the changes"
	echo -e "that a beacon will be broadcasting when this script is listening."
	echo -e "The greater this value, the greater the liklihood that a present beacon"
	echo -e "will be recognized.${NC}"
fi 

# ----------------------------------------------------------------------------------------
# SCAN FOR GUEST DEVICES DURING OWNER DEVICE TIMEOUTS
# ----------------------------------------------------------------------------------------

scan_for_guests () {
	#TO DETERMINE CORRECT EXIT TIME FOR WHILE LOOP
	local STARTTIME=$(date +%s)

	#INIT END TIME
	local ENDTIME=0

	#THIS TIME
	local seen=()

	#PUBLISH?
	local ok_to_publish_guest=1

	#DELAY TYPE
	local delay_to_implement=$1

	#IF WE HAVE GUEST DEVICES TO SCAN FOR, THEN SCAN FOR THEM!
	if [ ! -z "$macaddress_guests" ]; then 

		#calculate 
		local DIFFERENCE=$((ENDTIME - STARTTIME))

		#START WHILE LOOP DURING OWNER SCANS; USING A WHILE LOOP HERE INSTEAD OF 
		#A FOR LOOP SO THAT WE CAN EXIT THE LOOP ON TIME WITHOUT MISSING
		#GUEST SCANS. FOR EXAMPLE, IF THE OWNER LOOP ONLY PERMITS 5 SECONDS TO SCAN, 
		#WE MIGHT ONLY BE ABLE TO SCAN ONE GUEST AT A TIME PER CALL OF 
		#THIS FUNCTION. 

		while [ $DIFFERENCE -lt $delay_to_implement ]
		do

			#CALCULATE REMAINDER OF DELAY
			local MAX_DELAY=$(( delay_to_implement - DIFFERENCE )) 

			#CACHE BLUETOOTH RESULTS 
			local name_scan_result_guest=""

			#OBTAIN INDIVIDUAL ADDRESS
			local current_guest_device_address="${macaddress_guests[$current_guest_index]}"

			#IF BLANK, PRESUME ERROR AND PROCEED TO BEGINNING OF GUEST ARRAY
			[ -z "$current_guest_device_address" ] && current_guest_index=0 && current_guest_device_address="${macaddress_guests[$current_guest_index]}"

			#CHECK IF WE'VE ALREADY SCANNED THIS DEVICE; THIS MEANS WE HAVE ITERATED 
			#OVER ALL GUEST DEVICES IN THIS INTER-OWNER DEVICE SCAN INTERVAL
			if [ "${seen[$current_guest_index]}" == "1" ]; then 

				##MAKE SURE THAT WE'RE NOT IMPLEMENTING A NEGATIVE DELAY
				MAX_DELAY=$(( MAX_DELAY > 0 ? MAX_DELAY : 0 ))

				#PRINT DELAY FOR DEBUGGING
				debug_echo "Appropriate Delay: $MAX_DELAY"

				#DELAY TO THE MAX VALUE
				sleep $MAX_DELAY 

				#RESET CURRENT GUEST INDEX TO ZERO
				current_guest_index=0

				#WE HAVE ALREADY BEEN NOTIFIED OF THIS GUEST DEVICE ALREADY IN THIS LOOP; TIME TO BREAK
				return
			fi

			#CORRECT THE GUEST INDEX
			if [ "$current_guest_index" -gt "$(( number_of_guests - 1 ))" ] ; then 
				current_guest_index=0
			fi

			#MARK AS SEEN
			seen[$current_guest_index]=1

			#MARK BEGINNING OF SCAN OPERATION
			local start_timer_guest=$(date +%s%N)

			#OBTAIN RESULTS AND APPEND EACH TO THE SAME
			local name_scan_result_guest=$(scan $current_guest_device_address)
			
			#MARK END OF SCAN OPERATION
			local end_time_guest=$(date +%s%N)
			
			#CALCULATE DIFFERENCE
			local duration_timer_guest=$(( (end_time_guest - start_timer_guest) / 1000000 )) 
			
			#THIS DEVICE NAME IS PRESENT
			if [ "$name_scan_result_guest" != "" ]; then
				#OK TO PUBLISH?
				[ "${guest_device_statuses[$current_guest_index]}" == '100' ] && [ "$changes_only" == 1 ] && ok_to_publish_guest=0

				#SET GUEST DEVICE STATUS
				guest_device_statuses[$current_guest_index]="100"

				#PUBLISH THE PRESENCE OF THE GUEST 
				[ "$ok_to_publish_guest" == "1" ] && publish "/guest/$mqtt_room/$current_guest_device_address" '100' "$name_scan_result_guest" "$duration_timer_guest"
			else
				#OK TO PUBLISH?
				[ "${guest_device_statuses[$current_guest_index]}" == '0' ] && [ "$changes_only" == 1 ] && ok_to_publish_guest=0

				#SET GUEST DEVICE STATUS
				guest_device_statuses[$current_guest_index]="0"

				[ "$ok_to_publish_guest" == "1" ] && publish "/guest/$mqtt_room/$current_guest_device_address" '0' "$name_scan_result_guest" "$duration_timer_guest"
			fi

			#ITERATE THE CURRENT GUEST THAT WE'RE LOOKING FOR
			current_guest_index=$((current_guest_index+1))

			#SET ENDTIME 
			ENDTIME=$(date +%s)

			#REFERSH DIFFERNCE
			DIFFERENCE=$((ENDTIME - STARTTIME)) 

		done

		### NEED TO FIND THE REMAINDER OF TIME NEEDED BETWEEN OWNER SCANS

		#SET ENDTIME 
		ENDTIME=$(date +%s)

		#REFERSH DIFFERNCE
		DIFFERENCE=$((ENDTIME - STARTTIME)) 


		#CALCULATE FINAL MAX DELAY
		local MAX_DELAY=$((delay_to_implement - DIFFERENCE)) 

		#LESS THAN ZERO? 
		MAX_DELAY=$(( MAX_DELAY > 0 ? MAX_DELAY : 0 ))

		#PRINT DELAY FOR DEBUGGING
		debug_echo "Remainder of delay before next owner scan: $MAX_DELAY"

		#SLEEP THE MAXIMUM DELAY 
		sleep $MAX_DELAY

	else
		#ERROR CORRECTIONS; NEED TO HAVE MINIMUM DELAY
		local MAX_DELAY=$(( delay_to_implement > 0 ? delay_to_implement : 5))

		#PRINT DELAY FOR DEBUGGING
		debug_echo "Remainder of delay before next owner scan: $MAX_DELAY"

		#DEFAULT SLEEP; NO GUEST DEVICES
		sleep $MAX_DELAY
    fi
}

# ----------------------------------------------------------------------------------------
# SCAN 
# ----------------------------------------------------------------------------------------

scan () {
	if [ ! -z "$1" ]; then 
		local result=$(timeout --signal SIGINT $name_scan_timeout hcitool -i hci0 name "$1" 2>&1 | grep -v 'not available' | grep -vE "hcitool|timeout|invalid|error" )
		debug_echo "Scan result: [$result]"
		echo "$result" 
	fi
}

# ----------------------------------------------------------------------------------------
# PUBLISH MESSAGE
# ----------------------------------------------------------------------------------------

publish () {
	if [ ! -z "$1" ]; then 

		#SET NAME FOR 'UNKONWN'
		local name="$3"

		#IF NO NAME, RETURN "UNKNOWN"
		if [ -z "$3" ]; then 
			name="Unknown"
		fi 

		#TIMESTAMP
		stamp=$(date "+%a %b %d %Y %H:%M:%S GMT%z (%Z)")

		#DEBUGGING 
		[ "$debug" == "1" ] && (>&2 echo -e "${PURPLE}$mqtt_topicpath$1 { confidence : $2, name : $name, scan_duration_ms: $4, timestamp : $stamp} ${NC}")

		#POST TO MQTT
		$mosquitto_pub_path -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath$1" -m "{\"confidence\":\"$2\",\"name\":\"$name\",\"scan_duration_ms\":\"$4\",\"timestamp\":\"$stamp\"}" -r 
	fi
}

# ----------------------------------------------------------------------------------------
# WORST CASE ESTIMATIONS 
# ----------------------------------------------------------------------------------------

#STARTUP MESSAGE
[ "$debug" == "1" ] && echo -e "${GREEN}presence $VERSION ${NC} - Started. Performance predictions based on current settings:"

#ALL OWNERS AT HOME 
[ "$debug" == "1" ] && echo -e "  > Est. to verify all ($number_of_owners) owners as 'away' from all 'home': $(( number_of_owners * (2 * verification_of_away_loop_size + verification_of_away_loop_delay * verification_of_away_loop_size) + (beacon_scan_enabled == 1 ? beacon_scan_interval : 0 ))) seconds to $(( delay_between_owner_scans_present + number_of_owners * name_scan_timeout * verification_of_away_loop_delay * verification_of_away_loop_size + (beacon_scan_enabled == 1 ? beacon_scan_interval : 0 ))) seconds."

#FUZZ FOR ONE SECOND PER OWNER THAT IS HOME, PLUS WORST CASE 
[ "$debug" == "1" ] && echo -e "  > Est. to verify one owner is 'away': $(( 2 * verification_of_away_loop_size + verification_of_away_loop_delay * verification_of_away_loop_size )) to $(( (beacon_scan_enabled == 1 ? beacon_scan_interval : 0 ) + delay_between_owner_scans_present + (number_of_owners - 1) + name_scan_timeout * verification_of_away_loop_delay * verification_of_away_loop_size )) seconds." 

#0.15 SECONDS IS EXPERIMENATALLY OBTAINED ON A RASPBERRY PI
[ "$debug" == "1" ] && echo -e "  > Est. to recognize one owner is 'home': 0.15 seconds to $(( (beacon_scan_enabled == 1 ? beacon_scan_interval : 0 ) + delay_between_owner_scans_away + (number_of_owners - 1) + name_scan_timeout )) seconds." 

# ----------------------------------------------------------------------------------------
# MAIN LOOP
# ----------------------------------------------------------------------------------------

beacon_devices=()			#STORES IDENFIERS THAT RECORD WHICH MACS ARE ASSOCIATED WITH BEACONS
device_statuses=()			#STORES STATUS FOR EACH BLUETOOTH DEVICES
guest_device_statuses=()	#STORES STATUS FOR EACH BLUETOOTH DEVICES
device_names=()				#STORES DEVICE NAMES FOR BOTH BEACONS AND BLUETOOTH DEVICES
one_owner_home=0 			#FLAG FOR AT LEAST ONE OWNER BEING HOME
trigger_stop_time=0 		#FLAG FOR TRIGGERING SCAN EVENTS OF PARTICULAR DURATION

# ----------------------------------------------------------------------------------------
# CHECK USER 
# ----------------------------------------------------------------------------------------

has_root_permission=1

if [[ $EUID -ne 0 ]] && [ "$beacon_scan_enabled" == 1 ] ; then
  	echo -e "${GREEN}presence $VERSION ${RED}WARNING:  ${NC}Beacon detection requires root; man hcitool for detail."
  	echo -e "Any BTLE Beacon MAC addresses in the 'owner_devices' configuration" 
  	echo -e "file will be treated as standard bluetooth devices and will likely"
  	echo -e "always return a confidence of 0. Performance may be degraded for "
  	echo -e "other devices.${NC}" 
   	has_root_permission=0
fi

# ----------------------------------------------------------------------------------------
# START THE OPERATIONAL LOOP
# ----------------------------------------------------------------------------------------

#POST TO MQTT
$mosquitto_pub_path -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath$1" -m "{\"status\":\"online\"}" --will-retain  --will-topic "$mqtt_topicpath$1" --will-payload "{\"status\":\"offline\"}"

#MAIN LOOP
while true; do 

	#--------------------------------------
	#	OPEN SCANNING FOR BLUETOOTH LE DEVICES
	#--------------------------------------
	if [ "$has_root_permission" == 1 ] && [ "$beacon_scan_enabled" == 1 ] ; then 
		beacons_raw=$(sudo timeout --signal SIGINT $beacon_scan_interval hcitool lescan --duplicates 2>&1)
		beacons_filtered=$(echo "$beacons_raw" | grep -Ei "([0-9a-f]{2}:){5}[0-9a-f]{2}" | sort -u)

		#CHECK INTERFACE HEALTH, RESTORE IF NECESSARY
		if [ "$beacons_raw" == "Set scan parameters failed: Input/output error" ];then
			echo -e "${GREEN}presence $VERSION ${RED}WARNING:  ${NC}Bluetooth interface went down. Restoring now...${NC}"
			sudo hciconfig hci0 down
			sleep 1
			sudo hciconfig hci0 up
		fi
	else

		#IF WE DO NOT HAVE BEACON DETECTION ENABLED, SET THE ARRAY TO BLANK
		beacons_filtered=""

	fi 

	#RESET AT LEAST ONE DEVICE HOME
	one_owner_home=0

	#--------------------------------------
	#	UPDATE STATUS OF ALL USERS WITH NAME QUERY
	#--------------------------------------
	for ((index=0; index<${#macaddress_owners[*]}; index++));
	do
		#CLEAR PER-LOOP VARIABLES
		name_scan_result=""
		name_scan_result_verify=""
		ok_to_publish=1

		#OBTAIN INDIVIDUAL ADDRESS
		current_device_address="${macaddress_owners[$index]}"

		#WAS FOUND? 
		is_beacon=$(echo "$beacons_filtered" | grep -ic $current_device_address)

		#CHECK FOR ADDITIONAL BLANK LINES IN ADDRESS FILE
		if [ -z "$current_device_address" ]; then 
			continue
		fi

		#TEST IF CURRENT DEVICE WAS FOUND ON A BEACON SCAN

		if [ "$is_beacon" == 0 ]; then  
			### NON BEACON ###

			#MARK BEGINNING OF SCAN OPERATION
			start_timer=$(date +%s%N)

			#OBTAIN RESULTS AND APPEND EACH TO THE SAME
			name_scan_result=$(scan $current_device_address)
			
			#MARK END OF SCAN OPERATION
			end_time=$(date +%s%N)
			
			#CALCULATE DIFFERENCE
			duration_timer=$(( (end_time - start_timer) / 1000000 )) 

		else
			### BEACON ###

			#SET THE NAME AS THE DEVICE ADDRES
			name_scan_result="$current_device_address"

			#SET SCAN DURATION TO TIMEOUT
			duration_timer="$((beacon_scan_interval * 1000))"

			#SET BEACON ARRAY SO THAT WE CAN IGNORE IF BEACON LEAVES
			beacon_devices[$index]=1

		fi 

		#THIS DEVICE NAME IS PRESENT
		if [ "$name_scan_result" != "" ]; then

			#STATE IS SAME && ONLY REPORT CHANGES THEN DISABLE PUBLICATION
			[ "${device_statuses[$index]}" == '100' ] && [ "$changes_only" == 1 ] && ok_to_publish=0

			#NO DUPLICATE MESSAGES
			[ "$ok_to_publish" == "1" ] && publish "/owner/$mqtt_room/$current_device_address" '100' "$name_scan_result" "$duration_timer"

			#USER STATUS			
			device_statuses[$index]="100"

			#SET AT LEAST ONE DEVICE HOME
			one_owner_home=1

			#SET NAME ARRAY
			device_names[$index]="$name_scan_result"

		else

			#HANDLE BEACONS FIRST
			was_beacon="${beacon_devices[$index]}"

			#IF THIS WAS PREVIOUSLY MARKED AS A BEACON, SKIP NAME SCANNING
			if [ "$was_beacon" == '1' ]; then
				
				#STATE IS SAME && ONLY REPORT CHANGES THEN DISABLE PUBLICATION
				[ "${device_statuses[$index]}" == '0' ] && [ "$changes_only" == 1 ] && ok_to_publish=0

				#NO DUPLICATE MESSAGES
				[ "$ok_to_publish" == "1" ] && publish "/owner/$mqtt_room/$current_device_address" '0' "$name_scan_result" "$duration_timer"

				#USER STATUS			
				device_statuses[$index]="0"

				#SET NAME ARRAY
				device_names[$index]="$name_scan_result"

				#NEXT MAC ADDRESS
				continue
			fi 

			#USER STATUS			
			status="${device_statuses[$index]}"

			if [ -z "$status" ]; then 
				status="0"
			fi 

			#BY DEFAULT, SET REPETITION TO PREFERENCE
			repetitions="$verification_of_away_loop_size"

			#IF WE ARE JUST STARTING OR, ALTERNATIVELY, WE HAVE RECORDED THE STATUS 
			#OF NOT HOME ALREADY, ONLY SCAN ONE MORE TIME. 
			if [ "$status" == 0 ];then 
				repetitions=1
			fi 

			#SHOULD VERIFY ABSENSE
			for repetition in $(seq 1 $repetitions); 
			do 
				#RESET OK TO PUBLISH
				ok_to_publish=1

				#VERIFICATION LOOP DELAY
				sleep "$verification_of_away_loop_delay"

				#GET PERCENTAGE
				percentage=$(($status * ( $repetitions - $repetition) / $repetitions))

				#ONLY SCAN IF OUR STATUS IS NOT ALREADY 0
				if [ "$status" != 0 ];then 

					#MARK BEGINNING OF SCAN OPERATION
					start_timer=$(date +%s%N)

					#PERFORM SCAN
					name_scan_result_verify=$(scan $current_device_address)

					#MARK END OF SCAN OPERATION
					end_time=$(date +%s%N)
					
					#CALCULATE DIFFERENCE
					duration_timer=$(( (end_time - start_timer) / 1000000 )) 

					#CHECK SCAN 
					if [ "$name_scan_result_verify" != "" ]; then						

						#STATE IS SAME && ONLY REPORT CHANGES THEN DISABLE PUBLICATION
						[ "${device_statuses[$index]}" == '100' ] && [ "$changes_only" == 1 ] && ok_to_publish=0

						#PUBLISH
						[ "$ok_to_publish" == "1" ] && publish "/owner/$mqtt_room/$current_device_address" '100' "$name_scan_result_verify" "$duration_timer"

						#SET AT LEAST ONE DEVICE HOME
						one_owner_home=1

						#WE KNOW THAT WE MUST HAVE BEEN AT A PREVIOUSLY-SEEN USER STATUS
						device_statuses[$index]="100"

						#UPDATE NAME ARRAY
						device_names[$index]="$name_scan_result_verify"

						#MUST BREAK CONFIDENCE SCANNING LOOP; 100' ISCOVERED
						break
					fi
				fi 

				#RETREIVE LAST-KNOWN NAME FOR PUBLICATION; SINCE WE OBVIOUSLY DIDN'T RECEIVE A NAME SCAN RESULT 
				expectedName="${device_names[$index]}"

				if [ "$percentage" == "0" ]; then 
					#STATE IS SAME && ONLY REPORT CHANGES THEN DISABLE PUBLICATION
					[ "${device_statuses[$index]}" == '0' ] && [ "$changes_only" == 1 ] && ok_to_publish=0

					#PRINT ZERO CONFIDENCE OF A DEVICE AT HOME
					[ "$ok_to_publish" == "1" ] && publish "/owner/$mqtt_room/$current_device_address" "0" "$expectedName" "$duration_timer"
				else 
					#STATE IS SAME && ONLY REPORT CHANGES THEN DISABLE PUBLICATION
					[ "${device_statuses[$index]}" == '$percentage' ] && [ "$changes_only" == 1 ] && ok_to_publish=0

					#IF BINARY ONLY, THEN DISABLE PUBLICATION
					[ "$binary_only" == "1" ] && ok_to_publish=0

					#REPORT CONFIDENCE DROP
					[ "$ok_to_publish" == "1" ] && publish "/owner/$mqtt_room/$current_device_address" "$percentage" "$expectedName" "$duration_timer"
				fi 

				#UPDATE STATUS ARRAY
				device_statuses[$index]="$percentage" 
			done
		fi
	done

	#CHECK STATUS ARRAY FOR ANY DEVICE MARKED AS 'HOME'
	wait_duration=0

	#DETERMINE APPROPRIATE DELAY
	if [ "$one_owner_home" == 1 ]; then 
		[ "$debug" == "1" ] && (>&2 debug_echo "Scanning for $number_of_guests guest devices between owner scans (at least one device is present).")
		 wait_duration=$delay_between_owner_scans_present
	else
		[ "$debug" == "1" ] && (>&2 debug_echo "Scanning for $number_of_guests guest devices between owner scans (no owner device is present).")
		wait_duration=$delay_between_owner_scans_away
	fi

	#TRIGGER ONLY MODE
	if [ "$trigger_only_on_message" == 1 ]; then
		#CHECK IF TRIGGER MODE 1 OR TRIGGER MODE 2

		if [ "$trigger_mode" == 2 ] && [ "$one_owner_home" == 0 ]; then 
			#SCAN MODE EXPLANATION
			debug_echo "Periodic scanning enabled. All ($number_of_owners) owner devices away."

			#TRIGGER SCAN FOR GUESTS WITH DEFAULT SETTINGS
			scan_for_guests	$wait_duration
		else
			#TRIGGER SCAN FOR GUESTS WITH SUFFICIENT DELAY FOR ALL GUESTS; SEVEN SECONDS IS 
			#TWO SECONDS BEYOND IN-BUILT TIMEOUT OF HCITOOL AT 5 SECONDS; ALLOWS FOR SCAN
			#OF ALL GUEST DEVICES BEFORE NEXT MESSAGE
			time_now=$(date +%s)

			#CALCULATE TIME DELTA; 
			time_delta_to_trigger_stop=$(( time_now - trigger_stop_time ))

			#IF VALUE IS POSITIVE, THEN TIME HAS ELAPSED
			if [[ "$time_delta_to_trigger_stop" -gt 0 ]]; then 
				#make sure that all guests have been scanned 
				scan_for_guests	$(( number_of_guests * 7 ))

				debug_echo "Most recent trigger duration has timed out. Awaiting next trigger."

				#AFTER ALL DEVICES ARE SCANNED (POTENTIALLY NOT ALL GUEST DEVICES)
				while read instruction; do

					#ESTABLISH DURATION OF LOOP DURING WHICH SCANNING  
					scan_duration=$(echo "$instruction" | grep -oiE "duration\"? {0,}: {0,}\"?[0-9]{1,}" | sed 's/[^0-9]//g' )

					#DEFAULT SCANNING FOR AT LEAST TWO MINTUES
					[ -z "$scan_duration" ] && scan_duration=120

					#REFRESH CURRENT TIME
					time_now=$(date +%s)

					#CALCULATED END TIME FOR COMPARISON
					trigger_stop_time=$(( time_now + scan_duration ))

					#DESYNCHRONIZATION STEP SO THAT ALL DEVICES ARE NOT LIKELY TO BE SCANNING AT ONCE.
					desync_delay=$[ ( $RANDOM % 6 )  + 1 ]s
					debug_echo "Received instruction to scan for $scan_duration seconds. Scanning..."
					sleep "$desync_delay"
					break

				done < <($mosquitto_sub_path -v -h "$mqtt_address" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath/scan") 
			else 
				#TRIGGER SCAN FOR GUESTS WITH DEFAULT SETTINGS
				scan_for_guests	$wait_duration
			fi 
		fi 
	else 
		#TRIGGER SCAN FOR GUESTS WITH DEFAULT SETTINGS
		scan_for_guests	$wait_duration
	fi
done

