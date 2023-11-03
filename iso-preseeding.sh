#!/usr/bin/env bash

if ! source log_functions.sh; then
    echo "Could not source log_functions.sh"
    exit 1
fi

usage() {
    cat << EOF

Usage: ./$(basename "${0}") [OPTIONS]

DESCRIPTION:
    Customize Debian Iso with a preseed and grub config for automatic the installation.

OPTIONS:
    -i, --iso <original_iso>
    -p, --preseed <preseed file>
    -g, --grub-file <grub config file>
    -t, --txt-file <txt config file>
    -d, --disk <disk to write to>   E.g.: sda
EOF
}

rootAccount() {
    log_info "Setting root account"

    initialRootPassword=""
    selectionRootPassword="password"

    while [[ "${initialRootPassword}" != "${selectionRootPassword}" ]]; do
        printf "\nEnter password for root: "
        read -r -s initialRootPassword
        printf "\nConfirm: "
        read -r -s selectionRootPassword
    done

    selectionRootPassword="$(mkpasswd "${selectionRootPassword}" -m sha-512)"

    log_ok "DONE"
}

userAccount() {
    log_info "Setting user account"

    userName=""

    while [ -z "${userName}" ]; do
        printf "Enter name for the local user: "
        read -r userName
    done

    initialUserPassword=""
    selectionUserPassword="password"

    while [[ "${initialUserPassword}" != "${selectionUserPassword}" ]]; do
        printf "\nEnter password for %s: " "${userName}"
        read -r -s initialUserPassword
        printf "\nConfirm: "
        read -r -s selectionUserPassword
    done

    selectionUserPassword="$(mkpasswd "${selectionUserPassword}" -m sha-512)"

    log_ok "DONE"
}

decompress_image() {
    log_info "Decompress Image"

    if ! command -v 7z 1> /dev/null; then
        echo "7z command not found. Please install it."
        exit 2
    fi

    7z x -o"${tempIso}" "${originalIso}" || exit 2

    log_ok "DONE"
}

preseedIso() {
    log_info "Preseeding the Iso"

    mkdir "${tempIso}/preseed"
    cp "${preseedFile}" "${tempIso}/preseed/preseed.cfg"

    sed -i "s|ROOTPASSWORD|${selectionRootPassword}|" "${tempIso}/preseed/preseed.cfg"

    sed -i "s|USERNAME|${userName}|g" "${tempIso}/preseed/preseed.cfg"
    sed -i "s|USERPASSWORD|${selectionUserPassword}|" "${tempIso}/preseed/preseed.cfg"

    log_ok "DONE"
}

configureGRUB() {
    log_info "Configuring Grub"
    
    cp "${grubFile}" "${tempIso}/boot/grub/grub.cfg"
    cp "${txtFile}" "${tempIso}/isolinux/txt.cfg"

    log_ok "DONE"
}

regenerateMD5() {
    log_info "Regenerating MD5SUM"

    pushd "${tempIso}" || exit 2
    chmod +w md5sum.txt
    find . -type f ! -name "md5sum.txt" -exec md5sum {} \; > md5sum.txt
    chmod -w md5sum.txt
    popd || exit 2
    
    log_ok "DONE"
}

createIso() {
    log_info "Creating the Iso"

    if ! command -v xorriso 1> /dev/null; then
        echo "xorriso command not found. Please install it."
        exit 2
    fi

    xorrisoOptions="$(xorriso -indev "${originalIso}" -report_el_torito as_mkisofs 2> /dev/null | grep --invert-match -- "-V" | tr '\n' ' ')"
    eval xorriso -as mkisofs "${xorrisoOptions}" -V "Debian" -o "${nameIso}" "${tempIso}"

    log_ok "DONE"
}

cleanUp() {
    log_info "Cleaning up"

    chmod +w -R "${tempIso}"
    rm --recursive --force "${tempIso}"
    rm --force "${nameIso}"

    log_ok "DONE"
}

writingToDisk() {
    log_info "Writing ${nameIso} to ${writeDisk}"

    sudo umount /dev/sda* 2> /dev/null
    sudo dd if="${nameIso}" of="/dev/${writeDisk}" status=progress

    log_ok "DONE"
}

if [[ $# -eq 0 ]]; then
    echo "No option provided."
    usage
    exit 1
fi

# Gather options
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

        -g | --grub-file)
            if [[ -z "${2-}" || ! -e "${2}" ]]; then
                usage
                exit 1
            fi
            shift
            grubFile="${1}"
            ;;

        -t | --txt-file)
            if [[ -z "${2-}" || ! -e "${2}" ]]; then
                usage
                exit 1
            fi
            shift
            txtFile="${1}"
            ;;

        -d | --disk)
            if [[ -z "${2-}" ]]; then
                usage
                exit 1
            fi
            shift
            writeDisk="${1}"
            ;;


        *)
            echo "Invalid option: ${1}"
            usage
            exit 1
            ;;
    esac
    shift
done

# Check if a preseed file was mentioned
if [[ -z "${originalIso}" ]]; then
    log_error "ISO file not specified"
    usage
    exit 1
fi

# Variables
nameIso="preseed-$(basename "${originalIso}")"
tempIso="$(mktemp -d)"
[[ -z "${preseedFile}" ]] && preseedFile="preseed.cfg"
[[ -z "${grubFile}" ]] && grubFile="grub.cfg"
[[ -z "${txtFile}" ]] && txtFile="txt.cfg"

# Loading functions
rootAccount
userAccount
decompress_image
preseedIso
configureGRUB
regenerateMD5
createIso
[[ -n "${writeDisk}" ]] && writingToDisk
cleanUp
