#!/bin/bash

# ADB Device Information Collector for macOS
# Waits for ADB device connection and pulls comprehensive hardware/software information

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="${SCRIPT_DIR}/device_info_$(date +%Y%m%d_%H%M%S).md"
TEMP_LOG="/tmp/adb_info_temp.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if ADB is available
check_adb() {
    if ! command -v adb &> /dev/null; then
        log_error "ADB not found. Please install Android SDK Platform Tools."
        exit 1
    fi
    log_success "ADB found: $(which adb)"
}

# Wait for device connection
wait_for_device() {
    log_info "Waiting for ADB device connection..."
    echo "Please connect your Android device with USB debugging enabled."

    while true; do
        if adb devices | grep -q "device$"; then
            DEVICE_ID=$(adb devices | grep "device$" | awk '{print $1}' | head -1)
            log_success "Device connected: $DEVICE_ID"
            break
        fi
        echo -n "."
        sleep 1
    done
}

# Execute ADB command with error handling
execute_adb_command() {
    local cmd="$1"
    local description="$2"
    local output_section="$3"

    echo "## $output_section" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    echo "**Command:** \`$cmd\`" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    # Use eval to properly handle complex shell commands
    # Check if gtimeout (GNU timeout) is available, otherwise use basic execution
    if command -v gtimeout &> /dev/null; then
        TIMEOUT_CMD="gtimeout 30"
    elif command -v timeout &> /dev/null; then
        TIMEOUT_CMD="timeout 30"
    else
        TIMEOUT_CMD=""
    fi

    if [ -n "$TIMEOUT_CMD" ]; then
        if $TIMEOUT_CMD bash -c "$cmd" > "$TEMP_LOG" 2>&1; then
            timeout_success=true
        else
            timeout_success=false
        fi
    else
        if bash -c "$cmd" > "$TEMP_LOG" 2>&1; then
            timeout_success=true
        else
            timeout_success=false
        fi
    fi

    if [ "$timeout_success" = "true" ]; then
        echo '```' >> "$OUTPUT_FILE"
        cat "$TEMP_LOG" >> "$OUTPUT_FILE"
        echo '```' >> "$OUTPUT_FILE"
        log_success "$description"
    else
        echo "**ERROR:** Command failed or timed out" >> "$OUTPUT_FILE"
        echo '```' >> "$OUTPUT_FILE"
        cat "$TEMP_LOG" >> "$OUTPUT_FILE"
        echo '```' >> "$OUTPUT_FILE"
        log_warning "$description - FAILED"
    fi

    echo "" >> "$OUTPUT_FILE"
    echo "---" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
}

# Initialize output file
init_output_file() {
    cat > "$OUTPUT_FILE" << EOF
# Android Device Information Report

**Generated:** $(date)
**Script Location:** $SCRIPT_DIR
**Device ID:** $DEVICE_ID

EOF
}

# Main information collection
collect_device_info() {
    log_info "Starting comprehensive device information collection..."

    # System Properties
    execute_adb_command "adb shell getprop" "System Properties" "System Properties (Complete)"

    # Filtered Key Properties
    execute_adb_command "adb shell \"getprop | grep -E 'model|version|manufacturer|hardware|platform|revision|serialno|product|brand|board|soc'\"" "Key System Properties" "Key System Properties"

    # CPU Information
    execute_adb_command "adb shell cat /proc/cpuinfo" "CPU Information" "CPU Information"

    # Memory Information
    execute_adb_command "adb shell cat /proc/meminfo" "Memory Information" "Memory Information"

    # Storage Information
    execute_adb_command "adb shell df -h" "Storage Information" "Storage Information"

    # Hardware Features
    execute_adb_command "adb shell pm list features" "Hardware Features" "Hardware Features"

    # Display Properties
    execute_adb_command "adb shell wm size" "Display Size" "Display Size"
    execute_adb_command "adb shell wm density" "Display Density" "Display Density"
    execute_adb_command "adb shell dumpsys display" "Display System Dump" "Display System Information"

    # GPU Information
    execute_adb_command "adb shell cat /proc/driver/gpu" "GPU Driver Information" "GPU Driver Information"
    execute_adb_command "adb shell \"getprop | grep gpu\"" "GPU Properties" "GPU Properties"

    # Audio System
    execute_adb_command "adb shell dumpsys audio" "Audio System" "Audio System Information"

    # Media Capabilities
    execute_adb_command "adb shell dumpsys media.player" "Media Player Information" "Media Player Capabilities"

    # MediaCodec Configuration Files
    execute_adb_command "adb shell ls -la /vendor/etc/media_codecs*.xml" "MediaCodec Config Files" "MediaCodec Configuration Files"
    execute_adb_command "adb shell cat /vendor/etc/media_codecs.xml" "MediaCodec Main Config" "MediaCodec Main Configuration"
    execute_adb_command "adb shell cat /vendor/etc/media_codecs_performance.xml" "MediaCodec Performance Config" "MediaCodec Performance Configuration"

    # Detailed Media Framework Information
    execute_adb_command "adb shell dumpsys media.codec" "MediaCodec Service" "MediaCodec Service Information"
    execute_adb_command "adb shell dumpsys media.extractor" "Media Extractor" "Media Extractor Information"
    execute_adb_command "adb shell dumpsys media.metrics" "Media Metrics" "Media Framework Metrics"

    # Audio Capabilities
    execute_adb_command "adb shell \"getprop | grep audio\"" "Audio Properties" "Audio System Properties"
    execute_adb_command "adb shell cat /proc/asound/cards" "Audio Hardware" "Audio Hardware Information"
    execute_adb_command "adb shell cat /proc/asound/devices" "Audio Devices" "Audio Device List"

    # Video Hardware Acceleration
    execute_adb_command "adb shell \"getprop | grep video\"" "Video Properties" "Video System Properties"
    execute_adb_command "adb shell \"ls -la /dev/video*\"" "Video Devices" "Video Hardware Devices"

    # OpenMAX and Codec Libraries
    execute_adb_command "adb shell \"find /vendor/lib* -name '*omx*' -o -name '*codec*' -o -name '*media*'\"" "Codec Libraries" "Media and Codec Libraries"

    # DRM Capabilities
    execute_adb_command "adb shell dumpsys media.drm" "DRM Information" "Digital Rights Management"

    # Surface Flinger (for video rendering)
    execute_adb_command "adb shell dumpsys SurfaceFlinger" "Surface Flinger" "Surface Flinger Information"

    # USB Configuration
    execute_adb_command "adb shell cat /sys/class/android_usb/android0/state" "USB State" "USB Configuration"
    execute_adb_command "adb shell lsusb" "USB Devices" "USB Devices List"

    # Network Interfaces
    execute_adb_command "adb shell ip addr" "Network Interfaces" "Network Interface Information"

    # System Performance
    execute_adb_command "adb shell top -n 1" "Current Processes" "System Performance Snapshot"

    # Battery Information
    execute_adb_command "adb shell dumpsys battery" "Battery Information" "Battery Status"

    # Thermal Information
    execute_adb_command "adb shell \"find /sys/class/thermal -name 'temp' -exec cat {} \\;\"" "Thermal Sensors" "Thermal Information"

    # Build Information
    execute_adb_command "adb shell \"getprop | grep ro.build\"" "Build Information" "Android Build Information"

    # API Level and Permissions
    execute_adb_command "adb shell getprop ro.build.version.sdk" "API Level" "Android API Level"
    execute_adb_command "adb shell pm list permissions" "System Permissions" "Available System Permissions"

    # Package Information
    execute_adb_command "adb shell pm list packages" "Installed Packages" "Installed Package List"

    # System Services
    execute_adb_command "adb shell service list" "System Services" "System Services List"

    # Kernel Information
    execute_adb_command "adb shell uname -a" "Kernel Information" "Kernel Version"

    # Mount Points
    execute_adb_command "adb shell mount" "Mount Points" "File System Mount Points"

    # Process List
    execute_adb_command "adb shell ps" "Process List" "Running Processes"

    # System Uptime
    execute_adb_command "adb shell uptime" "System Uptime" "System Uptime"

    # Logcat Buffer Sizes
    execute_adb_command "adb logcat -g" "Logcat Buffer Info" "Logcat Buffer Information"
}

# Cleanup function
cleanup() {
    rm -f "$TEMP_LOG"
}

# Main execution
main() {
    log_info "ADB Device Information Collector Started"
    log_info "Output will be saved to: $OUTPUT_FILE"

    check_adb
    wait_for_device
    init_output_file
    collect_device_info
    cleanup

    log_success "Device information collection completed!"
    log_success "Report saved to: $OUTPUT_FILE"

    # Open the file in default editor if possible
    if command -v open &> /dev/null; then
        log_info "Opening report in default application..."
        open "$OUTPUT_FILE"
    fi
}

# Set trap for cleanup on script exit
trap cleanup EXIT

# Execute main function
main "$@"