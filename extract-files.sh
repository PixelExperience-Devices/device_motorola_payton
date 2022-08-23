#!/bin/bash
#
# Copyright (C) 2016 The CyanogenMod Project
# Copyright (C) 2017-2020 The LineageOS Project
# Copyright (C) 2018-2020 The PixelExperience Project
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

export DEVICE=payton
export VENDOR=motorola

# Load extract_utils and do some sanity checks
MY_DIR="${BASH_SOURCE%/*}"
if [[ ! -d "${MY_DIR}" ]]; then MY_DIR="${PWD}"; fi

ANDROID_ROOT="${MY_DIR}/../../.."

HELPER="${ANDROID_ROOT}/tools/extract-utils/extract_utils.sh"
if [ ! -f "${HELPER}" ]; then
    echo "Unable to find helper script at ${HELPER}"
    exit 1
fi
source "${HELPER}"

# Default to sanitizing the vendor folder before extraction
CLEAN_VENDOR=true

ONLY_COMMON=
ONLY_TARGET=
KANG=
SECTION=

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        --only-common )
                ONLY_COMMON=true
                ;;
        --only-target )
                ONLY_TARGET=true
                ;;
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

function blob_fixup() {
    case "${1}" in
        # Load ZAF configs from vendor
        vendor/lib/libzaf_core.so)
            sed -i -e 's|/system/etc/zaf|/vendor/etc/zaf|g' "${2}"
            ;;
        # Add uhid group for fingerprint service
        vendor/etc/init/android.hardware.biometrics.fingerprint@2.1-service.rc)
            sed -i -e 's|system input|system uhid input|g' "${2}"
            ;;
        # Fix camera recording
        vendor/lib/libmmcamera2_pproc_modules.so)
            sed -i -e 's|ro.product.manufacturer|ro.product.nopefacturer|g' "${2}"
            ;;
        # Fix xml version
        product/etc/permissions/vendor.qti.hardware.data.connection-V1.0-java.xml | product/etc/permissions/vendor.qti.hardware.data.connection-V1.1-java.xml)
            sed -i 's|xml version="2.0"|xml version="1.0"|g' "${2}"
            ;;
        # Fix missing symbols
        product/lib64/lib-imscamera.so | product/lib64/lib-imsvideocodec.so | product/lib/lib-imscamera.so | product/lib/lib-imsvideocodec.so)
            for LIBGUI_SHIM in $(grep -L "libgui_shim.so" "${2}"); do
                "${PATCHELF}" --add-needed "libgui_shim.so" "${LIBGUI_SHIM}"
            done
            ;;
        vendor/lib/libmot_gpu_mapper.so)
            for LIBGUI_SHIM in $(grep -L "libgui_shim_vendor.so" "${2}"); do
                "${PATCHELF}" --add-needed "libgui_shim_vendor.so" "${LIBGUI_SHIM}"
            done
            ;;
        # Load wrapped shim
        vendor/lib64/libmdmcutback.so)
            sed -i "s|libqsap_sdk.so|libqsapshim.so|g" "${2}"
            ;;
        # Fix missing symbols
        vendor/lib64/libril-qc-hal-qmi.so)
            for  LIBCUTILS_SHIM in $(grep -L "libcutils_shim.so" "${2}"); do
                "${PATCHELF}" --add-needed "libcutils_shim.so" "$LIBCUTILS_SHIM"
            done
            ;;
        # memset shim
        vendor/bin/charge_only_mode)
            for  LIBMEMSET_SHIM in $(grep -L "libmemset_shim.so" "${2}"); do
                "${PATCHELF}" --add-needed "libmemset_shim.so" "$LIBMEMSET_SHIM"
            done
            ;;
       # Patch qcril to support only RadioConfig::1.0 interface
        vendor/lib64/libril-qc-hal-qmi.so)
            patchelf --replace-needed "android.hardware.radio.config@1.1.so" "android.hardware.radio.config@1.1_shim.so" "${2}"
            ;;
        vendor/lib64/android.hardware.radio.config@1.1_shim.so)
            patchelf --set-soname "android.hardware.radio.config@1.1_shim.so" "${2}"
            sed -i -e 's|android.hardware.radio.config@1.1::IRadioConfig\x00|android.hardware.radio.config@1.0::IRadioConfig\x00|g' "${2}" 
            ;;
        # Use VNDK 32 libhidlbase
        vendor/lib64/com.fingerprints.extension@1.0_vendor.so)
            "${PATCHELF_0_8}" --remove-needed "libhidlbase.so" "${2}"
            sed -i "s/libhidltransport.so/libhidlbase-v32.so\x00/" "${2}"
            ;;
    esac
}

if [ -z "${ONLY_TARGET}" ]; then
    # Initialize the helper 
    setup_vendor "$DEVICE" "$VENDOR" "$ANDROID_ROOT" true "$CLEAN_VENDOR"

    extract "${MY_DIR}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

if [ -z "${ONLY_COMMON}" ] && [ -s "${MY_DIR}/../${DEVICE}/proprietary-files.txt" ]; then
    # Reinitialize the helper for device
    source "${MY_DIR}/../${DEVICE}/extract-files.sh"
    setup_vendor "${DEVICE}" "${VENDOR}" "${ANDROID_ROOT}" false "${CLEAN_VENDOR}"

    extract "${MY_DIR}/../${DEVICE}/proprietary-files.txt" "${SRC}" "${KANG}" --section "${SECTION}"
fi

"${MY_DIR}/../${DEVICE}/setup-makefiles.sh"
