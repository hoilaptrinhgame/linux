#!/bin/bash
declare -A host_console
log_dir="/home/admin/statistic_log"
host_console["ip-172-31-22-13"]="Kamailio"
host_console["ip-172-31-38-182"]="Asterisk1"
host_console["ip-172-31-45-123"]="Asterisk2"
host_console["ip-172-31-45-175"]="Asterisk3"
sudo asterisk -rvvvvv > ${log_dir}/console_${host_console[$HOSTNAME]}.txt
