#!/bin/bash -u

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
    if [ $# -lt 1 ]
    then
        local stat=1
    else
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
    fi
    return $stat
}

# Check which if the OS in this machine is of a certain type
function machine_is
{
  OS=`uname -v`
  [[ ! "${OS//$1/}" == "$OS" ]] && return 0 || return 1
}

DIRNOW="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Defines

USERAGENT="Bash No-IP Updater/0.7 mowerm@gmail.com"

#Defaults

DEBUG=false
CONFIGFILE="$DIRNOW/config"
CRONTAB=false

while [[ $# -gt 0 ]]
do
    case $1 in
    -d|-debug|--debug)
        DEBUG=true
    ;;
    -c|-config|-config)
        shift
        CONFIGFILE="$1"
    ;;
    -c=*|-config=*|--config=*)
        CONFIGFILE="${1#*=}"
    ;;
    -crontab|--crontab)
        CRONTAB=true
    ;;
    *)
        echo "WARNING: ignored input argument '$1'"
    ;;
    esac
    shift
done

$DEBUG && {
    echo DIRNOW=$DIRNOW
    echo USERAGENT=$USERAGENT
    echo CONFIGFILE=$CONFIGFILE
}

if [ -e $CONFIGFILE ]; then
    source $CONFIGFILE
else
    echo "ERROR: Config file not found: $CONFIGFILE"
    exit 1
fi

$DEBUG && {
    echo USERNAME=$USERNAME
    echo PASSWORD=$PASSWORD
}

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
   echo "ERROR: USERNAME or PASSWORD has not been set in the config file."
   exit 1
fi

machine_is Darwin && {
   USERNAME=$(echo -ne $USERNAME | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
   PASSWORD=$(echo -ne $PASSWORD | xxd -plain | tr -d '\n' | sed 's/\(..\)/%\1/g')
} || {
   USERNAME=$(echo -ne $USERNAME | od -An -t x1 | sed 's/[[:space:]]//g' | sed 's/\(..\)/%\1/g')
   PASSWORD=$(echo -ne $PASSWORD | od -An -t x1 | sed 's/[[:space:]]//g' | tr -d '\n' | sed 's/\(..\)/%\1/g')
}

#use encoded username/passwords if they are set
[ -z ${USERNAME+x} ] && USERNAME=$USERNAME_ENC
[ -z ${PASSWORD+x} ] && PASSWORD=$PASSWORD_ENC

$DEBUG && {
    echo USERNAME=$USERNAME
    echo PASSWORD=$PASSWORD
}

if ! [[ "$FORCEUPDATEFREQ" =~ ^[0-9]+$ ]] ; then
   echo "ERROR: FORCEUPDATEFREQ has not been set correctly in the config file"
   exit 1
fi

if [ ! -d "$LOGDIR" ]; then
    mkdir -p "$LOGDIR"
    if [ $? -ne 0 ]; then
        echo "ERROR: Log directory could not be created or accessed."
        exit 1
    fi
fi

LOGFILE="${LOGDIR%/}/noip.log"
IPFILE="${LOGDIR%/}/last_ip"
if [ ! -e $LOGFILE ] || [ ! -e $IPFILE ]; then
    touch $LOGFILE
    touch $IPFILE
    if [ $? -ne 0 ]; then
        echo "ERROR: Log files could not be created. Is the log directory writable?"
        exit 1
    fi
elif [ ! -w $LOGFILE ] || [ ! -w $IPFILE ]; then
    echo "ERROR: Log files not writable."
    exit 1
fi
STOREDIP=$(cat $IPFILE)

# Program

# Select brew coreutils unix g-prefixed programs in Darwin
if machine_is Darwin
then
  DATE=gdate
else
  DATE=date
fi

if machine_is Darwin
then
  TAC=gtac
else
  TAC=tac
fi

$DEBUG && {
    echo DATE=$DATE
    echo TAC=$TAC
}


# Check log for last successful ip change to No-IP and set FUPD flag if an
# update is necessary.  (Note: 'nochg' return code is not enough for No-IP to be
# satisfied; must be 'good' return code)
FUPD=false
NOW=$($DATE '+%s')
$DEBUG && {
    echo NOW=$NOW
    echo FUPD=$FUPD
}
if [ $FORCEUPDATEFREQ -eq 0 ]; then
    FUPD=false
elif [ -e $LOGFILE ] && $TAC $LOGFILE | grep -q -m1 '(good)'; then
    GOODLINE=$($TAC $LOGFILE | grep -m1 '(good)')
    LASTGC=$([[ $GOODLINE =~ \[(.*?)\] ]] && echo "${BASH_REMATCH[1]}")
    LASTCONTACT=$($DATE -d "$LASTGC" '+%s')
    if [ `expr $NOW - $LASTCONTACT` -gt $FORCEUPDATEFREQ ]; then
        FUPD=true
    fi
    $DEBUG && {
        echo FUPD=$FUPD
        echo GOODLINE=$GOODLINE
        echo LASTGC=$LASTGC
        echo LASTCONTACT=$LASTCONTACT
    }
else
    FUPD=true
fi
$DEBUG && echo FUPD=$FUPD


COUNTER=1
NEWIP=0
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
            $DEBUG && echo LOGLINE=$LOGLINE
            echo $LOGLINE >> $LOGFILE
            exit 1
            ;;
    esac
    $DEBUG && {
        echo COUNTER=$COUNTER
        echo NEWIP=$NEWIP
    }
done

$DEBUG && echo CURL_COM: curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST&myip=$NEWIP"
if [ $FUPD == true ]; then
    curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST&myip=127.0.0.1" &> /dev/null
    sleep 5
    RESULT=$(curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST&myip=$NEWIP")
elif [ "$NEWIP" != "$STOREDIP" ]; then
    RESULT=$(curl -s -k --user-agent "$USERAGENT" "https://$USERNAME:$PASSWORD@dynupdate.no-ip.com/nic/update?hostname=$HOST&myip=$NEWIP")
else
    RESULT="nochglocal"
fi

$DEBUG && echo RESULT=$RESULT

LOGDATE="[$($DATE +'%Y-%m-%d %H:%M:%S')]"
$DEBUG && echo LOGDATE=$LOGDATE
SRESULT=$(echo $RESULT | awk '{ print $1 }')
$DEBUG && echo SRESULT=$SRESULT
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

$DEBUG && echo LOGLINE=$LOGLINE


echo $NEWIP > $IPFILE
echo $LOGLINE >> $LOGFILE

machine_is Darwin && ! $CRONTAB && {
  echo "Hit Ctr-C to stop monitoring the DNS update (current IP is $NEWIP)"
  dns-sd -q $HOST
}

exit 0

