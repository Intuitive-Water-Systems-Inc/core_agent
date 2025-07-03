#!/bin/bash

# To install new device:
# sudo bash -c "$(curl -sN https://install.connect.sixfab.com)" -- -t TOKEN_HERE
# To uninstall device:
# sudo bash -c "$(curl -sN https://install.connect.sixfab.com)" -- --uninstall

clear
cat <<"EOF"
    .&@&.             %%          .%@%           
   #@@@%           *&@@@&.         %@@@#         
  &@@&. .&@@%   .%@@@@@%/.   .%@@&. ,&@@%        
 %@@&. /@@@#  *&@@@@&&&@@@@&,  %@@&* .&@@&       
/@@@* .@@@#  &@@&(       (@@@%  #@@&, *@@@*      
%@@&. #@@&. (@@@,         ,&@@( .@@@(  &@@#      
%@@&. #@@&. /@@@,         *&@@( .@@@(  &@@#      
*@@@* .&@@#  %@@@#       %@@@#  #@@&, /@@@,      
 %@@&, *@@@%  .&@@@@@@@@@@@%. .&@@&, ,&@@%       
  %@@&*  %@@#     *#%%%#*     #@@%  *&@@%        
   (@@@&.                         .&@@&/         
     #@#                           #@#    

  ____  _       __       _        ____               
 / ___|(_)_  __/ _| __ _| |__    / ___|___  _ __ ___ 
 \___ \| \ \/ / |_ / _` | '_ \  | |   / _ \| '__/ _ \
  ___) | |>  <|  _| (_| | |_) | | |__| (_) | | |  __/
 |____/|_/_/\_\_|  \__,_|_.__/   \____\___/|_|  \___|
=====================================================
EOF

AGENT_REPOSITORY="https://github.com/sixfab/core_agent.git"
MANAGER_REPOSITORY="https://github.com/sixfab/core_manager.git"

VERBOSE_SUFFIX="/dev/null"
OS_DISTRO="Raspbian"

SIXFAB_PATH="/opt/sixfab"
CORE_PATH="$SIXFAB_PATH/core"
MANAGER_SOURCE_PATH="$CORE_PATH/manager"
AGENT_SOURCE_PATH="$CORE_PATH/agent"
ENV_PATH="$SIXFAB_PATH/.env.yaml"


print_help() {
    printf "[HELP]  $1\n"
}

print_info() {
    YELLOW='\033[0;33m'
    NC='\033[0m'
    printf "${YELLOW}[INFO]${NC}  $1\n"
}

print_error() {
    RED='\033[0;31m'
    NC='\033[0m'
    printf "${RED}[ERROR]${NC} $1\n"
}

print_done() {
    GREEN='\033[0;32m'
    NC='\033[0m'
    printf "${GREEN}[DONE]${NC}  $1\n"
}

help() {
    print_help "To install new device:"
    print_help 'sudo bash -c "$(curl -sN https://install.connect.sixfab.com)" -- -t TOKEN_HERE'
    print_help "To uninstall device:"
    print_help 'sudo bash -c "$(curl -sN https://install.connect.sixfab.com)" -- --uninstall'
    destroy_scroll_area
}

run_command() {
    for count in {1..3}; do 
        COMMAND=$1
        sudo su sixfab -c "eval $COMMAND" &> $VERBOSE_SUFFIX
        STATUS_CODE=$?
        
        if [ $STATUS_CODE -eq "0" ]; then
            return
        fi
    done

    print_error "Installer faced an error during the following command, please re-run installer"
    print_error "*****************************************************"
    printf "\033[0;31m[ERROR]\033[0m $COMMAND\n"
    print_error "*****************************************************"
    exit 1
}

initialize_parameters() {

    TOKEN=""
    B_TOKEN=""
    REGION="global"
    BOARD="RaspberryPi4"
    IS_DEV=False
    VERBOSE=False

    deployment_type="device"

    while getopts "t:p:r:b:dv" arg; do
        case "$arg" in
        t) TOKEN="$OPTARG" ;;
        p) B_TOKEN="$OPTARG" ;;
        r) REGION="$OPTARG" ;;
        b) BOARD="$OPTARG" ;;
        v) VERBOSE=True ;;
        d) IS_DEV=True ;;
        -) break ;;
        \?) ;;
        esac
    done

    if [ -z "$TOKEN" ] && [ -z "$B_TOKEN" ]; then
        print_error "Device token is missing"
        help
        exit 1
    fi

    if [ -z "$TOKEN" ]; then
        deployment_type="bulk"
    fi

    if [ "$VERBOSE" == True ]; then
        VERBOSE_SUFFIX="/dev/stdout"
    fi
}

check_is_root() {
    if [ $(id -u) != 0 ]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

if [ "$1" = "--uninstall" ]; then
    print_info "Uninstall Sixfab Core..."

    if [ -d "$CORE_PATH" ]; then
        print_info "Removing source..."
        sudo rm -r $CORE_PATH &> $VERBOSE_SUFFIX
        print_info "Source removed."
    fi

    if [ -d "/home/sixfab/.core" ]; then
        print_info "Removing local files..."
        sudo rm -r /home/sixfab/.core &> $VERBOSE_SUFFIX
        print_info "Local files removed."
    fi

    if [ -e "$SIXFAB_PATH/.env.yaml" ]; then
        print_info "Removing environment file..."
        sudo rm -r $SIXFAB_PATH/.env.yaml &> $VERBOSE_SUFFIX
        print_info "Environment file removed."
    fi

    print_info "Stopping & removing services..."
    sudo systemctl stop core_agent &> $VERBOSE_SUFFIX
    sudo systemctl stop core_manager &> $VERBOSE_SUFFIX

    sudo rm /etc/systemd/system/core_agent.service &> $VERBOSE_SUFFIX
    sudo rm /etc/systemd/system/core_manager.service &> $VERBOSE_SUFFIX
    sudo systemctl daemon-reload
    print_info "Removed services."

    print_done "Sixfab Core is uninstalled successfully"

    exit 0
fi


check_distro() {
    OS_DETAILS=$(cat /etc/os-release)
    case "$OS_DETAILS" in
    *Raspbian*|*Debian*)
        OS_DISTRO="Raspbian"
        return
        ;;
    *Ubuntu*|*ubuntu*)
        OS_DISTRO="Ubuntu"
        return
        ;;
    esac

    read -p "[WARNING] The operating system is not one of the supported ones, Sixfab Core may not run properly. Do you want to continue? (y/N) " yn

    case "$yn" in
    *y*|*Y*)
        return
        ;;
    *)
        print_info "Installer is exiting..."
        exit 1
        ;;
    esac
}

check_usb_is_connected() {
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m'

    LSUSB_OUTPUT=$(lsusb) > /dev/null 2>&1

    case "$LSUSB_OUTPUT" in
    *Telit*|*1b7c*|*Quectel*|*2c7c*)
        printf -- "-------\n"
        printf "${RED}Warning\n${NC}"
        printf -- "-------\n"
        printf "You are using the cellular modem. It may cause unintended data costs or failed installation!\n" 
        printf -- "-> Unplug the USB cable from the Sixfab HAT before continuing! (${GREEN}Recommended${NC})\n"
        printf -- "-> Then press ${YELLOW}ENTER${NC} to continue to installation.\n"
        read -r -p "" foo
        return
        ;;
    *)
        return
        ;;
    esac
}

update_system() {
    print_info "Updating system package index..."
    run_command "sudo apt update -y"
}

check_user() {
    create_sixfab_user() {
        sudo adduser --disabled-password --gecos "" sixfab &> $VERBOSE_SUFFIX
    }

    add_usb_permissions_to_plugdev() {
        PERMISSIONS_TO_ADD="SUBSYSTEM==\"usb\", ENV{DEVTYPE}==\"usb_device\", MODE=\"0664\", GROUP=\"plugdev\""
        PLUGDEV_RULES_PATH=/etc/udev/rules.d/plugdev_usb.rules

        if [ ! -f $PLUGDEV_RULES_PATH ]; then
            echo $PERMISSIONS_TO_ADD | sudo tee $PLUGDEV_RULES_PATH &> $VERBOSE_SUFFIX
            sudo udevadm control --reload
            sudo udevadm trigger
        fi
    }

    add_gpio_permissions_for_ubuntu() {   
        GPIO_RULES_PATH=/etc/udev/rules.d/gpio.rules
        
        if [ ! -f $GPIO_RULES_PATH ]; then
            echo "\"SUBSYSTEM==\"gpio\", GROUP=\"gpio\", MODE=\"0660\"
SUBSYSTEM==\"gpio*\", PROGRAM=\"/bin/sh -c '\
chown -R root:gpio /sys/class/gpio && chmod -R 770 /sys/class/gpio;\
chown -R root:gpio /sys/devices/virtual/gpio && chmod -R 770 /sys/devices/virtual/gpio;\
chown -R root:gpio /sys\$devpath && chmod -R 770 /sys\$devpath\
'\"" | sudo tee $GPIO_RULES_PATH &> $VERBOSE_SUFFIX
            
            sudo groupadd gpio
            sudo usermod -aG gpio sixfab
            sudo udevadm control --reload
            sudo udevadm trigger
        fi
    }

    check_sixfab_user_privilege() {
        add_usb_permissions_to_plugdev

        case "$OS_DISTRO" in
        *Raspbian*)
            sudo usermod -aG spi sixfab &> $VERBOSE_SUFFIX
            sudo usermod -aG i2c sixfab &> $VERBOSE_SUFFIX
            sudo usermod -aG gpio sixfab &> $VERBOSE_SUFFIX
            ;;
        *Ubuntu*|*ubuntu*)
            add_gpio_permissions_for_ubuntu
            ;;
        esac

        # common usermods
        sudo usermod -aG sudo sixfab &> $VERBOSE_SUFFIX
        sudo usermod -aG dialout sixfab &> $VERBOSE_SUFFIX
        sudo usermod -aG users sixfab &> $VERBOSE_SUFFIX
        sudo usermod -aG plugdev sixfab &> $VERBOSE_SUFFIX
    }

    if id -u "sixfab" &> $VERBOSE_SUFFIX; then
        print_info "Sixfab user already exists, updating..."
        check_sixfab_user_privilege
    else
        print_info "Creating sixfab user..."
        create_sixfab_user
        check_sixfab_user_privilege
    fi
}

initialize_sudoers() {
    print_info "Updating sudoers..."
    echo "sixfab ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/sixfab_core &> $VERBOSE_SUFFIX
    print_info "Sudoers updated"
}

check_system_dependencies() {
    git --version &> $VERBOSE_SUFFIX
    IS_GIT_INSTALLED=$?
    python3 --version &> $VERBOSE_SUFFIX
    IS_PYTHON_INSTALLED=$?
    pip3 --version &> $VERBOSE_SUFFIX
    IS_PIP_INSTALLED=$?

    if [ ! "$IS_GIT_INSTALLED" = "0" ] || [ ! "$IS_PYTHON_INSTALLED" = "0" ] || [ ! "$IS_PIP_INSTALLED" = "0" ]; then
        install_system_dependencies
    fi
}

install_system_dependencies() {
    print_info "Looking for dependencies..."

    # Check if git installed
    if ! [ -x "$(command -v git)" ]; then
        print_info 'Git is not installed, installing...'
        run_command "sudo apt install git -y"
    fi

    # Check if python3 installed
    if ! [ -x "$(command -v python3)" ]; then
        print_info 'Python3 is not installed, installing...'
        run_command "sudo apt install python3 -y"
    fi

    # Check python3 version, minimum python3.6 required
    version=$(python3 -V 2>&1 | grep -Po '(?<=Python )(.+)' | sed -e 's/\.//g')

    if [ "$version" -lt "360" ]; then
        print_error "Python 3.6 or later version is required to run Sixfab Core. Please upgrade Python and re-try. Using latest version of Raspberry Pi OS (Previously known as Raspbian OS) is recommended."
        exit
    fi

    # Check if pip3 installed
    if ! [ -x "$(command -v pip3)" ]; then
        print_info 'Pip for python3 is not installed, installing...'
        run_command "sudo apt install python3-pip -y"
    fi

    # Install python3-venv
    run_command "sudo apt install python3-venv -y"

    # Check if ifmetric installed
    if ! [ -x "$(command -v ifmetric)" ]; then
        print_info 'ifmetric is not installed, installing...'
        run_command "sudo apt install ifmetric -y"
    fi

    # Check if net-tools installed
    if ! [ -x "$(command -v route)" ]; then
        print_info 'net-tools is not installed, installing...'
        run_command "sudo apt install net-tools -y"
    fi

    # Check if lshw 
    if ! [ -x "$(command -v lshw)" ]; then
        print_info 'lshw is not installed, installing...'
        run_command "sudo apt install lshw -y"
    fi

    check_system_dependencies
}

remove_conflicting_packages() {
    # Check if modemmanager installed
    if [ -x "$(command -v ModemManager)" ]; then
        print_info 'Removing ModemManager...'
        run_command "sudo apt purge modemmanager -y"
    fi
}

check_network_layer_dependencies() {
    
    # Configuration for compatibility of systemd-networkd service
    # on ubuntu-server with raspberry pi hardware
    configure_systemd_networkd_for_ubuntu(){
        NETWORKD_CONF_PATH="/etc/systemd/network/10-allifs.network"
        echo "[Match]
Name=*

[Network]
DHCP=true" | sudo tee $NETWORKD_CONF_PATH &> $VERBOSE_SUFFIX

        sudo systemctl restart systemd-networkd.service
    }


    case "$BOARD" in
    *Raspberry*)
        case "$OS_DISTRO" in
        *Raspbian*)
            print_info "Board: Raspberry Pi - OS: Raspbian"
            ;;
        *Ubuntu*)
            print_info "Board: Raspberry Pi - OS: Ubuntu"
            configure_systemd_networkd_for_ubuntu
            ;;
        esac
        ;;
    *Jetson*)
        print_info "Board: Nvidia Jetson Nano - OS: Ubuntu"
    ;;
    esac
}


install_agent() {
    if [ -d "$AGENT_SOURCE_PATH" ]; then
        print_info "Agent source already exists, updating..."
        git -C $AGENT_SOURCE_PATH reset --hard HEAD &> $VERBOSE_SUFFIX
        git -C $AGENT_SOURCE_PATH pull &> $VERBOSE_SUFFIX
    else
        print_info "Downloading agent source..."
        git clone $AGENT_REPOSITORY $AGENT_SOURCE_PATH &> $VERBOSE_SUFFIX
        sudo chown sixfab:sixfab $AGENT_SOURCE_PATH -R &> $VERBOSE_SUFFIX
        git config --global --add safe.directory $AGENT_SOURCE_PATH &> $VERBOSE_SUFFIX
    fi

    apply_dev_mode_if_necessary "agent"

    print_info "Creating virtual environment and installing agent requirements..."
    sudo python3 -m venv $AGENT_SOURCE_PATH/venv &> $VERBOSE_SUFFIX
    source $AGENT_SOURCE_PATH/venv/bin/activate &> $VERBOSE_SUFFIX
    pip3 install -r $AGENT_SOURCE_PATH/requirements.txt --no-cache-dir &> $VERBOSE_SUFFIX
    deactivate &> $VERBOSE_SUFFIX
    
    print_info "Initializing agent service..."
    sed -i "s|AGENT_SOURCE_PATH|$AGENT_SOURCE_PATH|g" $AGENT_SOURCE_PATH/core_agent.service
    mv $AGENT_SOURCE_PATH/core_agent.service /etc/systemd/system/core_agent.service &> $VERBOSE_SUFFIX
    sudo chown sixfab /etc/systemd/system/core_agent.service &> $VERBOSE_SUFFIX
    sudo systemctl daemon-reload &> $VERBOSE_SUFFIX
    sudo systemctl enable core_agent &> $VERBOSE_SUFFIX
    restart_sixfab_services "agent"

    print_info "Agent service initialized successfully."
}

install_manager() {
    if [ -d "$MANAGER_SOURCE_PATH" ]; then
        print_info "Manager source already exists, updating..."
        git -C $MANAGER_SOURCE_PATH reset --hard HEAD &> $VERBOSE_SUFFIX
        git -C $MANAGER_SOURCE_PATH pull &> $VERBOSE_SUFFIX
    else
        print_info "Downloading manager source..."
        git clone $MANAGER_REPOSITORY $MANAGER_SOURCE_PATH &> $VERBOSE_SUFFIX
        sudo chown sixfab:sixfab $MANAGER_SOURCE_PATH -R &> $VERBOSE_SUFFIX
        git config --global --add safe.directory $MANAGER_SOURCE_PATH &> $VERBOSE_SUFFIX
    fi

    apply_dev_mode_if_necessary "manager"

    print_info "Creating virtual environment and installing manager requirements..."
    sudo python3 -m venv $MANAGER_SOURCE_PATH/venv &> $VERBOSE_SUFFIX
    source $MANAGER_SOURCE_PATH/venv/bin/activate &> $VERBOSE_SUFFIX
    pip3 install -r $MANAGER_SOURCE_PATH/requirements.txt --no-cache-dir &> $VERBOSE_SUFFIX
    deactivate &> $VERBOSE_SUFFIX
    print_info "Virtual environment deactivated."

    print_info "Initializing manager service..."
    sed -i "s|MANAGER_SOURCE_PATH|$MANAGER_SOURCE_PATH|g" $MANAGER_SOURCE_PATH/core_manager.service
    mv $MANAGER_SOURCE_PATH/core_manager.service /etc/systemd/system/core_manager.service &> $VERBOSE_SUFFIX
    sudo chown sixfab /etc/systemd/system/core_manager.service &> $VERBOSE_SUFFIX
    sudo systemctl daemon-reload &> $VERBOSE_SUFFIX
    sudo systemctl enable core_manager &> $VERBOSE_SUFFIX
    restart_sixfab_services "manager"

    print_info "Manager service initialized successfully."
}

check_sixfab_folder() {
    if [ ! -d "$SIXFAB_PATH" ]; then
        sudo mkdir $SIXFAB_PATH
    fi

    if [ ! -d "$CORE_PATH" ]; then
        sudo mkdir $CORE_PATH
    fi

    sudo chown sixfab:sixfab $SIXFAB_PATH -R
}

initialize_environment_file() {
    print_info "Initializing environment file..."

    # Create venv to run python script
    python3 -m venv venv_temp &> $VERBOSE_SUFFIX
    source venv_temp/bin/activate &> $VERBOSE_SUFFIX
    pip3 install pyyaml --no-cache-dir&> $VERBOSE_SUFFIX

    venv_temp/bin/python3 -c "
import yaml

region = '$REGION'
board = '$BOARD'
is_dev = $IS_DEV

try:
    with open('$SIXFAB_PATH/.env.yaml', 'r') as env_file:
        environments = yaml.safe_load(env_file)
except:
    environments = {}

if not 'core' in environments:
    environments['core'] = {}

elif not is_dev and 'MQTT_HOST' in environments['core']:
    del environments['core']['MQTT_HOST']

if '$TOKEN':
    environments['core']['token'] = '$TOKEN'

if '$B_TOKEN':
    environments['core']['b_token'] = '$B_TOKEN'

if is_dev:
    environments['core']['MQTT_HOST'] = 'mqtt.connect.sixfab.dev'

if region == 'global' and environments['core'].get('apn', False):
    environments['core'].pop('apn', False)
elif region == 'emea':
    environments['core']['apn'] = 'de1.super'
elif region == 'apac':
    environments['core']['apn'] = 'sg1.super'

environments['core']['board'] = board

with open('$SIXFAB_PATH/.env.yaml', 'w') as env_file:
    yaml.dump(environments, env_file)
"
    print_info "Initialized environment file"

    print_info "Temporary environment removing"
    deactivate &> $VERBOSE_SUFFIX
    rm -rf venv_temp &> $VERBOSE_SUFFIX
    sudo chown sixfab:sixfab $SIXFAB_PATH/.env.yaml &> $VERBOSE_SUFFIX
}


apply_dev_mode_if_necessary() {
    if [ "$IS_DEV" == True ]; then
    
        if [ $1 == "manager" ]; then
            print_info "Applying dev mode to manager..."
            cd $MANAGER_SOURCE_PATH/ &> $VERBOSE_SUFFIX
            sudo git reset --hard HEAD &> $VERBOSE_SUFFIX
            sudo git checkout dev &> $VERBOSE_SUFFIX
            restart_sixfab_services "manager"
        fi

        if [ $1 == "agent" ]; then
            print_info "Applying dev mode to agent..."
            cd $AGENT_SOURCE_PATH/ &> $VERBOSE_SUFFIX
            sudo git reset --hard HEAD &> $VERBOSE_SUFFIX
            sudo git checkout dev &> $VERBOSE_SUFFIX
            restart_sixfab_services "agent"
        fi
    fi
}


restart_sixfab_services(){
    if [ $deployment_type == "bulk" ]; then
        if [ $1 == "agent" ]; then
            sudo systemctl stop core_agent &> $VERBOSE_SUFFIX
        elif [ $1 == "manager" ]; then
            sudo systemctl stop core_manager &> $VERBOSE_SUFFIX
        fi
    else
        if [ $1 == "agent" ]; then
            sudo systemctl restart core_agent &> $VERBOSE_SUFFIX
        elif [ $1 == "manager" ]; then
            sudo systemctl restart core_manager &> $VERBOSE_SUFFIX
        fi
    fi
}


reboot_system() {
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
    
    remove_conflicting_packages

    if [ $deployment_type == "bulk" ]; then
    printf "\n"
    printf -- "-----------------------------------------------------------------------\n"
    printf "Bulk deployment image is ready. You can use this image to deploy multiple CORE devices\n"
    printf "Follow instructions at the link below to copy os image and create multiple SD cards\n"
    printf "${YELLOW}Link:${NC} https://docs.sixfab.com/page/bulk-deployments#cloning-the-sd-card"
    printf "\n"
    printf "Press ${YELLOW}ENTER${NC} to power off your system as the first step.\n" 
    printf "Press ${YELLOW}Ctrl+C${NC} (^C) to finish installation without power off.\n" 
    printf -- "-----------------------------------------------------------------------\n"
    printf "\n"
    read -r -p "" foo
    sudo poweroff
    else
    printf "\n"
    printf -- "-----------------------------------------------------------------------\n"  
    printf "Press ${YELLOW}ENTER${NC} to reboot your system. (${GREEN}Recommended${NC})\n" 
    printf "Press ${YELLOW}Ctrl+C${NC} (^C) to finish installation without reboot.\n" 
    printf "\n"
    printf "${GREEN}Reminder${NC}: Plug the USB cable to Sixfab HAT!\n"
    printf "${RED}Warning${NC}: Network priority settings will be effective after reboot!\n"
    printf -- "-----------------------------------------------------------------------\n"
    printf "\n"
    read -r -p "" foo
    sudo reboot
    fi
}

### Progress Bar ###
# Revised by selengalp (yasinkaya.121@gmail.com) on 28/11/2021
# Main Source: https://github.com/pollev/bash_progress_bar

# Constants
CODE_SAVE_CURSOR="\033[s"
CODE_RESTORE_CURSOR="\033[u"
CODE_CURSOR_IN_SCROLL_AREA="\033[1A"
COLOR_FG="\e[32m"
COLOR_BG="\e[47m"
COLOR_BG_BLOCKED="\e[43m"
RESTORE_FG="\e[39m"
RESTORE_BG="\e[49m"

# Variables
PROGRESS_BLOCKED="false"
TRAPPING_ENABLED="false"
TRAP_SET="false"

CURRENT_NR_LINES=0

setup_scroll_area() {
    # If trapping is enabled, we will want to activate it whenever 
    # we setup the scroll area and remove it when we break the scroll area
    if [ "$TRAPPING_ENABLED" = "true" ]; then
        trap_on_interrupt
    fi

    lines=$(tput lines)
    CURRENT_NR_LINES=$lines
    let lines=$lines-1
    # Scroll down a bit to avoid visual glitch when the screen area shrinks by one row
    echo -en "\n"

    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"
    # Set scroll region (this will place the cursor in the top left)
    echo -en "\033[0;${lines}r"

    # Restore cursor but ensure its inside the scrolling area
    echo -en "$CODE_RESTORE_CURSOR"
    echo -en "$CODE_CURSOR_IN_SCROLL_AREA"

    # Start empty progress bar
    draw_progress_bar 0
}

destroy_scroll_area() {
    lines=$(tput lines)
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"
    # Set scroll region (this will place the cursor in the top left)
    echo -en "\033[0;${lines}r"

    # Restore cursor but ensure its inside the scrolling area
    echo -en "$CODE_RESTORE_CURSOR"
    echo -en "$CODE_CURSOR_IN_SCROLL_AREA"

    # We are done so clear the scroll bar
    clear_progress_bar

    # Scroll down a bit to avoid visual glitch when the screen area grows by one row
    echo -en "\n\n"

    # Once the scroll area is cleared, we want to remove any trap previously set. Otherwise, ctrl+c will exit our shell
    if [ "$TRAP_SET" = "true" ]; then
        trap - INT
    fi
}

draw_progress_bar() {
    percentage=$1
    lines=$(tput lines)
    let lines=$lines

    # Check if the window has been resized. If so, reset the scroll area
    if [ "$lines" -ne "$CURRENT_NR_LINES" ]; then
        setup_scroll_area
    fi

    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"

    # Move cursor position to last row
    echo -en "\033[${lines};0f"

    # Clear progress bar
    tput el

    # Draw progress bar
    PROGRESS_BLOCKED="false"
    print_bar_text $percentage

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR"
}

block_progress_bar() {
    percentage=$1
    lines=$(tput lines)
    let lines=$lines
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"

    # Move cursor position to last row
    echo -en "\033[${lines};0f"

    # Clear progress bar
    tput el

    # Draw progress bar
    PROGRESS_BLOCKED="true"
    print_bar_text $percentage

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR"
}

clear_progress_bar() {
    lines=$(tput lines)
    let lines=$lines
    # Save cursor
    echo -en "$CODE_SAVE_CURSOR"

    # Move cursor position to last row
    echo -en "\033[${lines};0f"

    # clear progress bar
    tput el

    # Restore cursor position
    echo -en "$CODE_RESTORE_CURSOR"
}

print_bar_text() {
    local percentage=$1
    local cols=$(tput cols)
    let bar_size=$cols-30

    local color="${COLOR_FG}${COLOR_BG}"
    if [ "$PROGRESS_BLOCKED" = "true" ]; then
        color="${COLOR_FG}${COLOR_BG_BLOCKED}"
    fi

    # Prepare progress bar
    let complete_size=($bar_size*$percentage)/100
    let remainder_size=$bar_size-$complete_size
    progress_bar=$(echo -ne ""; echo -en "${color}"; printf_new "█" $complete_size; echo -en "${RESTORE_FG}${RESTORE_BG}"; printf_new "" $remainder_size; echo -ne "");
    
    # Print progress bar
    echo -ne "Total Progress-> ${progress_bar} ${percentage}%"
}

enable_trapping() {
    TRAPPING_ENABLED="true"
}

trap_on_interrupt() {
    # If this function is called, we setup an interrupt handler to cleanup the progress bar
    TRAP_SET="true"
    trap cleanup_on_interrupt INT
}

cleanup_on_interrupt() {
    destroy_scroll_area
    exit
}

printf_new() {
    str=$1
    num=$2
    v=$(printf "%-${num}s" "$str")
    echo -ne "${v// /$str}"
}
### End of progress bar ###

main() {

    enable_trapping
    setup_scroll_area

    initialize_parameters "$@"
    check_is_root
    check_distro
    check_usb_is_connected
    draw_progress_bar 5

    check_user
    draw_progress_bar 7

    initialize_sudoers
    draw_progress_bar 10
    
    update_system
    draw_progress_bar 20

    install_system_dependencies
    draw_progress_bar 30

    check_network_layer_dependencies
    draw_progress_bar 40

    check_system_dependencies
    draw_progress_bar 50

    check_sixfab_folder
    initialize_environment_file
    draw_progress_bar 60

    install_agent
    draw_progress_bar 75

    install_manager
    draw_progress_bar 100

    print_done "Installation completed successfully."
    reboot_system
    destroy_scroll_area
}

main "$@"