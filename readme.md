Bash No-IP Updater
------------------

A bash script to update the IP address of a no-ip.com hostname.

__Prerequisites__

1.  curl

__Usage__

1.  Configure the script with the correct username, password, hostname, IP cache file, and log file
2.  Make it executable (`chmod +x`)
3.  Run it (`./noipupdater.sh`)

__Automation__

Include the script in your cron file (`crontab -e`):

Run script once each day at 5:30am:
`30 5 * * * /path/to/noipupdater.sh`

Run the script every fifteen minutes:
`*/15 * * * * /path/to/noipupdater.sh`

Note: If the cron job doesn't execute correctly, try these suggestions:

1.  Add this line to your crontab: `SHELL=/bin/bash`
2.  Remove the `.sh` extension

Forked from the [Simple Bash No-IP Updater by AntonioCS](https://github.com/AntonioCS/no-ip.com-bash-updater)

2013 © Matt Mower

My goals with this fork is to be able to use this script on my Android tablet
with just little extra additionals:
    - Busybox from Stericson
    - curl from http://curl.haxx.se/download.html (Linux - Android)
    - bash from http://pub.mzet.net/bash
Maybe other improvements.
