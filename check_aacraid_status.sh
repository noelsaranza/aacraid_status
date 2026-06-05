#!/bin/bash

# Alert Thresholds
CRIT_LIFETIME=10
WARN_LIFETIME=20
CRIT_NAND_BLK=1

# Status Tracking
FINAL_STATUS=0
OUTPUT_SUMMARY=""

# Check the 4 SSDs
for DISK_ID in 0 1 2 3; do

    SMART_DATA=$(smartctl -d aacraid,0,0,$DISK_ID -a /dev/sg0 2>/dev/null)

    # Handle missing disk data
    if [ -z "$SMART_DATA" ]; then
        OUTPUT_SUMMARY="${OUTPUT_SUMMARY}[Disk ${DISK_ID}: No SMART Data] "
        [ "$FINAL_STATUS" -lt 3 ] && FINAL_STATUS=3
        continue
    fi

    # Device Model
    MODEL=$(echo "$SMART_DATA" | grep "^Device Model:" | cut -d: -f2- | xargs)

    # Serial Number
    SERIAL=$(echo "$SMART_DATA" | grep "^Serial Number:" | cut -d: -f2- | xargs)

    [ -z "$MODEL" ] && MODEL="Unknown"
    [ -z "$SERIAL" ] && SERIAL="Unknown"

    # Lifetime Remaining
    LIFETIME_LINE=$(echo "$SMART_DATA" | grep "Percent_Lifetime_Remain")

    if [ -n "$LIFETIME_LINE" ]; then
        LIFETIME=$(echo "$LIFETIME_LINE" | awk '{print $4}')
    else
        LIFETIME=100
    fi

    # Reallocated NAND Blocks
    NAND_BLK_LINE=$(echo "$SMART_DATA" | grep "Reallocate_NAND_Blk_Cnt")

    if [ -n "$NAND_BLK_LINE" ]; then
        NAND_BLK=$(echo "$NAND_BLK_LINE" | awk '{print $4}')
    else
        NAND_BLK=0
    fi

    # Remove leading zeros
    LIFETIME=$(echo "$LIFETIME" | sed 's/^0*//')
    NAND_BLK=$(echo "$NAND_BLK" | sed 's/^0*//')

    # Validate values
    [[ ! "$LIFETIME" =~ ^[0-9]+$ ]] && LIFETIME=0
    [[ ! "$NAND_BLK" =~ ^[0-9]+$ ]] && NAND_BLK=0

    # Build Output
    OUTPUT_SUMMARY="${OUTPUT_SUMMARY}[Disk ${DISK_ID}: ${MODEL} SN:${SERIAL} Life:${LIFETIME}% BadBlk:${NAND_BLK}] "

    # Status Evaluation
    if [ "$LIFETIME" -le "$CRIT_LIFETIME" ] || [ "$NAND_BLK" -ge "$CRIT_NAND_BLK" ]; then
        [ "$FINAL_STATUS" -lt 2 ] && FINAL_STATUS=2
    elif [ "$LIFETIME" -le "$WARN_LIFETIME" ]; then
        [ "$FINAL_STATUS" -lt 1 ] && FINAL_STATUS=1
    fi

done

# Status Prefix
case $FINAL_STATUS in
    0) PREFIX="OK" ;;
    1) PREFIX="WARNING" ;;
    2) PREFIX="CRITICAL" ;;
    3) PREFIX="UNKNOWN" ;;
esac

echo "${PREFIX} - ${OUTPUT_SUMMARY}"
exit $FINAL_STATUS
