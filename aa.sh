#!/usr/bin/env bash

# Global configuration
EXEC_NAME="$0 $*"
ROOT_OPTS=("--chaotic-install" "--chaotic-purge" "--chaotic-revert")

# Logging and output helpers
_tput() {
    tput "$@" 2>/dev/null || return 0
}

_term_cols() {
    local cols
    cols=$(tput cols 2>/dev/null)
    echo "${cols:-80}"
}

vertL="$(printf '=%.0s' $(seq 1 "$(_term_cols)"))"

box_me() {
    local s="$*"
    _tput setaf 3
    echo " ═${s//?/═}"
    echo "║$s ║"
    echo " ═${s//?/═}"
    _tput sgr0
}

print_log() {
    local status="$1"
    local message="$2"
    echo -e "[\e[34mAUR\e[0m] ${status}: ${message}"
}

# System check functions
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Error: [ $EXEC_NAME ] must be run as root!"
        exit 1
    fi
}

check_ping() {
    if ! ping -q -c 1 -W 1 8.8.8.8 >/dev/null; then
        box_me "Error: No internet connection."
        exit 1
    fi
}

pkg_installed() {
    pacman -Qq "$1" &>/dev/null
}

# Chaotic-AUR management logic
write_chaotic_aur() {
    local is_chaotic
    is_chaotic=$(grep -c "chaotic-aur" /etc/pacman.conf 2>/dev/null)

    if [ "$1" == "append" ]; then
        box_me "Appending Chaotic AUR"
        if [ "$is_chaotic" -gt 0 ]; then
            echo "Chaotic-AUR already in pacman.conf..."
        else
            echo "Appending Chaotic-AUR in pacman.conf..."
            echo -e "\r\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >>/etc/pacman.conf
        fi
    elif [ "$1" == "remove" ]; then
        box_me "Removing Chaotic AUR from pacman.conf"
        if grep -q 'chaotic-aur' /etc/pacman.conf; then
            echo "Removing Chaotic-AUR from pacman.conf..."
            sed -i '/chaotic-aur/d' /etc/pacman.conf
            sed -i '/chaotic-mirrorlist/d' /etc/pacman.conf
        else
            echo "Chaotic-AUR is not present in pacman.conf..."
        fi
    fi
}

check_chaotic_integrity() {
    if ! grep -q "chaotic-aur" /etc/pacman.conf 2>/dev/null; then
        return 1
    fi
    if ! pacman-key -l | grep -q 3056513887B78AEB; then
        return 1
    fi
    if ! pkg_installed chaotic-keyring || ! pkg_installed chaotic-mirrorlist; then
        return 1
    fi
    return 0
}

install_chaotic() {
    handle_error() {
        _tput setaf 1
        echo "ERROR :: Failed to install Chaotic AUR"
        _tput sgr0
        echo "WARNING :: Reverting changes..."
        { purge_chaotic && echo "Reverted successfully"; } || echo "Failed to revert"
        exit 1
    }

    box_me "Installing the key"
    pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com || handle_error
    pacman-key --lsign-key 3056513887B78AEB || handle_error

    box_me "Downloading the keyring"
    pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' || handle_error

    box_me "Downloading the mirrorlist"
    pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst' || handle_error

    write_chaotic_aur "append" || handle_error

    box_me "Refreshing the mirrorlists"
    pacman -Sy || handle_error

    box_me "Chaotic-AUR has been successfully installed!"
}

purge_chaotic() {
    if pacman-key -l | grep -q 3056513887B78AEB; then
        box_me "Deleting the key"
        pacman-key --delete 3056513887B78AEB
    fi

    if pkg_installed chaotic-keyring; then
        box_me "Uninstalling the keyring"
        pacman -Rns --noconfirm chaotic-keyring
    fi

    if pkg_installed chaotic-mirrorlist; then
        box_me "Uninstalling the mirrorlist"
        pacman -Rns --noconfirm chaotic-mirrorlist
    fi

    write_chaotic_aur "remove"

    box_me "Refreshing the mirrorlists"
    pacman -Sy

    box_me "Chaotic-AUR has been successfully purged"
}

revert_chaotic() {
    local to_be_reverted
    to_be_reverted="$(pacman -Qmq | grep chaotic-aur)"

    box_me "Revert Chaotic AUR to standard AUR Packages"

    if [[ -z "${to_be_reverted// /}" ]]; then
        echo "No chaotic-aur package detected. You are good to go!"
        exit 0
    fi

    echo -e "The following packages will be affected:\n$to_be_reverted"
    read -p "Proceed to reinstall these packages from AUR? [Y/n] " ans

    if [[ "$ans" =~ ^[Nn]$ ]]; then
        box_me "Aborting..."
        exit 0
    fi

    for chaoticPackage in $to_be_reverted; do
        convertedPackage="$(echo "$chaoticPackage" | sed 's/chaotic-aur/aur/')"
        if [ "$(pacman -Qs "$convertedPackage")" == "$convertedPackage" ]; then
            box_me "Reinstalling $convertedPackage..."
            pacman -S --noconfirm "$convertedPackage"
        else
            box_me "Could not find $convertedPackage in the AUR."
        fi
    done

    box_me "Your Chaotic-AUR packages have been reinstalled!"
}

fresh_chaotic_prompt() {
    clear
    echo "Detected: Arch Linux"
    _tput setaf 2
    echo "Would you like to add Chaotic AUR to your mirror list?"
    _tput sgr0
    cat <<'CHAOS'
Chaotic AUR provides prebuilt and precompiled packages,
which can make installing packages from Arch faster.
CHAOS
    printf '%s\n' "${vertL}"
    _tput setaf 6
    echo "About Chaotic AUR:"
    _tput sgr0
    cat <<'CHAOS'
Most packages available in this repo are automatically built from their respective AUR source package.
For more information, visit: https://aur.chaotic.cx/
CHAOS
    printf '%s\n' "${vertL}"
    echo

    read -p "Type 'yes' to continue [default: No]: " add_chaotic
    if [ "${add_chaotic}" != "yes" ]; then
        _tput setaf 1
        echo "Skipping Chaotic AUR setup."
        _tput sgr0
        exit 0
    fi
}

# Helper installation logic (non-root)
install_aur_helper() {
    local helper="${1:-yay-bin}"

    if [ "$EUID" -eq 0 ]; then
        print_log "Error" "AUR helpers must NOT be installed as root. Run without sudo."
        exit 1
    fi

    if pkg_installed "${helper}"; then
        if "${helper}" --version &>/dev/null; then
            print_log "Detected" "${helper} is already installed and working."
            exit 0
        else
            print_log "Warning" "Detected '${helper}' is not working properly. Reinstalling..."
        fi
    fi

    local clone_dir="$HOME/Clone"
    if [ -d "${clone_dir}" ]; then
        print_log "Status" "Cleaning existing ${clone_dir}/${helper} directory..."
        rm -rf "${clone_dir}/${helper}"
    else
        mkdir -p "${clone_dir}"
        echo -e "[Desktop Entry]\nIcon=default-folder-git" >"${clone_dir}/.directory"
        print_log "Status" "Created ${clone_dir} directory..."
    fi

    if ! pkg_installed git; then
        print_log "Error" "Missing dependency 'git'. Please install git first (sudo pacman -S git)."
        exit 1
    fi

    print_log "Status" "Cloning https://aur.archlinux.org/${helper}.git..."
    if ! git clone "https://aur.archlinux.org/${helper}.git" "${clone_dir}/${helper}"; then
        print_log "Error" "Failed to clone repository for ${helper}."
        exit 1
    fi

    cd "${clone_dir}/${helper}" || exit 1

    if makepkg --noconfirm -si; then
        print_log "Success" "Successfully installed ${helper}!"
        exit 0
    else
        print_log "Error" "${helper} installation failed."
        exit 1
    fi
}

# Main routing logic
if ! command -v pacman >/dev/null 2>&1; then
    box_me "Error: pacman not detected"
    exit 1
fi

for option in "${ROOT_OPTS[@]}"; do
    if [ "$1" == "$option" ]; then
        check_ping
        check_root
        break
    fi
done

case "$1" in
--chaotic-install)
    if [ "$2" == "fresh" ]; then fresh_chaotic_prompt; fi
    if check_chaotic_integrity >/dev/null; then
        read -p "Chaotic AUR already installed. Reinstall? [y/N] " ans
        if [[ ! "$ans" =~ ^[Yy]$ ]]; then
            echo "Operation Cancelled."
            exit 0
        fi
    fi
    install_chaotic
    ;;
--chaotic-purge)
    purge_chaotic
    revert_chaotic
    ;;
--chaotic-revert)
    revert_chaotic
    ;;
--helper)
    install_aur_helper "$2"
    ;;
*)
    cat <<HELP
Usage: $0 [option]

Chaotic-AUR Options (requires root/sudo):
    --chaotic-install [fresh]  Install Chaotic-AUR ('fresh' prompts for confirmation)
    --chaotic-purge            Uninstall Chaotic-AUR and revert packages
    --chaotic-revert           Reinstall orphaned Chaotic-AUR packages from standard AUR

AUR Helper Options (do NOT run as root/sudo):
    --helper [name]            Install an AUR helper (default: yay-bin, e.g. yay, paru)
HELP
    ;;
esac
