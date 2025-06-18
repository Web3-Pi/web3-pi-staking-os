#!/bin/bash
#
# Web3 Pi Staking OS install script
#
echo "[install.sh] - start at $(date '+%Y-%m-%d %H:%M:%S')"

SWAPFILE_SIZE=16384
RC_LOG="/opt/web3pi/logs/rc.local.txt"
E_LOG="/opt/web3pi/logs/elog.txt"

# Function: echolog
# Description: Logs messages with a timestamp prefix. If no arguments are provided,
#              reads from stdin and logs each line. Outputs to console and appends to $LOGI file.
LOGI="/opt/web3pi/logs/web3pi.log"
echolog(){
    if [ $# -eq 0 ]
    then cat - | while read -r message
        do
                echo "$(date +"[%F %T %Z] -") $message" | tee -a $LOGI
            done
    else
        echo -n "$(date +'[%F %T %Z]') - " | tee -a $LOGI
        echo $* | tee -a $LOGI
    fi
}

echolog " "
echolog "Web3 Pi install.sh START - Web3 Pi install.sh START - Web3 Pi install.sh START - Web3 Pi install.sh START - Web3 Pi install.sh START"
echolog " "
timedatectl | echolog


# Function: set_install_stage
# Description: A function that saves the installation stage to the file /root/.install_stage. The file stores a number as text. The beginning of the installation is marked by 0, and the higher the number, the further along the installation process is. A value of 100 indicates the installation is complete.
set_install_stage() {
  local number=$1
  echo $number > /root/.install_stage
}


# If the installation stage file does not exist, create it and initialize it with the value "0".
if [ ! -f "/root/.install_stage" ]; then
  echolog "/root/.install_stage not exist"
  touch /root/.install_stage
  set_install_stage "0" # initial value
  echolog "/root/.install_stage file created and initialized to 0"
fi

# Function: get_install_stage
# Description: A function that retrieves the installation stage from the file /root/.install_stage.
get_install_stage() {
    local file_path=$1
    if [ -f "/root/.install_stage" ]; then
        local number=$(cat "/root/.install_stage")
        echo $number
    else
        echolog "File /root/.install_stage does not exist."
        return 0
    fi
}

# Function: set_status_jlog
# Function to write a string to a file with status
STATUS_FILE="/opt/web3pi/status.jlog"
set_status_jlog() {
  local status="$1"
  local level="$2"
  jq -n -c\
    --arg status "$status"\
    --arg stage "$(get_install_stage)"\
    --arg time "$(date +"%Y-%m-%dT%H:%M:%S%z")"\
    --arg level "$([ "$level" = "" ] && echo "INFO" || echo "$level")"\
    '{"time": $time, "status": $status, "level": $level, "stage": $stage}' | tee -a $STATUS_FILE
  #echolog " " 
  #echolog "STAGE $(get_install_stage): $status" 
  #echolog " " 
}

# Function: set_status
# Function to write a string to a file with status
set_status() {
  local status="$1"  # Assign the first argument to a local variable
  echo "STAGE $(get_install_stage): $status" > /opt/web3pi/status.txt  # Write the string to the file
  echolog " " 
  echolog "STAGE $(get_install_stage): $status" 
  echolog " " 
  set_status_jlog "$status" INFO
}

set_status "[install.sh] - Script started"

set_error() {
  local status="$1"
  set_status_jlog "$status" "ERROR"
}

# Terminate the script with saving logs
terminateScript()
{
  echolog "terminateScript()"
  touch $E_LOG
  grep "rc.local" /var/log/syslog >> $E_LOG 
  exit 1
}

# Read custom config flags from /boot/firmware/config.txt
config_read_file() {
    (grep -E "^${2}=" -m 1 "${1}" 2>/dev/null || echo "VAR=UNDEFINED") | head -n 1 | cut -d '=' -f 2-;
}

config_get() {
    val="$(config_read_file /boot/firmware/config.txt "${1}")";
    printf -- "%s" "${val}";
}
# use example 
# echo "$(config_get lighthouse)";

# MAIN install.sh part
if [ "$(get_install_stage)" -eq 2 ]; then

set_status "[install.sh] - Main installation part"

## SWAP SPACE CONFIGURATION ###################################################################
set_status "[install.sh] - SWAP configuration"

# Configure swap file location and size
#sed -i "s|#CONF_SWAPFILE=.*|CONF_SWAPFILE=/mnt/storage/swapfile|" /etc/dphys-swapfile
sed -i "s|#CONF_SWAPSIZE=.*|CONF_SWAPSIZE=$SWAPFILE_SIZE|" /etc/dphys-swapfile
sed -i "s|#CONF_MAXSWAP=.*|CONF_MAXSWAP=$SWAPFILE_SIZE|" /etc/dphys-swapfile

# Check total RAM in kB
total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2}')
set_status "[install.sh] - Detected RAM: ${total_ram} kB"

# Conditions
if [ "$total_ram" -lt 7000000 ]; then
    set_error "[install.sh] - Not enough RAM for Web3 Pi. Minimum required is 8 GB"
elif [ "$total_ram" -ge 15000000 ]; then
    set_status "[install.sh] - Setting vm.swappiness to 10"
    # Enable dphys-swapfile service
    systemctl enable dphys-swapfile
    {
    echo "vm.min_free_kbytes=65536"
    echo "vm.swappiness=10"
    echo "vm.vfs_cache_pressure=100"
    echo "vm.dirty_background_ratio=10"
    echo "vm.dirty_ratio=20"
    } >> /etc/sysctl.conf
    sysctl -p
elif [ "$total_ram" -ge 7000000 ]; then
    set_status "[install.sh] - Setting vm.swappiness to 80"
    # Enable dphys-swapfile service
    systemctl enable dphys-swapfile
    {
    echo "vm.min_free_kbytes=65536"
    echo "vm.swappiness=80"
    echo "vm.vfs_cache_pressure=500"
    echo "vm.dirty_background_ratio=1"
    echo "vm.dirty_ratio=50"
    } >> /etc/sysctl.conf
    sysctl -p
else
    set_error "[install.sh] - RAM does not match expected specifications."
fi
#--------------------------------------------------------------------------------------------

set_status "[install.sh] - Change the stage to 100"
set_install_stage 100

set_status "[install.sh] - Write rc.local logs to ${RC_LOG}"
grep "rc.local" /var/log/syslog >> $RC_LOG

set_status "[install.sh] - Rebooting..."
sleep 3
reboot
fi

# Print the IP address
_IP=$(hostname -I) || true
if [ "$_IP" ]; then
  printf "\n\n\nRaspberry Pi IP address is %s\n\n\n" "$_IP"
fi

echo "[install.sh] - exit 0 at $(date '+%Y-%m-%d %H:%M:%S')"
exit 0