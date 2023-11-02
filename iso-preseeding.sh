#!/usr/bin/env bash

if ! source log_functions.sh; then
    echo "Could not source log_functions.sh"
    exit 1
fi

usage() {
    cat << EOF

Usage: $(basename "${0}")

DESCRIPTION:
    Include preseed files in a Debian ISO.

OPTIONS:
    -i, --iso <original_iso>
    -p, --preseed <preseed file>
EOF
}

decompress_image() {
    log_info "Decompress Image"
    if ! command -v 7z 1> /dev/null; then
        echo "7z command not found. Please install it."
        exit 2
    fi

    tempISO="$(mktemp -d)"
    7z x -o"${tempISO}" "${originalIso}" || exit 2
    log_ok "DONE"
}

preseedISO() {
    log_info "Preseeding the ISO"
    chmod +w -R "${tempISO}/install.amd/"
    gunzip "${tempISO}/install.amd/initrd.gz"
    echo "${preseedFile}" | cpio -H newc -o -A -F "${tempISO}/install.amd/initrd"
    gzip "${tempISO}/install.amd/initrd"
    chmod -w -R "${tempISO}/install.amd/"
    log_ok "DONE"
}

regenerateMD5() {
    log_info "Regenerating MD5SUM"
    pushd "${tempISO}" || exit 2
    chmod +w md5sum.txt
    find . -type f ! -name "md5sum.txt" -exec md5sum {} \; > md5sum.txt
    chmod -w md5sum.txt
    popd || exit 2
    log_ok "DONE"
}

createISO() {
    log_info "Creating the ISO"
    if ! command -v xorriso 1> /dev/null; then
        echo "xorriso command not found. Please install it."
        exit 2
    fi

    xorrisoOptions="$(xorriso -indev "${originalIso}" -report_el_torito as_mkisofs 2> /dev/null | grep --invert-match -- "-V" | tr '\n' ' ')"
    eval xorriso -as mkisofs "${xorrisoOptions}" -V "Debian" -o "preseed-$(basename "${originalIso}")" "${tempISO}"

    log_ok "DONE"
}

cleanUp() {
    log_info "Cleaning up"
    chmod +w -R "${tempISO}"
    rm --recursive --force "${tempISO}"
    log_ok "DONE"
}

if [[ $# -eq 0 ]]; then
    echo "No option provided."
    usage
    exit 1
fi

while [[ ! $# -eq 0 ]]; do
    case "${1}" in
        -h | --help)
            usage
            exit 0
            ;;

        -i | --iso)
            if [[ -z "${2-}" || ! -e "${2}" ]]; then
                usage
                exit 1
            fi
            shift
            originalIso="${1}"
            ;;

        -p | --preseed)
            if [[ -z "${2-}" || ! -e "${2}" ]]; then
                usage
                exit 1
            fi
            shift
            preseedFile="${1}"
            ;;

        *)
            echo "Invalid option: ${1}"
            usage
            exit 1
            ;;
    esac
    shift
done

if [[ -z "${preseedFile}" ]]; then
    log_error "Error. Preseed file not specified"
    usage
    exit 1
fi

decompress_image
preseedISO
regenerateMD5
createISO
cleanUp
