#!/bin/bash
# IBM Confidential
#
# OCO Source Materials
# (C) Copyright IBM Corp. 2017
#
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
#
#########################################################################################
#
# File Name:health_check.sh
#
# Author: ADYANTHA T S , REYMOND PEO
# Author contact: adyantts@in.ibm.com , reymondpeo.nevis@in.ibm.com
# Reviewers: Madhu Sudhan , Vinatha Chaturvedi
# Description: This script can be used to generate "health check report" for n number of servers 
#		- can be used for LINUX/AIX
#		- can be executed for a site with multiple customers ( eg. RTP site & WHR,WH1 and WH2 customers)
#		- can be executed for customers across multiple sites ( eg. Z4G customer in all sites)
#		- can be used to get details of servers irrespective of site/customers by inputting file containing hostnames
#		- can be used to get details of all parameters or only few (custom). User will be prompted to choose parameters (screenshot attached below)
#		- can be used to execute a custom command (eg. uname -a) and get the output in csv/xls report.
#
# Usage: 
#	bash health_check.sh
#	-P [Platform - LINUX/AIX] Mandatory 
#	-T [Health Check Type - FULL for all parameters/CUSTOM to choose any] Mandatory 
#	-S [Site Code] Optional 
#	-C [Customer codes - comma separated ] Optional 
#	-I [servers_file containing hostnames] Optional 
# 	-h help
#
# ###############################################################################################
### If the script is terminated in between with Ctrl-C, Prepare the report with servers processed till that point
trap 'echo -e "Exiting now..\nPreparing the Report and Stopping tunnels";finalize $platform $$;exit' 2
bold=`tput bold`
normal=`tput sgr0`
blue='\e[34m'
green='\e[0;32m'
red='\e[31m'
### Usage ###
USAGE="${bold}Usage: \n$0\n -P [Platform - LINUX/AIX] Mandatory \n -T [Health Check Type - FULL for all parameters/CUSTOM to choose any] Mandatory \n -S [Site Codes - comma separated - ALL for all sites] Optional \n -C [Customer codes - comma separated - ALL for all customers of given site] Optional \n -I [servers_file containing hostnames] Optional \n -h help${normal}"
while getopts "P:S:C:T:I:h" opt; do
    case $opt in
        h)
            echo -e "$USAGE"
            exit 0
            ;;
        P)
            platform=${OPTARG} 
            ;;
        S)
            site_codes=${OPTARG}
            ;;
        C)
            customer_codes=${OPTARG}
            ;;
        T)
            rep_type=${OPTARG}
            ;;
        I)
            INP_FILE=${OPTARG}
            ;;
    esac
done
##### Validate Inputs
echo -en "${bold}Validating Inputs ..${normal}"
if [[ -z $platform || -z $rep_type ]]
then
	echo -e "$USAGE";
	exit 0
fi
if [[ -z $site_codes && -z $customer_codes && -z $INP_FILE ]];then 
	echo -e "${red}Either Site Code / Customer Codes / Servers file with Hostnames is mandatory${normal}\n$USAGE";
	exit 0;
fi
if [[ ! -z $INP_FILE && ! -s $INP_FILE ]];then
	echo -e "${red}$INP_FILE is not a file or empty${normal}"
	exit 0
fi

if [[ ! ${platform^^} =~ LINUX|AIX ]]
then
	echo "${red}Invalid Platform - Should be LINUX/AIX${normal}"
	exit 0
fi

if [[ ! ${rep_type^^} =~ FULL|CUSTOM ]]
then
	echo "${red}Invalid Type - Should be FULL/CUSTOM${normal}"
	exit 0
fi
echo -e "${bold}\rValidating Inputs ..done${normal}"

### Get the directory where script is kept for further processing ###
BASEDIR=$(dirname $(readlink -f $0 ))
cd ${BASEDIR}

## Read configuration file
if [[ -f health_check.cfg ]]
then
	. health_check.cfg
else
	echo "health_check.cfg configuration file not present. Exiting .."
	exit 1
fi

## Inherit the generic functions
if [[ -f generic_functions ]]
then
	. generic_functions
else
	echo "generic_functions file not present. Exiting .."
	exit 1
fi

DATE=$(date +"%d-%b-%Y_%I-%M%p_%Z")

### Check for SASGUI
ps -ef|grep -w "/usr/bin/sasgui" | grep -v grep 1>>/dev/null 2>>/dev/null
if [[ $? -eq 0 ]]
then
	echo "SASGUI is running!!!. Please close and execute again"
	exit 0
fi

##### Prepare commands based on type of healthcheck
if [[ -f ${platform,,}_params ]]
then
	. ${platform,,}_params
else
	echo "${platform,,}_params file not present. Exiting .."
	exit 1
fi
if [[ ${rep_type^^} == "FULL" ]]
then
	output=${all_params}
else
	zenity_cmd="zenity --width=800 --height=800 --list --text \"Choose the parameters\" --checklist --column \"Options\" --column \"Host details\" "
	zenity_input=`echo -e "${param_names}"| while read line1; do echo "FALSE \"$line1\""; done | tr '\n' ' '`
	output=$(eval ${zenity_cmd} ${zenity_input})
	output=$(echo $output|tr ' ' '_')
	if [[ -z ${output} ]];then 
		echo -e "No option selected!! Exiting..";
		exit;
	fi
	if [[ "${output}" =~ "All_parameters" ]];then
		[[ "$output" =~ "Custom_Command" ]] && output="${all_params}|Custom_Command" || output="${all_params}"
	fi
	if [[ "$output" =~ "Custom_Command" ]];then
        	cmd_Custom_Command=`zenity  --title "Custom command" --entry --text "Enter the custom command"`
	        [[ $cmd_Custom_Command =~ "shutdown" || $cmd_Custom_Command =~ "reboot" || $cmd_Custom_Command =~ "init" || $cmd_Custom_Command =~ ^rm ]] && echo -e "${red}Not allowed to execute $cmd_Custom_Command command through this script.${normal}" && exit 1
        	cmd_Custom_Command='$('${cmd_Custom_Command}')'
	fi
fi
for i in `echo $output | tr '|' ' '`;do header="${header},\"$(echo $i | tr '_' ' ')\"";eval cmd='$'"cmd_${i}";cmds="$cmds,\\\"${cmd}\\\"";done
cmds=`echo "$cmds"| sed 's/^,//g'`
cmds="echo \"$cmds\""
## Get Servers details
echo -e "${bold}Getting Servers details ..${normal}"
servers_file="tunnel_connect_servers.txt"	
if [[ ! -z $INP_FILE ]];then
	get_host_details $INP_FILE
else
	extract_hosts	
fi
echo -e "${green}${bold}Getting Servers details ..done${normal}"
### Output Report Name
## FORMAT: <TYPE>_HEALTH_CHECK_REPORT_<PLATFORM>_<SITE_CODE>_<CUSTOMERID/MUTLIPLECUSTOMER/ALLCUSTOMERS>_<dd-Mon-YY_HH-MMam/pm_timezone>.<csv/xls>
if [[ ! -z ${site_codes} ]]
then
	if [[ ! -z ${customer_codes} ]];then
		no_cust=$(echo ${customer_codes} | awk -F ',' '{print NF}')
		[[ ${no_cust} -le 2 ]] && OUTPUT_REPORT="${rep_type^^}_HEALTH_CHECK_REPORT_${platform^^}_$(echo ${site_codes^^} | tr ',' '_')_$(echo ${customer_codes^^} | tr ',' '_')_${DATE}.csv" || OUTPUT_REPORT="${rep_type^^}_HEALTH_CHECK_REPORT_${platform^^}_$(echo ${site_codes^^} | tr ',' '_')_MULTIPLECUSTOMERS_${DATE}.csv"
	else
		OUTPUT_REPORT="${rep_type^^}_HEALTH_CHECK_REPORT_${platform^^}_$(echo ${site_codes^^} | tr ',' '_')_ALLCUSTOMERS_${DATE}.csv"
	fi
else
	OUTPUT_REPORT="${rep_type^^}_HEALTH_CHECK_REPORT_${platform^^}_${DATE}.csv"
fi
##Backup previous report if there are any (both csv and xls reports) 
if [[ -f "$(echo ${OUTPUT_REPORT} | cut -d '.' -f1).csv" ]]; 
then 
	gen_time=$( ls -l "$(echo ${OUTPUT_REPORT} | cut -d '.' -f1).csv" | awk '{print $8}')
	mv "$(echo ${OUTPUT_REPORT} | cut -d '.' -f1).csv" $(echo ${OUTPUT_REPORT}|cut -d '.' -f1)_${gen_time}.csv;
fi
if [[ -f "$(echo ${OUTPUT_REPORT} | cut -d '.' -f1).xls" ]]; 
then 
	gen_time=$( ls -l "$(echo ${OUTPUT_REPORT} | cut -d '.' -f1).xls" | awk '{print $8}')
	mv "$(echo ${OUTPUT_REPORT} | cut -d '.' -f1).xls" $(echo ${OUTPUT_REPORT}|cut -d '.' -f1)_${gen_time}.xls;
fi

#speed=`(time -p wget http://ehngsa.ibm.com/projects/o/osengde/OS_ENG/01_public/07_tecsec/Tools/Socks/sas_cfg.xml -O ~/.sasgui/myconfig.xml) 2>&1|grep ^\`date +"%Y"\` |awk '{print $3}'| cut -d'(' -f2|cut -d. -f1`
wget http://ehngsa.ibm.com/projects/o/osengde/OS_ENG/01_public/07_tecsec/Tools/Socks/sas_cfg.xml -O ~/.sasgui/myconfig.xml >/dev/null 2>&1
speed=50
sleep_con_time=10
if [ $speed -ge 50 ]; then
	sleep_con_time=10
elif [ $speed -lt 50 ] && [ $speed -gt 30 ]; then
	sleep_con_time=20
else
	sleep_con_time=30
fi

### Initialize Parameters
number=0
_end=$(wc -l ${servers_file}|awk '{print $1}')
tot_wait_time=0
declare -A flag
declare -A pid_ip_pair
pid=""
ip_chn_ids=""
### Assign default values if not configured in health_check.cfg
[[ -z $threads ]] && threads=100
[[ -z $time_out ]] && time_out=180
[[ -z $sleep_time ]] && time_out=180
### Sort the servers file based on Customer-DataCenter combination for easy processing
sort -k1 -k2 ${servers_file} > ${servers_file}_tmp
mv ${servers_file}_tmp ${servers_file}

### Split the servers file based on threads specified in config file
split -l ${threads} ${servers_file} split_$$_

### Close any tunnels if running
stop_tunnel

### Take a backup of known hosts file. This is needed in next steps to handle servers with same IPs
cp -p ~/.ssh/known_hosts ~/.ssh/known_hosts_bkp

for split_file in `ls split_$$_*`
do
	
	while read CUSTOMER DC IP host_name SITE
        do
                if [[ ${flag["${CUSTOMER,,}-${DC,,}"]} == "" ]];then
			>~/.ssh/known_hosts
	                ip_chn_id=$RANDOM
			add_connection ${CUSTOMER} ${DC} ${IP} ${ip_chn_id} 
                        ret_code=$?
                        if [[ ${ret_code} -eq 1 ]];then ProgressBar $((number++)) ${_end};echo -e "${SITE},${CUSTOMER},${IP},${host_name},Tunnel details not found" >> HealthCheck_$$_dtls_ntavl.csv;continue;
                        elif [[ ${ret_code} -eq 2 ]];then
                                for proc_id in $pid
                                do
                                        while kill -0 ${proc_id} >/dev/null 2>&1; do
                                                sleep ${sleep_time}
                                                tot_wait_time=$(( ${tot_wait_time} + ${sleep_time} ))
                                                if [[ ${time_out} -eq ${tot_wait_time} ]] && [[ $(ps -ef | grep ${proc_id} |grep -v grep) ]] ;then
							for id in $pid
							do
								kill -0 ${id} >/dev/null 2>&1 
								if [[ $? -eq 0 ]]; then
                                                        	kill -9 ${id}
                                                        	echo "${pid_ip_pair["${id}"]},Server took too long to get details.Aborted" >> HealthCheck_$$_term.csv 
								fi
							done	                                                        
							tot_wait_time=0
							break
                                                fi
                                        done
                                done
                                stop_tunnel ${ip_chn_ids}
                                #Reset all values
                                flag=()
                                >networks.txt
                                pid=""
                                ip_chn_ids=""
                                pid_ip_pair=()
                                add_connection ${CUSTOMER} ${DC} ${IP} ${ip_chn_id} 
                                if [[ $? -eq 1 ]];then ProgressBar $((number++)) ${_end};echo -e "${SITE},${CUSTOMER},${IP},${host_name},Tunnel details not found" >> HealthCheck_$$_dtls_ntavl.csv;continue;fi
                        fi
                        flag+=(["${CUSTOMER,,}-${DC,,}"]="yes")
                        ip_chn_ids="${ip_chn_ids} ${ip_chn_id}"
                        get_${platform,,}_details ${SITE} ${CUSTOMER} ${DC} $IP $$ ${host_name} &
                        pid="$pid $!"
                        pid_ip_pair+=(["$!"]="${SITE},${CUSTOMER},${IP},${host_name}")
                else
                        get_${platform,,}_details ${SITE} ${CUSTOMER} ${DC} $IP $$ ${host_name} &
                        pid="$pid $!"
                        pid_ip_pair+=(["$!"]="${SITE},${CUSTOMER},${IP},${host_name}")
                fi
		ProgressBar $((number++)) ${_end}
        done < ${split_file}
	for proc_id in $pid
        do
                while kill -0 ${proc_id} >/dev/null 2>&1; do
                        sleep ${sleep_time}
                        tot_wait_time=$(( ${tot_wait_time} + ${sleep_time} ))
                        if [[ ${time_out} -eq ${tot_wait_time} ]] && [[ $(ps -ef | grep ${proc_id} |grep -v grep) ]] ;then
				for id in $pid
                                do
                                  kill -0 ${id} >/dev/null 2>&1
                                  if [[ $? -eq 0 ]]; then
                                   kill -9 ${id}
                                   echo "${pid_ip_pair["${id}"]},Server took too long to get details.Aborted" >> HealthCheck_$$_term.csv
                                  fi
                                done
				tot_wait_time=0
                                break
                        fi

                done
        done
done
ProgressBar $((number++)) ${_end}
echo

### Prepare report ###
finalize $platform $$
### Prepare xls file with summary sheet added
chk_pkg=$(perldoc -l "Text::CSV" "Spreadsheet::WriteExcel" 2>&1)
if [[ ! "${chk_pkg}" =~ "No documentation" ]];then 
	prepare_summary
	OUTPUT_REPORT="$(echo ${OUTPUT_REPORT} | cut -d '.' -f1).xls"
else
	echo -e "${blue}${bold}Skipping preparation of summary details in the report ..${normal}"
	echo -e "${blue}Install Perl packages - 'Text::CSV' & 'Spreadsheet::WriteExcel' to get xls report with summary details..{normal}"
fi
### Send report in mail 
#send_mail
[[ -f summary.txt ]] && rm summary.txt
echo -e "${green}${bold}${OUTPUT_REPORT} GENERATED AT $(date)${normal}"
