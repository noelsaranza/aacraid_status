#!/bin/bash

# Define Alert Thresholds
CRIT_LIFETIME=10   # Critical if lifetime remaining is <= 10%
WARN_LIFETIME=20   # Warning if lifetime remaining is <= 20%
CRIT_NAND_BLK=1    # Critical if reallocated NAND blocks >= 1

# Initialize Tracking Variables
FINAL_STATUS=0
OUTPUT_SUMMARY=""
PERFDATA_SUMMARY=""

# Loop Through the 4 Specific Disks
for DISK_ID in 0 1 2 3; do
    # Run the exact smartctl command (without 'less' so it doesn't block Nagios)
    SMART_DATA=$(smartctl -d aacraid,0,0,$DISK_ID -a /dev/sg0 2>/dev/null)

    # Handle missing disk or communication failure
    if [ -z "$SMART_DATA" ]; then
        OUTPUT_SUMMARY="${OUTPUT_SUMMARY}[Disk ${DISK_ID}: UNKNOWN/No Data] "
        [ "$FINAL_STATUS" -lt 3 ] && FINAL_STATUS=3
        continue
    fi

    # Extract and parse the line for Percent_Lifetime_Remain
    LIFETIME_LINE=$(echo "$SMART_DATA" | grep "Percent_Lifetime_Remain")
    if [ -n "$LIFETIME_LINE" ]; then
        # Grab Column 4 (VALUE) from your table layout
        LIFETIME=$(echo "$LIFETIME_LINE" | awk '{print $4}')
    else
        LIFETIME=100
    fi

    # Extract and parse the line for Reallocate_NAND_Blk_Cnt
    NAND_BLK_LINE=$(echo "$SMART_DATA" | grep "Reallocate_NAND_Blk_Cnt")
    if [ -n "$NAND_BLK_LINE" ]; then
        # Grab Column 4 (VALUE) to avoid hyphen column-shifting issues
        NAND_BLK=$(echo "$NAND_BLK_LINE" | awk '{print $4}')
    else
        NAND_BLK=0
    fi

    # Remove any potential leading zeros to prevent bash octal errors (e.g., "062" -> "62")
    LIFETIME=$(echo "$LIFETIME" | sed 's/^0*//')
    NAND_BLK=$(echo "$NAND_BLK" | sed 's/^0*//')
    
    # If stripping zeros emptied the string or hit a non-number, set back to 0
    [[ ! "$LIFETIME" =~ ^[0-9]+$ ]] && LIFETIME=0
    [[ ! "$NAND_BLK" =~ ^[0-9]+$ ]] && NAND_BLK=0

    # Append data to the human-readable summary string
    OUTPUT_SUMMARY="${OUTPUT_SUMMARY}[Disk ${DISK_ID}: Life ${LIFETIME}%, BadBlk ${NAND_BLK}] "

    # Append data to the Nagios Performance Graphing metrics
    PERFDATA_SUMMARY="${PERFDATA_SUMMARY}disk${DISK_ID}_life=${LIFETIME}%;$WARN_LIFETIME;$CRIT_LIFETIME;0;100 disk${DISK_ID}_blk=${NAND_BLK};;;0; "

    # Check severity rules (keeps the worst error status found across all 4 disks)
    if [ "$LIFETIME" -le "$CRIT_LIFETIME" ] || [ "$NAND_BLK" -ge "$CRIT_NAND_BLK" ]; then
        [ "$FINAL_STATUS" -lt 2 ] && FINAL_STATUS=2
    elif [ "$LIFETIME" -le "$WARN_LIFETIME" ]; then
        [ "$FINAL_STATUS" -lt 1 ] && FINAL_STATUS=1
    fi
done

# Map the Final Status to Nagios Headers
case $FINAL_STATUS in
    0) PREFIX="OK" ;;
    1) PREFIX="WARNING" ;;
    2) PREFIX="CRITICAL" ;;
    3) PREFIX="UNKNOWN" ;;
esac

# Print the Final Combined Output and Exit
echo "${PREFIX} - ${OUTPUT_SUMMARY}| ${PERFDATA_SUMMARY}"
exit $FINAL_STATUS

