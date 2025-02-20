#!/bin/bash
#
# Copyright (C) 2018-2020 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

DEVICE_COMMON=universal8890-common
VENDOR=samsung

# Load extractutils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "$MY_DIR" ]]; then MY_DIR="$PWD"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --no-cleanup )
                CLEAN_VENDOR=false
                ;;
        -k | --kang )
                KANG="--kang"
                ;;
        -s | --section )
                SECTION="${2}"; shift
                CLEAN_VENDOR=false
                ;;
        * )
                SRC="${1}"
                ;;
    esac
    shift
done

if [ -z "${SRC}" ]; then
    SRC="adb"
fi

# Initialize the helper
setup_vendor "${DEVICE_COMMON}" "${VENDOR}" "${ANDROID_ROOT}" true "${CLEAN_VENDOR}"

extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"

# Fix proprietary blobs
BLOB_ROOT="$ANDROID_ROOT"/vendor/"$VENDOR"/"$DEVICE_COMMON"/proprietary

sed -i -z "s/    seclabel u:r:gpsd:s0\n//" $BLOB_ROOT/vendor/etc/init/init.gps.rc
sed -i -z "s/    setprop wifi.interface wlan0\n\n/    setprop wifi.interface wlan0\n    setprop wifi.concurrent.interface swlan0\n\n/" $BLOB_ROOT/vendor/etc/init/wifi_sec.rc

# replace SSLv3_client_method with SSLv23_method
sed -i "s/SSLv3_client_method/SSLv23_method\x00\x00\x00\x00\x00\x00/" $BLOB_ROOT/vendor/bin/hw/gpsd

# Vendor separation
sed -i "s|system/etc|vendor/etc|g" $BLOB_ROOT/vendor/lib/libfloatingfeature.so
sed -i "s|system/etc|vendor/etc|g" $BLOB_ROOT/vendor/lib64/libfloatingfeature.so

# RIL patches
xxd -p -c0 $BLOB_ROOT/proprietary/vendor/lib64/libsec-ril-dsds.so | sed "s/600e40f9820c8052e10315aae30314aa/600e40f9820c8052e10315aa030080d2/g" | xxd -r -p > $BLOB_ROOT/proprietary/vendor/lib64/libsec-ril-dsds.so.patched
mv $BLOB_ROOT/proprietary/vendor/lib64/libsec-ril-dsds.so.patched $BLOB_ROOT/proprietary/vendor/lib64/libsec-ril-dsds.so

xxd -p -c0 $BLOB_ROOT/proprietary/vendor/lib64/libsec-ril.so | sed "s/600e40f9820c8052e10315aae30314aa/600e40f9820c8052e10315aa030080d2/g" | xxd -r -p > $BLOB_ROOT/proprietary/vendor/lib64/libsec-ril.so.patched
mv $BLOB_ROOT/proprietary/vendor/lib64/libsec-ril.so.patched $BLOB_ROOT/proprietary/vendor/lib64/libsec-ril.so


# hidlbase legacy hack
"${PATCHELF}" --replace-needed libhidlbase.so libhidlbase-v32.so $BLOB_ROOT/vendor/lib/vendor.samsung.hardware.gnss@1.0.so
"${PATCHELF}" --replace-needed libhidlbase.so libhidlbase-v32.so $BLOB_ROOT/vendor/lib64/vendor.samsung.hardware.gnss@1.0.so

# Replace protobuf with vndk29 compat libs for specified libs
"${PATCHELF}" --replace-needed libprotobuf-cpp-lite.so libprotobuf-cpp-lite-v29.so $BLOB_ROOT/vendor/lib/libwvhidl.so
"${PATCHELF}" --replace-needed libprotobuf-cpp-lite.so libprotobuf-cpp-lite-v29.so $BLOB_ROOT/vendor/lib/mediadrm/libwvdrmengine.so

# Remove wpa_supplicant service from wifi.rc
sed -i "41,48d" $BLOB_ROOT/vendor/etc/init/wifi_sec.rc

# Replace libvndsecril-client with libsecril-client
"${PATCHELF}" --replace-needed libvndsecril-client.so libsecril-client.so $BLOB_ROOT/vendor/lib/libwrappergps.so
"${PATCHELF}" --replace-needed libvndsecril-client.so libsecril-client.so $BLOB_ROOT/vendor/lib64/libwrappergps.so

"${MY_DIR}/setup-makefiles.sh"
