#!/bin/bash
# iBeacon Scan by Radius Networks
#
# Edited by Andrew J Freyer
# version 20180209

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
          if [[ $2 == "-b" ]]; then
	    echo "$UUID $MAJOR $MINOR $POWER"
          else
    	    echo "UUID: $UUID MAJOR: $MAJOR MINOR: $MINOR POWER: $POWER"
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
  sudo hcitool lescan --duplicates 1>/dev/null &
  if [ "$(pidof hcitool)" ]; then
    sudo hcidump --raw | ./$0 parse $1
  fi
fi
