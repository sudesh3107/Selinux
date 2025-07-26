#!/bin/bash

# SELinux Enabler for Nobara OS
# Description: Safely enables and configures SELinux on Fedora-based systems

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}[!] This script must be run as root${NC}"
    exit 1
fi

# Banner
echo -e "${BLUE}"
echo "   _____ _______    _______ _   _ _____  "
echo "  / ____|__   __|/\|__   __| \ | |  __ \ "
echo " | (___    | |  /  \  | |  |  \| | |  | |"
echo "  \___ \   | | / /\ \ | |  | . \` | |  | |"
echo "  ____) |  | |/ ____ \| |  | |\  | |__| |"
echo " |_____/   |_/_/    \_\_|  |_| \_|_____/ "
echo -e "${NC}"
echo "SELinux Configuration Script for Nobara OS"
echo ""

# Function to check and install required packages
install_required_packages() {
    echo -e "${BLUE}[*] Checking for required packages...${NC}"
    
    local missing_pkgs=()
    
    # Check for policycoreutils (contains important SELinux tools)
    if ! rpm -q policycoreutils &>/dev/null; then
        missing_pkgs+=("policycoreutils")
    fi
    
    # Check for setroubleshoot (for diagnostics)
    if ! rpm -q setroubleshoot &>/dev/null; then
        missing_pkgs+=("setroubleshoot")
    fi
    
    # Check for audit (for SELinux auditing)
    if ! rpm -q audit &>/dev/null; then
        missing_pkgs+=("audit")
    fi
    
    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo -e "${YELLOW}[!] Missing packages: ${missing_pkgs[*]}${NC}"
        dnf install -y "${missing_pkgs[@]}"
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[+] Successfully installed required packages${NC}"
        else
            echo -e "${RED}[!] Failed to install required packages${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[+] All required packages are already installed${NC}"
    fi
}

# Function to check current SELinux status
check_selinux_status() {
    echo -e "${BLUE}[*] Checking current SELinux status...${NC}"
    
    if ! command -v sestatus &>/dev/null; then
        echo -e "${RED}[!] SELinux tools not installed. Please install policycoreutils package.${NC}"
        exit 1
    fi
    
    CURRENT_STATUS=$(sestatus | grep "SELinux status" | awk '{print $3}')
    CURRENT_MODE=$(sestatus | grep "Current mode" | awk '{print $3}')
    CONFIG_MODE=$(grep -Ei "^SELINUX=" /etc/selinux/config | cut -d'=' -f2)
    
    echo -e "Current Status: ${YELLOW}$CURRENT_STATUS${NC}"
    echo -e "Current Mode: ${YELLOW}$CURRENT_MODE${NC}"
    echo -e "Config Mode: ${YELLOW}$CONFIG_MODE${NC}"
    
    if [ "$CURRENT_STATUS" != "enabled" ]; then
        echo -e "${RED}[!] SELinux is currently disabled${NC}"
        return 1
    fi
    
    if [ "$CURRENT_MODE" == "enforcing" ]; then
        echo -e "${GREEN}[+] SELinux is already in enforcing mode${NC}"
        return 2
    fi
    
    return 0
}

# Function to set SELinux to permissive mode
set_permissive_mode() {
    echo -e "${BLUE}[*] Setting SELinux to permissive mode...${NC}"
    
    # Set runtime mode to permissive
    setenforce 0
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!] Failed to set permissive mode${NC}"
        exit 1
    fi
    
    # Update config file for persistence
    sed -i 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!] Failed to update config file${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[+] Successfully set SELinux to permissive mode${NC}"
}

# Function to check for SELinux relabeling
check_relabel() {
    echo -e "${BLUE}[*] Checking if filesystem relabeling is needed...${NC}"
    
    if [ ! -f "/.autorelabel" ]; then
        echo -e "${YELLOW}[!] Filesystem relabeling is recommended before enforcing${NC}"
        return 1
    fi
    
    return 0
}

# Function to schedule filesystem relabel
schedule_relabel() {
    echo -e "${BLUE}[*] Scheduling filesystem relabeling...${NC}"
    
    touch /.autorelabel
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[+] Filesystem will be relabeled on next boot${NC}"
    else
        echo -e "${RED}[!] Failed to schedule relabeling${NC}"
        exit 1
    fi
}

# Function to set SELinux to enforcing mode
set_enforcing_mode() {
    echo -e "${BLUE}[*] Setting SELinux to enforcing mode...${NC}"
    
    # First try without reboot
    setenforce 1
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!] Failed to set enforcing mode (might need reboot)${NC}"
        exit 1
    fi
    
    # Update config file for persistence
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    if [ $? -ne 0 ]; then
        echo -e "${RED}[!] Failed to update config file${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}[+] Successfully set SELinux to enforcing mode${NC}"
}

# Function to generate SELinux policy module for common issues
generate_policy_module() {
    echo -e "${BLUE}[*] Checking for SELinux denials...${NC}"
    
    if ! command -v ausearch &>/dev/null; then
        echo -e "${YELLOW}[!] audit package not installed, cannot check denials${NC}"
        return
    fi
    
    local denial_count=$(ausearch -m avc -ts recent 2>/dev/null | wc -l)
    
    if [ "$denial_count" -gt 0 ]; then
        echo -e "${YELLOW}[!] Found $denial_count recent SELinux denials${NC}"
        echo -e "${BLUE}[*] Attempting to generate policy module...${NC}"
        
        # Generate policy module
        ausearch -m avc -ts recent | audit2allow -M nobara_local
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[+] Generated policy module: nobara_local${NC}"
            echo -e "${YELLOW}[!] To install the module, run: semodule -i nobara_local.pp${NC}"
            echo -e "${YELLOW}[!] Review the module carefully before installing!${NC}"
        else
            echo -e "${RED}[!] Failed to generate policy module${NC}"
        fi
    else
        echo -e "${GREEN}[+] No recent SELinux denials found${NC}"
    fi
}

# Function to create a troubleshooting report
create_troubleshooting_report() {
    echo -e "${BLUE}[*] Creating troubleshooting report...${NC}"
    
    local report_file="/var/log/selinux_troubleshooting_report.txt"
    
    echo "SELinux Troubleshooting Report" > "$report_file"
    echo "Generated on: $(date)" >> "$report_file"
    echo "=================================" >> "$report_file"
    
    # System information
    echo -e "\n=== System Information ===" >> "$report_file"
    cat /etc/os-release >> "$report_file"
    uname -a >> "$report_file"
    
    # SELinux status
    echo -e "\n=== SELinux Status ===" >> "$report_file"
    sestatus >> "$report_file"
    
    # Recent denials
    echo -e "\n=== Recent SELinux Denials ===" >> "$report_file"
    ausearch -m avc -ts recent 2>/dev/null >> "$report_file"
    
    # Installed SELinux packages
    echo -e "\n=== Installed SELinux Packages ===" >> "$report_file"
    rpm -qa | grep -E 'selinux|policycoreutils|setroubleshoot|audit' >> "$report_file"
    
    echo -e "${GREEN}[+] Troubleshooting report created: $report_file${NC}"
}

# Main execution flow
echo -e "${BLUE}[*] Starting SELinux configuration...${NC}"

# Step 1: Install required packages
install_required_packages

# Step 2: Check current status
check_selinux_status
status_result=$?

case $status_result in
    0)
        # SELinux is enabled but not enforcing - proceed with configuration
        echo -e "${YELLOW}[!] SELinux is enabled but not in enforcing mode${NC}"
        
        # Step 3: Set to permissive mode first
        set_permissive_mode
        
        # Step 4: Check for relabeling
        check_relabel
        if [ $? -ne 0 ]; then
            read -p "Do you want to schedule filesystem relabeling on next boot? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                schedule_relabel
            fi
        fi
        
        # Step 5: Generate policy module if needed
        generate_policy_module
        
        # Step 6: Set to enforcing mode
        read -p "Are you ready to set SELinux to enforcing mode? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            set_enforcing_mode
            echo -e "${YELLOW}[!] You may need to reboot for changes to take full effect${NC}"
        fi
        ;;
    1)
        # SELinux is disabled - need to enable first
        echo -e "${RED}[!] SELinux is currently disabled${NC}"
        echo -e "${YELLOW}[!] To enable SELinux, you need to:${NC}"
        echo -e "1. Edit /etc/selinux/config and set SELINUX=permissive"
        echo -e "2. Reboot the system"
        echo -e "3. Run this script again after reboot"
        ;;
    2)
        # SELinux is already enforcing
        echo -e "${GREEN}[+] SELinux is already properly configured${NC}"
        ;;
esac

# Create troubleshooting report
create_troubleshooting_report

echo -e "${BLUE}[*] SELinux configuration complete${NC}"
