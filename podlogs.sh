#!/bin/bash
#
#
Version="1.0"
# v1.0 - June 24th 2020 - Eric Raidelet
# Initial Release
#
Version="1.1"
# v1.1 - June 25th 2020 - Eric Raidelet
# RENAMED the tool to podlogs.sh
# Enhancement: Does write out logs from all Pods
# Enhancement: Added option -t and -a for faster results
Version="1.2"
# v1.2 - June 29h 2020 - Eric Raidelet
# Bugfix: The default loglevel ERR|WARN did not get correctly recognized a regex
# Bugfix: The final output for $Values included a trailing \n which got removed




# This variable defines the default timespan how old log entries can be.
# The format is in hours. You can change it.

DefaultLogTimeSpan="24" # hours
DefaultNameSpace="default" # If no namespace is given use this one
DefaultLastLines="50" # If nothing specified then limit the log output to this value 
DefaultLogLevel="'ERR\|WARN'" # If not set use this loglevel. Can be ERR WARN ERRWARN or ALL (or something else of course if you want)

# console colors

color_white="\033[1;37m"
color_orange="\033[0;33m"
color_red="\033[0;31m"
color_green="\033[0;32m"
color_nc="\033[0m"


# No root, no cookies
if [ "$(id -u)" != "0" ]; then echo -e "\nThis script must run ${color_white}as uid=0 (root)${color_nc}\n"; exit 1; fi


usage()
{
	echo ""
	echo -e "${color_orange}podlogs.sh v$Version - Eric Raidelet${color_nc}"
	echo "--------------------------------------------------------------------"
	echo "This tool is an extension to checkpods.sh to gather"
	echo "Pod logs. However, it can also be used standalone."
	echo "--------------------------------------------------------------------"
	echo ""
	echo "podlogs.sh mypod1 mypod2"
	echo ""
	echo -e "${color_orange}Usage:${color_nc}"
	echo "-p = Pod name, you can enter mutliple hosts."
	echo "     <PodName> Single Pod name"
	echo "     <\"PodName1 PodName2 PodName3\"> Multiple Pod names"                         
	echo "     Note: Multiple Pod must should be space delimited and"
	echo "     surounded by quotes \"pod1 pod2 pod2\""
	echo "-c = Container name to use"
	echo "     <ContainerName>"
	echo "-n = Pod namespace. Default is \"default\""
	echo "-P = Pod Prefix. This will first run checkpods.sh to get a list"
	echo "     of Pods matching your Prefix (it will grep). This has"
	echo "     priority over -p -c options."
	echo "-l = Log level to include. This can be either"
	echo "     <ERR|WARN|ERRWARN|ALL>"
	echo "-a = Age of the log entries in hours"
	echo "-t = Tail functoin, how many of last events/lines to show."
	echo "     <t> Default of t is 50"
	echo "     Note: Filtering for ERR will show last -a errors and does"
	echo "           not only apply to the last 50 log entries overall."
	echo "-q = Quiet mode, suppress some informational output"
	echo ""
	echo -e "${color_orange}Example:${color_nc}"
	echo "--------------------------------------------------------------------"
	echo "podlogs.sh -l ERR -t 10 -p mypod1 ---> Shows the last 10 Error entries for pod mypod1"
	echo ""
	
	

	exit 1
}


# some variable defaults

PodName=""
PodList=""
PodPrefix=""
ContainerName=""
LogLevel=""
LastLinesGrep=""
Silent="false"
SinceHours=""


while getopts "p:c:l:t:n:qa:e:P:" OPTION
do
	
	case $OPTION in
		p)
		PodList=$OPTARG
		;;
		c)
		ContainerName=$OPTARG
		;;
		l)
		LogLevel=$OPTARG
		;;
		n)
		NameSpace=$OPTARG
		;;
		t)
		LastLinesGrep=$OPTARG
		;;
		q)
		Silent="true"
		;;
		a)
		SinceHours=$OPTARG
		;;
		e)
		ExcludeArgs=$OPTARG
		;;
		P)
		PodPrefix=$OPTARG
		;;
		*)
		usage
		exit n | 0
		;;
	esac
done

# Get the last commandline argument as the PodList.
# Multiple Pods can be added but must be surrounded by quotes: "pod1 pod2 pod3"

shift $(($OPTIND - 1))
if [ $# -gt 0 ]; then PodList=$*; fi


# Splitting our Pods in an array to loop through later

if [ "$PodPrefix" != "" ] # The user wants a grep from checkpods.sh output, reset the PodList variable
then
	if [ ! -e "/usr/bin/checkpods.sh" ]
	then
		echo "/usr/bin/checkpods.sh is required to use this option, but not found."
		exit 1
	fi
	PodList=$(checkpods.sh -c p -s p | grep $PodPrefix)
	read -a PodArr <<< $PodList
else
	origIFS=$IFS
	IFS=" "
	read -a PodArr <<< $PodList
	IFS=$origIFS
fi



# If we still have no Pods to show logs for, show usage and skip
if [ "$PodList" = "" ]; then usage; fi


# setting no or nonsense input to defaults
if [ "$NameSpace" = "" ]; then NameSpace="$DefaultNameSpace"; fi
if [ "$LastLinesGrep" = "" ]; then LastLinesGrep="$DefaultLastLines"; fi
if [ "$SinceHours" = "" ]; then SinceHours="$DefaultLogTimeSpan"; fi

# check if the LastLinesGrep is actually a number
number='^[0-9]+$'
if ! [[ $LastLinesGrep =~ $number ]]
then 
	if [ "$Silent" != "true" ]; then echo -e "${color_red}Invalid paramater for -n , setting to default 50${color_nc}"; LastLinesGrep="50"; fi
fi

case $LogLevel in
	"ERR")
	LogGrep="'ERR'"
	;;
	"WARN")
	LogGrep="'WARN'"
	;;
	"ERRWARN")
	LogGrep="'ERR\|WARN'"
	;;
	"ALL")
	LogGrep="ALL"
	;;
	*)
	if [ "$Silent" != "true" ]; then echo "Loglevel set to default $DefaultLogLevel"; fi
	LogLevel="$DefaultLogLevel"
	LogGrep="$DefaultLogLevel"
	;;
esac




# If excludes were given we split them in an array for further usage
origIFS=$IFS
IFS=","
read -a ExcludeArr <<< $ExcludeArgs
IFS=$origIFS




# Finally, lets loop through and get the logs

for ThisPod in "${PodArr[@]}"
do

	# Grab a fresh set of values for the current Pod
	
	cmd="kubectl get pods --no-headers=true -n $NameSpace --field-selector=metadata.name=$ThisPod -o=custom-columns=NAME:.metadata.name,CONTAINERS:.spec.containers[*].name"
	Values=$(eval $cmd)
	if [ "$Values" = "" ]
	then
		echo "--------------------------------------------------------------------------------------"
		echo -e "${color_orange}No Pod found with name <$ThisPod> in namespace <$NameSpace>${color_nc}"
		echo "--------------------------------------------------------------------------------------"
		continue
	fi
	
	# Some Pods have more than 1 Container, get them
	
	if [ "$ContainerName" = "" ]
	then
		Containers=$(echo $Values | awk '{print $2}')
	else
		Containers=$ContainerName
	fi
	origIFS=$IFS
	IFS=","
	read -a ContainerArr <<< "$Containers"
	IFS=$origIFS
	
	# Yeah, looks dirty, but did the trick. Construct some grep string here
	
	GrepCmd=""
	if [ "$LogGrep" != "ALL" ]
	then 
		GrepCmd=" | grep ${LogGrep}"
	fi

	ExcludeGrep=""
	echo $ExcludeArgs
	echo ${ExcludeArr[*]}
	if [ "$ExcludeArgs" != "" ]
	then
		for Arg in ${ExcludeArr[*]}
		do
			ExcludeGrep+="${Arg}|"
		done
		len=${#ExcludeGrep} 
		len=$(($len-1))
		ExcludeGrep=${ExcludeGrep:0:$len}
		ExcludeGrep="| grep -v '$ExcludeGrep'"
	fi
	
	# Loop through the Containers and get the logs
	
	for ThisContainer in "${ContainerArr[@]}"
	do
		if [ "$Silent" != "true" ]
		then
			echo "--------------------------------------------------------------------------------------"
			echo "Pod:       $ThisPod (Available Containers: $Containers)"
			echo "Container: $ThisContainer"
			echo "Arguments: Log age within $SinceHours hours, matching $LogGrep, last $LastLinesGrep lines"
			echo "--------------------------------------------------------------------------------------"
		fi

		
		cmd="kubectl logs -n $NameSpace $ThisPod -c $ThisContainer --timestamps=true --since=${SinceHours}h ${GrepCmd} ${ExcludeGrep} | tail -n $LastLinesGrep"
		#echo $cmd
		Values=$(eval $cmd)
		if [ "$Values" = "" ]
		then
			echo -e "${color_green}No entries are marching the criterias${color_nc}"
		else
			if [ "$LogGrep" = "ERR" ] || [ "$LogGrep" = "'ERR\|WARN'" ]; then echo -e "${color_red}Found matching entries${color_nc}"; fi
			echo "$Values"
			echo ""
		fi

	done
	
done
