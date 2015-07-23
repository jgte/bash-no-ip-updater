#!/bin/bash

# Copyright (C) 2013 Matt Mower
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Functions

# IP Validator
# http://www.linuxjournal.com/content/validating-ip-address-bash-script
function valid_ip() {
    local  ip=$1
    local  stat=1

    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

# Check which if the OS in this machine is of a certain type
function machine_is
{
  OS=`uname -v`
  [[ ! "${OS//$1/}" == "$OS" ]] && return 0 || return 1
}

DIRNOW=$( cd "$( dirname "$0" )" && pwd )

# Defines

USERAGENT="Bash No-IP Updater/0.7 mowerm@gmail.com"
CONFIGFILE="$DIRNOW/config"

if [ -e $CONFIGFILE ]; then
    source $CONFIGFILE
else
    echo "Config file not found."
    exit 1
fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
   echo "USERNAME or PASSWORD has not been set in the config file."
   exit 1
fi

machine_is Darwin && {
   USERNAME=$(echo -ne $USERNAME | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
   PASSWORD=$(echo -ne $PASSWORD | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
} || {
   USERNAME=$(echo -ne $USERNAME | od -An -t x1 | sed 's/[[:space:]]//g' | sed 's/\(..\)/%\1/g')
   PASSWORD=$(echo -ne $PASSWORD | od -An -t x1 | sed 's/[[:space:]]//g' | tr -d '\n' | sed 's/\(..\)/%\1/g')
}

if ! [[ "$FORCEUPDATEFREQ" =~ ^[0-9]+$ ]] ; then
   echo "FORCEUPDATEFREQ has not been set correctly in the config file"
   exit 1
fi

if [ ! -d "$LOGDIR" ]; then
    mkdir -p "$LOGDIR"
    if [ $? -ne 0 ]; then
        echo "Log directory could not be created or accessed."
        exit 1
    fi
fi

LOGFILE="${LOGDIR%/}/noip.log"
IPFILE="${LOGDIR%/}/last_ip"
if [ ! -e $LOGFILE ] || [ ! -e $IPFILE ]; then
    touch $LOGFILE
    touch $IPFILE
    if [ $? -ne 0 ]; then
        echo "Log files could not be created. Is the log directory writable?"
        exit 1
    fi
elif [ ! -w $LOGFILE ] || [ ! -w $IPFILE ]; then
    echo "Log files not writable."
    exit 1
fi
STOREDIP=$(cat $IPFILE)

# Program

# Select brew coreutils unix g-prefixed programs in Darwin
machine_is Darwin && DATE=gdate || DATE=date
machine_is Darwin && TAC=gtac   || DATE=tac

# Check log for last successful ip change to No-IP and set FUPD flag if an
# update is necessary.  (Note: 'nochg' return code is not enough for No-IP to be
# satisfied; must be 'good' return code)
FUPD=false
NOW=$($DATE '+%s')
if [ $FORCEUPDATEFREQ -eq 0 ]; then
    FUPD=false
elif [ -e $LOGFILE ] && $TAC $LOGFILE | grep -q -m1 '(good)'; then
    GOODLINE=$($TAC $LOGFILE | grep -m1 '(good)')
    LASTGC=$([[ $GOODLINE =~ \[(.*?)\] ]] && echo "${BASH_REMATCH[1]}")
    LASTCONTACT=$($DATE -d "$LASTGC" '+%s')
    if [ `expr $NOW - $LASTCONTACT` -gt $FORCEUPDATEFREQ ]; then
        FUPD=true
    fi
else
    FUPD=true
fi

COUNTER=1
while ! valid_ip $NEWIP; do
    case $COUNTER in
        1)
            NEWIP=$(curl -s http://icanhazip.com | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
            let COUNTER++
            ;;
        2)
            NEWIP=$(curl -s http://checkip.dyndns.org | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
            let COUNTER++
            ;;
        3)
            NEWIP=$(curl -s http://wtfismyip.com/text | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
            let COUNTER++
            ;;
        4)
            NEWIP=$(curl -s http://www.networksecuritytoolkit.org/nst/tools/ip.php | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}')
            let COUNTER++
            ;;
        *)
            LOGLINE="[$($DATE +'%Y-%m-%d %H:%M:%S')] Could not find current IP"
            echo $LOGLINE >> $LOGFILE
            exit 1
            ;;
    esac
done

if [ $FUPD == true ]; then
    curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST&myip=127.0.0.1" &> /dev/null
    sleep 5
    RESULT=$(curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST&myip=$NEWIP")
elif [ "$NEWIP" != "$STOREDIP" ]; then
    RESULT=$(curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST&myip=$NEWIP")
else
    RESULT="nochglocal"
fi

LOGDATE="[$($DATE +'%Y-%m-%d %H:%M:%S')]"
SRESULT=$(echo $RESULT | awk '{ print $1 }')
case $SRESULT in
    "good")
        LOGLINE="$LOGDATE (good) DNS hostname(s) successfully updated to $NEWIP."
        ;;
    "nochg")
        LOGLINE="$LOGDATE (nochg) IP address is current: $NEWIP; no update performed."
        ;;
    "nochglocal")
        LOGLINE="$LOGDATE (nochglocal) IP address is current: $NEWIP; no update performed."
        ;;
    "nohost")
        LOGLINE="$LOGDATE (nohost) Hostname supplied does not exist under specified account. Revise config file."
        ;;
    "badauth")
        LOGLINE="$LOGDATE (badauth) Invalid username password combination."
        ;;
    "badagent")
        LOGLINE="$LOGDATE (badagent) Client disabled - No-IP is no longer allowing requests from this update script."
        ;;
    "!donator")
        LOGLINE="$LOGDATE (!donator) An update request was sent including a feature that is not available."
        ;;
    "abuse")
        LOGLINE="$LOGDATE (abuse) Username is blocked due to abuse."
        ;;
    "911")
        LOGLINE="$LOGDATE (911) A fatal error on our side such as a database outage. Retry the update in no sooner than 30 minutes."
        ;;
    *)
        LOGLINE="$LOGDATE (error) Could not understand the response from No-IP ($RESULT). The DNS update server may be down."
        ;;
esac

echo $NEWIP > $IPFILE
echo $LOGLINE >> $LOGFILE

machine_is Darwin && [[ "${@/-crontab/}" == "$@" ]] && {
  echo "Hit Ctr-C to stop monitoring the DNS update (current IP is $NEWIP)"
  dns-sd -q $HOST
}

exit 0

