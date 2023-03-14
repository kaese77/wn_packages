#!/bin/sh

. /lib/functions.sh
. /usr/share/libubox/jshn.sh

OWM_API_VER="1.0"

printhelp() {
	printf "owm.sh - Tool for registering routers at openwifimap.net\n
Options:
\t--help|-h:\tprint this text

\t--dry-run:\tcheck if owm.lua is working (does not paste any data).
\t\t\tWith this option you can check for errors in your
\t\t\tconfiguration and test the transmission of data to
\t\t\tthe map.\n\n
If invoked without any options, this tool will try to register
your node at the community-map and print the servers response.
To work correctly, this tool will need at least the geo-location
of the node (check correct execution with --dry-run).

To override the server used by this script, set freifunk.community.owm_api.
"
}

# save positional argument, as it would get overwritten otherwise.
CMD_1="$1"
if [ -n "$CMD_1" ] && [ "$CMD_1" != "--dry-run" ]; then
	[ "$CMD_1" != "-h" ] && [ "$CMD_1" != "--help" ] && printf "Unrecognized argument %s.\n\n" "$CMD_1"
	printhelp
	exit 1
fi


######################
#                    #
#  Collect OWM-Data  #
#                    #
######################

# Draft for OLSRv2-Links currently not used
olsr2_links() {
	json_select $2
	json_get_var localIP link_bindto
	json_get_var remoteIP neighbor_originator
	remotehost="$(nslookup $remoteIP | grep name | sed -e 's/.*name = \(.*\)/\1/' -e 's/\..*//')"".olsr"
	# Maybe add some stuff here.
	json_get_var linkQuality domain_metric_out_raw
	#json_get_var linkQuality domain_metric_in_raw
	json_get_var ifName "if"
	json_select ..
	olsr2links="$olsr2links$localIP $remoteIP $remotehost $linkQuality $ifName;"
}

olsr4_links() {
	json_select $2
	json_get_var localIP localIP
	json_get_var remoteIP remoteIP
	remotehost="$(nslookup $remoteIP | grep name | sed -e 's/.*name = \(.*\)/\1/'  -e 's/mid[0-9]\.//')"
	json_get_var linkQuality linkQuality
	json_get_var linkCost linkCost
	json_get_var olsrInterface olsrInterface
	json_get_var ifName ifName
	json_select ..
	olsr4links="$olsr4links$localIP $remoteIP $remotehost $linkQuality $linkCost $ifName;"
}

olsr6_links() {
	json_select $2
	json_get_var localIP localIP
	json_get_var remoteIP remoteIP
	remotehost="$(nslookup $remoteIP | grep name | sed -e 's/.*name = \(.*\)/\1/' -e 's/mid[0-9]\.//')"
	json_get_var linkQuality linkQuality
	json_get_var linkCost linkCost
	json_get_var olsrInterface olsrInterface
	json_get_var ifName ifName
	json_select ..
	olsr6links="$olsr6links$localIP $remoteIP $remotehost $linkQuality $linkCost $ifName;"
}

# This section is relevant for hopglass statistics feature (isUplink/isHotspot)
OLSRCONFIG=$(printf "/config" | nc 127.0.0.1 9090)

# collect nodes location
uci_load system
longitude="$(uci_get system @system[-1] longitude)"
latitude="$(uci_get system @system[-1] latitude)"

#
#   set another type if lat/lon is not set.
#
type="node"
if [ -z "$latitude" ] || [ -z "$longitude" ]; then
	printf "latitude/longitude is not set.\nFYI ...\n"
	type="node_no_loc"	
fi


# collect data on OLSR-links
json_load "$(printf "/nhdpinfo" json link | nc ::1 2009 2>/dev/null)" 2>/dev/null
olsr2links=""
if json_is_a link array;then
	json_for_each_item olsr2_links link
fi
json_cleanup
json_load "$( printf "/links" | nc 127.0.0.1 9090 2>/dev/null)" 2>/dev/null
#json_get_var timeSinceStartup timeSinceStartup
olsr4links=""
if json_is_a links array;then
	json_for_each_item olsr4_links links
fi
json_cleanup
json_load "$( printf "/links" | nc ::1 9090 2>/dev/null)" 2>/dev/null
#json_get_var timeSinceStartup timeSinceStartup
olsr6links=""
if json_is_a links array;then
	json_for_each_item olsr6_links links
fi
json_cleanup

# collect board info
json_load "$(ubus call system board)"
json_get_var model model
json_get_var hostname hostname
json_get_var system system
json_select release
json_get_var revision revision
json_get_var distribution distribution
json_get_var version version
json_get_var description description
json_select ..
json_load "$(ubus call system info)"
json_get_var uptime uptime
json_get_values loads load

# if file freifunk_release is available, override version and revision
if [ -f /etc/freifunk_release ]; then
	. /etc/freifunk_release
	distribution="$FREIFUNK_DISTRIB_ID"
	version="$FREIFUNK_RELEASE"
	revision="$FREIFUNK_REVISION"
fi

if [ -f /etc/weimarnetz_release ]; then
	. /etc/weimarnetz_release
	pkgdesc="$WEIMARNETZ_PACKAGES_DESCRIPTION"
	pkgbranch="$WEIMARNETZ_PACKAGES_BRANCH"
	pkgrev="$WEIMARNETZ_PACKAGES_REV"
fi

# Get System Data
sysload=$(cat /proc/loadavg)
load1=$(echo "$sysload" | cut -d' ' -f1)
load5=$(echo "$sysload" | cut -d' ' -f2)
load15=$(echo "$sysload" | cut -d' ' -f3)
json_load "$(ubus call system info)"
json_select memory
json_get_var freeram free
json_get_var sharedram shared
json_get_var bufferedram buffered
json_get_var totalram total
json_select ..
json_select swap
json_get_var totalswap total
json_get_var freeswap free
json_select ..
procs=$(ps|wc -l)

# Date when the firmware was build.
kernelString=$(cat /proc/version)
buildDate=$(echo $kernelString | cut -d'#' -f2 | cut -c 3-)
kernelVersion=$(echo $kernelString | cut -d' ' -f3)

# contact information
uci_load freifunk
name="$(uci_get freifunk contact name)"
nick="$(uci_get freifunk contact nickname)"
showMail="$(uci_get ffwizard settings email2owm)"
if [ "$showMail" -eq "1" ]; then
	mail="$(uci_get freifunk contact mail)"
	phone="$(uci_get freifunk contact phone)"
else
	mail="Email hidden"
fi
homepage="$(uci_get freifunk contact homepage)" # whitespace-separated, with single quotes, if string contains whitspace
note="$(uci_get freifunk contact note)"

# community info
ssid="$(uci_get freifunk community ssid)"
mesh_network="$(uci_get freifunk community mesh_network)"
uci_owm_api="$(uci_get freifunk community owm_api)"
owm_api_host=$(echo $uci_owm_api | sed -e 's/http\(s\)\{0,1\}:\/\///g')
com_name="$(uci_get freifunk community name)"
com_homepage="$(uci_get freifunk community homepage)"
com_longitude="$(uci_get freifunk community longitude)"
com_latitude="$(uci_get freifunk community latitude)"
com_ssid_scheme="$(uci_get freifunk community ssid_scheme)"
com_splash_network="$(uci_get freifunk community splash_network)"
com_splash_prefix="$(uci_get freifunk community splash_prefix)"
uci_load ffwizard
nodenumber="$(uci_get ffwizard settings nodenumber)"
json_load "$(ubus call registrator status)"
json_get_var regmessage message
json_get_var regnodenumber nodenumber
json_get_var regcode code
json_get_var regsuccess success

###########################
#                         #
#  Construct JSON-string  #
#                         #
###########################

json_init
json_add_object freifunk

	json_add_object contact
		if [ -n "$name" ]; then json_add_string name "$name"; fi
		if [ -n "$mail" ]; then json_add_string mail "$mail"; fi
		if [ -n "$nick" ]; then json_add_string nickname "$nick"; fi
		if [ -n "$phone" ]; then json_add_string phone "$phone"; fi
		if [ -n "$homepage" ]; then json_add_string homepage "$homepage"; fi # was array of homepages
		if [ -n "$note" ]; then json_add_string note "$note"; fi
	json_close_object

	json_add_object community
		json_add_string ssid "$ssid"
		json_add_string mesh_network "$mesh_network"
		json_add_string owm_api "$uci_owm_api"
		json_add_string name "$com_name"
		json_add_string homepage "$com_homepage"
		json_add_string longitude "$com_longitude"
		json_add_string latitude "$com_latitude"
		json_add_string ssid_scheme "$com_ssid_scheme"
		json_add_string splash_network "$com_splash_network"
		json_add_int splash_prefix $com_splash_prefix
	json_close_object
json_close_object

# script infos
json_add_string type "$type"
json_add_string script "owm.sh"
json_add_double api_rev $OWM_API_VER

json_add_object system
	json_add_array sysinfo
		json_add_string "" "$system"
		json_add_string "" "$model"
		json_add_object ""
		        json_add_int freeram "$freeram"
		        json_add_int sharedram "$sharedram"
		        json_add_int bufferram "$bufferedram"
		        json_add_int uptime "$uptime" 
		        json_add_int totalswap "$totalswap" 
		        json_add_int procs "$procs"
		        json_add_int totalram "$totalram"
		        json_add_array loads
		        	json_add_double $load1
		        	json_add_double $load5
		        	json_add_double $load15
		        json_close_array
		        json_add_int freeswap "$freeswap"
		json_close_object
	json_close_array
	json_add_array uptime
		json_add_int "" $uptime
	json_close_array
	json_add_array loadavg
		json_add_double $load1
		json_add_double $load5
		json_add_double $load15
	json_close_array
json_close_object

# OLSR-Config
# That string gets substituted by the olsrd-config-string afterwards
json_add_object olsr
send_olsrd_config="$(uci_get ffwizard owm send_olsrd_config '1')"
if [ "$send_olsrd_config" = "1" ]; then
	json_add_string ipv4Config '$OLSRCONFIG'
fi
json_close_object

json_add_array links
	IFSORIG="$IFS"
	IFS=';'
	for i in ${olsr2links} ; do
		IFS="$IFSORIG"
		set -- $i
		json_add_object
		json_add_string sourceAddr6 "$1"
		json_add_string destAddr6 "$2"
		json_add_string id "$3"
		json_add_double quality "$4"
		json_add_double linkCost "$5"
		json_close_object
		IFS=';'
	done
	for i in ${olsr4links} ; do
		IFS="$IFSORIG"
		IFS=" "
		set -- $i
		json_add_object
		json_add_string sourceAddr4 "$1"
		json_add_string destAddr4 "$2"
		json_add_string id "$3"
		json_add_double quality "$4"
		json_add_double linkCost "$5"
		json_add_string interface "$6"
		json_close_object
		IFS=';'
	done
	for i in ${olsr6links} ; do
		IFS="$IFSORIG"
		set -- $i
		json_add_object
		json_add_string sourceAddr6 "$1"
		json_add_string destAddr6 "$2"
		json_add_string id "$3"
		json_add_double quality "$4"
		json_add_double linkCost "$5"
		json_add_string interface "$6"
		json_close_object
		IFS=';'
	done
	IFS="$IFSORIG"
json_close_array

json_add_array interfaces
json_close_array

# General node info
# Bug in add_double function. Mostly it adds unwanted digits
# but they disappear, if we send stuff to the server
if [ -n "$latitude" ] && [ -n "$longitude" ]; then
	json_add_double latitude $latitude
	json_add_double longitude $longitude
fi
json_add_string hostname "$hostname"
json_add_int updateInterval 3600
json_add_string hardware "$system"
json_add_object firmware
	json_add_string name "$distribution $version"
	json_add_string distname "$distribution $version"
	json_add_string distversion "$version"
	json_add_string revision "$revision"
	json_add_string description "$description"
	json_add_string kernelVersion "$kernelVersion"
	json_add_string kernelBuildDate "$buildDate"
	json_add_string packageDescription "$pkgdesc"
	json_add_string packageBranch "$pkgbranch"
	json_add_string packageRevision "$pkgrev"
json_close_object
json_add_object weimarnetz
	json_add_string "nodenumber" "$nodenumber"
	json_add_object registratorstatus
		json_add_string message "$regmessage"
		json_add_int nodenumber $regnodenumber
		json_add_boolean success $regsuccess
		json_add_int code "$regcode"
	json_close_object
json_close_object

JSON_STRING=$(json_dump)
#insert json-string from OLSR and repair wrong syntax at string-borders (shell-quotes...)
JSON_STRING=$(echo "$JSON_STRING" | sed -e 's|$OLSRCONFIG|'"$OLSRCONFIG"'|; s|"{|{|; s|}"|}|' )

# just print data to stdout, if we have test-run.
if [ "$CMD_1" = "--dry-run" ]; then
	printf "%s\n" "$JSON_STRING"
	exit 0
fi


################################
#                              #
#   Send data to openwifimap   #
#                              #
################################

#echo $JSON_STRING
# get message lenght for request
LEN=$(echo $JSON_STRING | wc -m) 

MSG="\
PUT /update_node/$hostname.olsr HTTP/1.1\r
User-Agent: nc/0.0.1\r
Host: $owm_api_host\r
Content-type: application/json\r
Content-length: $LEN\r
\r
$JSON_STRING\r\n"

printf "$MSG" | nc $owm_api_host 80
printf "\n\n"
