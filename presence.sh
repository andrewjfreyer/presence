
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
VERSION=0.5.1

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
[ -z "$mosquitto_pub_path" ] && echo "Required package 'mosquitto_pub' not found. Please install." && exit 1
[ -z "$mosquitto_sub_path" ] && echo "Required package 'mosquitto_sub' not found. Please install." && exit 1

# ----------------------------------------------------------------------------------------
# LOAD PREFERENCES
# ----------------------------------------------------------------------------------------

#OR LOAD FROM A SOURCE FILE
if [ ! -f "$base_directory/behavior_preferences" ]; then 
	echo -e "${GREEN}presence $VERSION ${RED}WARNING:  ${NC}Behavior preferences are not defined:${NC}"
	echo -e "/behavior_preferences. Creating file and setting default values.${NC}"
  	echo -e "" 

  	#DEFAULT VALUES
  	echo "
#DELAY BETWEEN SCANS OF OWNER DEVICES WHEN AWAY FROM HOME
delay_between_owner_scans_away=6

#DELAY BETWEEN SCANS OF OWNER DEVICES WHEN HOME 
delay_between_owner_scans_present=30

#HOW MANY VERIFICATIONS ARE REQUIRED TO DETERMINE A DEVICE IS AWAY 
verification_of_away_loop_size=6

#HOW LONG TO DELAY BETWEEN VERIFICATIONS THAT A DEVICE IS AWAY 
verification_of_away_loop_delay=3

#PREFERRED HCI DEVICE
hci_device='hci0'" > "$base_directory/behavior_preferences"
fi 

# ----------------------------------------------------------------------------------------
# VARIABLE DEFINITIONS 
# ----------------------------------------------------------------------------------------

#SET PREFERENCES FROM FILE
DELAY_CONFIG="$base_directory/behavior_preferences" ; [ -f $DELAY_CONFIG ] && source $DELAY_CONFIG

#LOAD DEFAULT VALUES IF NOT PRESENT
[ -z "$hci_device" ] && hci_device='hci0' 
[ -z "$name_scan_timeout" ] && name_scan_timeout=5
[ -z "$delay_between_owner_scans_away" ] && delay_between_owner_scans_away=6 
[ -z "$delay_between_owner_scans_present" ] && delay_between_owner_scans_present=30
[ -z "$verification_of_away_loop_size" ] && verification_of_away_loop_size=6
[ -z "$verification_of_away_loop_delay" ] && verification_of_away_loop_delay=3

#LOAD PREFERENCES IF PRESENT
MQTT_CONFIG=$base_directory/mqtt_preferences ; [ -f $MQTT_CONFIG ] && source $MQTT_CONFIG
[ ! -f "$MQTT_CONFIG" ] && echo "warning: please configure mqtt preferences file. exiting." && echo "" > "$MQTT_CONFIG" && exit 1

#FILL ADDRESS ARRAY WITH SUPPORT FOR COMMENTS
[ ! -f "$base_directory/owner_devices" ] && "" > "$base_directory/owner_devices"
macaddress_owners=($(cat "$base_directory/owner_devices" | grep -oiE "([0-9a-f]{2}:){5}[0-9a-f]{2}" ))
[ -z "$macaddress_owners" ] && echo "warning: no owner devices are specified. exiting." && exit 1


#NUMBER OF CLIENTS THAT ARE MONITORED
number_of_owners=$((${#macaddress_owners[@]}))

# ----------------------------------------------------------------------------------------
# HELP TEXT
# ----------------------------------------------------------------------------------------

show_help_text() {
	echo "Usage:"
	echo "  presence -h 	show usage information"
	echo "  presence -d 	print debug messages and mqtt messages"
	echo "  presence -b 	binary output only; either 100 or 0 confidence"
	echo "  presence -c 	only post confidence status changes for owners/guests"
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
	*)	echo "warning: unknown or depreciated option: $opt"
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
# SCAN 
# ----------------------------------------------------------------------------------------

scan () {
	if [ ! -z "$1" ]; then 
		local result=$(hcitool -i $hci_device name "$1" 2>&1 | grep -v 'not available' | grep -vE "hcitool|timeout|invalid|error" )
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
		if [ -z ${mqtt_capath+x} ]; then
			$mosquitto_pub_path -h "$mqtt_address" -p "${mqtt_port:=1883}" -u "$mqtt_user" -P "$mqtt_password" -t "$mqtt_topicpath$1" -m "{\"confidence\":\"$2\",\"name\":\"$name\",\"scan_duration_ms\":\"$4\",\"timestamp\":\"$stamp\"}"
		else
			$mosquitto_pub_path -h "$mqtt_address" -p "${mqtt_port:=1883}" -u "$mqtt_user" -P "$mqtt_password" --capath "$mqtt_capath" -t "$mqtt_topicpath$1" -m "{\"confidence\":\"$2\",\"name\":\"$name\",\"scan_duration_ms\":\"$4\",\"timestamp\":\"$stamp\"}"
		fi
	fi
}

# ----------------------------------------------------------------------------------------
# MAIN LOOP
# ----------------------------------------------------------------------------------------

device_statuses=()			#STORES STATUS FOR EACH BLUETOOTH DEVICES
device_names=()				#STORES DEVICE NAMES FOR BOTH BEACONS AND BLUETOOTH DEVICES
one_owner_home=0 			#FLAG FOR AT LEAST ONE OWNER BEING HOME

# ----------------------------------------------------------------------------------------
# START THE OPERATIONAL LOOP
# ----------------------------------------------------------------------------------------

#MAIN LOOP
while true; do 

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

		#CHECK FOR ADDITIONAL BLANK LINES IN ADDRESS FILE
		if [ -z "$current_device_address" ]; then 
			continue
		fi

		#MARK BEGINNING OF SCAN OPERATION
		start_timer=$(date +%s%N)

		#OBTAIN RESULTS AND APPEND EACH TO THE SAME
		name_scan_result=$(scan $current_device_address)
		
		#MARK END OF SCAN OPERATION
		end_time=$(date +%s%N)
		
		#CALCULATE DIFFERENCE
		duration_timer=$(( (end_time - start_timer) / 1000000 )) 

		#THIS DEVICE NAME IS PRESENT
		if [ "$name_scan_result" != "" ]; then

			#STATE IS SAME && ONLY REPORT CHANGES THEN DISABLE PUBLICATION
			[ "${device_statuses[$index]}" == '100' ] && [ "$changes_only" == 1 ] && ok_to_publish=0

			#NO DUPLICATE MESSAGES
			[ "$ok_to_publish" == "1" ] && publish "/$mqtt_room/$current_device_address" '100' "$name_scan_result" "$duration_timer"

			#USER STATUS			
			device_statuses[$index]="100"

			#SET AT LEAST ONE DEVICE HOME
			one_owner_home=1

			#SET NAME ARRAY
			device_names[$index]="$name_scan_result"

		else

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
						[ "$ok_to_publish" == "1" ] && publish "/$mqtt_room/$current_device_address" '100' "$name_scan_result_verify" "$duration_timer"

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
					[ "$ok_to_publish" == "1" ] && publish "/$mqtt_room/$current_device_address" "0" "$expectedName" "$duration_timer"
				else 
					#STATE IS SAME && ONLY REPORT CHANGES THEN DISABLE PUBLICATION
					[ "${device_statuses[$index]}" == '$percentage' ] && [ "$changes_only" == 1 ] && ok_to_publish=0

					#IF BINARY ONLY, THEN DISABLE PUBLICATION
					[ "$binary_only" == "1" ] && ok_to_publish=0

					#REPORT CONFIDENCE DROP
					[ "$ok_to_publish" == "1" ] && publish "/$mqtt_room/$current_device_address" "$percentage" "$expectedName" "$duration_timer"
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
		 wait_duration=$delay_between_owner_scans_present
	else
		wait_duration=$delay_between_owner_scans_away
	fi

	sleep "$wait_duration"
done
