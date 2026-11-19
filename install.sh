#!/usr/bin/env bash
# Kyocera FS-1020MFP / FS-1025MFP / FS-1040 / FS-1060DN / FS-1120MFP / FS-1125MFP
# driver installer for CUPS. Distributed under GPLv2 (see LICENSE.txt).
#
# Works two ways:
#  - install.sh, run from a checkout of the repository, takes the driver files
#    from the directory it is in;
#  - kyocera_ppds_installer.sh, made by build_installer.sh, is this script with
#    the driver files appended, so it can be downloaded and run on its own.
#
# Setting DESTDIR installs into a staging directory instead of the system:
# root is not needed, and no packages are installed and no printers changed.

VERSION="1.1.0"
PPD_FILES=(
    Kyocera_FS-1020MFPGDI.ppd
    Kyocera_FS-1025MFPGDI.ppd
    Kyocera_FS-1040GDI.ppd
    Kyocera_FS-1060DNGDI.ppd
    Kyocera_FS-1120MFPGDI.ppd
    Kyocera_FS-1125MFPGDI.ppd
)
WRAPPER_MARK="kyocera-ppd-installer wrapper"
SELF=${BASH_SOURCE[0]}

usage() {
    cat << EOF
Kyocera PPD installer v.$VERSION

Installs CUPS drivers (English only) for Kyocera FS-1020MFP, FS-1025MFP,
FS-1040, FS-1060DN, FS-1120MFP and FS-1125MFP on 32- and 64-bit x86 Linux.

Usage: $(basename "$SELF") [option]

  (no option)    install, after asking for confirmation
  -y, --yes      install without asking (also answers yes to installing
                 missing packages)
  --uninstall    remove the drivers
  --check        show what is installed and what is wrong, change nothing
  -h, --help     show this help

Installer by Maxim Norin (https://mnorin.com, Mail: mnorin@mnorin.com).
Wrapper by tr0n (sorry, don't have contact)
EOF
}

say() { echo "$*"; }
warn() { echo "WARNING: $*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

confirm() { # question
    [ "$ASSUME_YES" == 1 ] && return 0
    local reply
    read -r -p "$1 [y/N]: " reply || reply=
    case $reply in
        [yY]*) return 0 ;;
    esac
    return 1
}

check_root() {
    if [ -z "$DESTDIR" ] && [ "$EUID" != 0 ]; then
        die "Not sufficient rights. Use \"sudo $SELF\" or start as root."
    fi
}

check_arch() {
    case $(uname -m) in
        x86_64 | amd64 | i?86) ;;
        *) die "Kyocera made these drivers only for x86 PCs (32 and 64 bit); this machine is $(uname -m)." ;;
    esac
    BITS=$(getconf LONG_BIT)
}

# Sets FILTER_DIR and MODEL_DIR to the directories CUPS uses on this system.
find_cups_dirs() {
    local serverbin datadir dir
    serverbin=$(cups-config --serverbin 2> /dev/null)
    datadir=$(cups-config --datadir 2> /dev/null)
    MODEL_DIR=${datadir:-/usr/share/cups}/model/Kyocera
    FILTER_DIR=
    for dir in "$serverbin" /usr/lib/cups /usr/libexec/cups /usr/lib64/cups /usr/lib32/cups; do
        if [ -n "$dir" ] && [ -d "$dir/filter" ]; then
            FILTER_DIR=$dir/filter
            return 0
        fi
    done
    if [ -n "$DESTDIR" ]; then
        FILTER_DIR=/usr/lib/cups/filter
        return 0
    fi
    return 1
}

find_package_manager() {
    local pm
    for pm in apt-get dnf yum zypper pacman; do
        if command -v $pm > /dev/null; then
            PM=$pm
            return 0
        fi
    done
    PM=
    return 1
}

pm_install() { # package...
    case $PM in
        apt-get) apt-get update -qq && apt-get install -y "$@" ;;
        dnf | yum) $PM install -y "$@" ;;
        zypper) zypper --non-interactive install "$@" ;;
        pacman) pacman -S --needed --noconfirm "$@" ;;
        *) return 1 ;;
    esac
}

# Packages with the libraries the filter binary links against
# (libcups.so.2 and libcupsimage.so.2).
install_cups_libraries() {
    case $PM in
        # Newer Debian and Ubuntu releases renamed the packages with a "t64" suffix.
        apt-get) pm_install libcups2t64 libcupsimage2t64 2> /dev/null || pm_install libcups2 libcupsimage2 ;;
        dnf | yum) pm_install cups-libs ;;
        zypper) pm_install libcups2 libcupsimage2 ;;
        pacman) pm_install libcups ;;
        *) return 1 ;;
    esac
}

file_owner() { # path; prints the package the file belongs to, if any
    if command -v dpkg > /dev/null; then
        dpkg -S "$1" 2> /dev/null | head -1 | cut -d: -f1
    elif command -v rpm > /dev/null; then
        rpm -qf "$1" 2> /dev/null | grep -v 'not owned'
    elif command -v pacman > /dev/null; then
        pacman -Qoq "$1" 2> /dev/null
    fi
}

missing_libraries() { # binary
    ldd "$1" 2> /dev/null | awk '/not found/ {print $1}'
}

# Every version of this installer's wrapper calls rastertokpsl-bin; since
# 1.1.0 it also carries WRAPPER_MARK.
is_our_wrapper() { # path
    [ -f "$1" ] && grep -q 'rastertokpsl-bin' "$1"
}

is_current_wrapper() { # path
    [ -f "$1" ] && grep -q "$WRAPPER_MARK" "$1"
}

# Prints "printer-name ppd-file" for each CUPS printer that drives one of the
# supported models with Kyocera's rastertokpsl filter.
kpsl_printers() {
    local ppd product
    for ppd in /etc/cups/ppd/*.ppd; do
        [ -r "$ppd" ] || continue
        grep -q 'rastertokpsl' "$ppd" || continue
        product=$(sed -n 's/^\*Product: *"(\(.*\))".*/\1/p' "$ppd" | head -1)
        if [ -n "$product" ] && [[ " ${PPD_FILES[*]} " == *" Kyocera_${product}GDI.ppd "* ]]; then
            echo "$(basename "$ppd" .ppd) Kyocera_${product}GDI.ppd"
        else
            echo "$(basename "$ppd" .ppd) -"
        fi
    done
}

cups_running() {
    command -v lpstat > /dev/null && LC_ALL=C lpstat -r 2> /dev/null | grep -q 'is running'
}

# Other PPD files for the same printers, e.g. from Kyocera's own driver
# package. They show up as duplicate drivers when a printer is added.
other_kpsl_ppds() {
    local dir
    for dir in /usr/share/ppd /usr/local/share/ppd /opt/share/ppd "${MODEL_DIR%/Kyocera}"; do
        [ -d "$DESTDIR$dir" ] || continue
        grep -rlZ --include='*.ppd' --include='*.PPD' 'rastertokpsl' "$DESTDIR$dir" 2> /dev/null |
            while IFS= read -r -d '' f; do
                [ "$(dirname "$f")" == "$DESTDIR$MODEL_DIR" ] || echo "${f#"$DESTDIR"}"
            done
    done
}

# Unpacks the driver files into the directory given, or checks that they are
# next to this script when it is run from a checkout.
get_driver_files() { # destination
    local line f
    line=$(grep -a -n -m 1 '^__PAYLOAD_BELOW__$' "$SELF" | cut -d: -f1)
    if [ -n "$line" ]; then
        if ! tail -n +$((line + 1)) "$SELF" | base64 -d | tar -xz -C "$1"; then
            die "Could not unpack the driver files. The installer may be damaged; download it again."
        fi
        SRC_DIR=$1
    else
        SRC_DIR=$(cd "$(dirname "$SELF")" && pwd)
    fi
    for f in "${PPD_FILES[@]}" rastertokpsl_32 rastertokpsl_64 rastertokpsl_wrapper; do
        [ -f "$SRC_DIR/$f" ] || die "Driver file $f is missing from $SRC_DIR."
    done
}

# The filter binary prints a KPSL job header even without any pages, so
# running it on empty input shows whether it can run at all.
self_test() {
    local out
    out=$(PPD="$DESTDIR$MODEL_DIR/Kyocera_FS-1025MFPGDI.ppd" "$DESTDIR$FILTER_DIR/rastertokpsl" 1 test test 1 "" < /dev/null 2> /dev/null | head -c 4)
    [ "$out" == "LSPK" ]
}

install_drivers() {
    local tmp existing owner missing name ppd failed=0

    check_root
    check_arch

    if ! find_cups_dirs; then
        find_package_manager || die "CUPS is not installed. Install it with your package manager and run this installer again."
        confirm "CUPS is not installed. Install it now with $PM?" || die "CUPS is needed. Install it and run this installer again."
        pm_install cups || die "Could not install CUPS."
        find_cups_dirs || die "CUPS was installed, but its filter directory was not found."
    fi

    tmp=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmp"' EXIT
    get_driver_files "$tmp"

    say "Installing..."

    existing=$DESTDIR$FILTER_DIR/rastertokpsl
    if [ -e "$existing" ] && is_our_wrapper "$existing"; then
        is_current_wrapper "$existing" || say "Upgrading the drivers installed by an earlier version of this installer."
    elif [ -e "$existing" ]; then
        owner=$(file_owner "$FILTER_DIR/rastertokpsl")
        if [ -n "$owner" ] && [ -z "$DESTDIR" ]; then
            warn "$FILTER_DIR/rastertokpsl belongs to the package \"$owner\" (probably Kyocera's own driver)."
            warn "It is replaced now, but updating or removing that package will undo this."
            warn "Remove that package and run this installer again to avoid that."
        else
            say "Replacing an older rastertokpsl filter, which fails on jobs with long names."
        fi
    fi

    # CUPS refuses to run filters that are writable by group or others,
    # so set the permissions explicitly instead of relying on umask.
    mkdir -p "$DESTDIR$MODEL_DIR" "$DESTDIR$FILTER_DIR" &&
        install -m 644 "${PPD_FILES[@]/#/$SRC_DIR/}" "$DESTDIR$MODEL_DIR" &&
        install -m 755 "$SRC_DIR/rastertokpsl_$BITS" "$DESTDIR$FILTER_DIR/rastertokpsl-bin" &&
        install -m 755 "$SRC_DIR/rastertokpsl_wrapper" "$DESTDIR$FILTER_DIR/rastertokpsl" ||
        die "Could not copy the driver files."

    # Installer versions before 1.0.5 left their unpacked files here.
    [ -z "$DESTDIR" ] && rm -rf /tmp/kyosera_ppds

    missing=$(missing_libraries "$DESTDIR$FILTER_DIR/rastertokpsl-bin")
    if [ -n "$missing" ]; then
        say "The driver needs libraries that are not installed: $(echo $missing)"
        if [ -z "$DESTDIR" ] && find_package_manager && confirm "Install them now with $PM?"; then
            install_cups_libraries || warn "Could not install the libraries."
        fi
        missing=$(missing_libraries "$DESTDIR$FILTER_DIR/rastertokpsl-bin")
        [ -n "$missing" ] && warn "Still missing: $(echo $missing). Printing will not work until they are installed." && failed=1
    fi

    if [ $failed == 0 ] && ! self_test; then
        warn "The installed filter does not run. Check the libraries it needs with: ldd $FILTER_DIR/rastertokpsl-bin"
        failed=1
    fi

    say "Drivers installed: PPD files in $MODEL_DIR, filter in $FILTER_DIR."

    # Printers that already exist keep their own copy of the PPD file, so
    # move them to the new one. CUPS keeps their chosen default options.
    if [ -z "$DESTDIR" ]; then
        if cups_running; then
            while read -r name ppd; do
                [ "$ppd" == "-" ] && continue
                if lpadmin -p "$name" -m "Kyocera/$ppd" 2> /dev/null; then
                    say "Printer \"$name\" now uses the new $ppd."
                else
                    warn "Could not update printer \"$name\". Set its driver to \"${ppd%GDI.ppd}\" (KPSL) again in the printer settings."
                fi
            done < <(kpsl_printers)
        else
            say "CUPS is not running, so existing printers were not checked. Run this installer again once it is."
        fi
    fi

    if [ $failed == 0 ]; then
        say "Done. Add the printer in the printer settings and choose the \"Kyocera <model> (KPSL)\" driver."
    else
        exit 1
    fi
}

uninstall_drivers() {
    local f name ppd

    check_root
    find_cups_dirs || die "CUPS filter directory not found, so there is nothing to uninstall."

    if [ -e "$DESTDIR$FILTER_DIR/rastertokpsl" ] && ! is_our_wrapper "$DESTDIR$FILTER_DIR/rastertokpsl"; then
        warn "$FILTER_DIR/rastertokpsl was not installed by this installer, so it is left in place."
    else
        rm -f "$DESTDIR$FILTER_DIR/rastertokpsl" "$DESTDIR$FILTER_DIR/rastertokpsl-bin"
    fi
    for f in "${PPD_FILES[@]}"; do
        rm -f "$DESTDIR$MODEL_DIR/$f"
    done
    rmdir "$DESTDIR$MODEL_DIR" 2> /dev/null

    if [ -z "$DESTDIR" ]; then
        while read -r name ppd; do
            warn "Printer \"$name\" uses these drivers and will not print any more. Delete it or choose another driver for it."
        done < <(kpsl_printers)
    fi
    say "Uninstalled."
}

check_installation() {
    local f missing name ppd problems=0 others

    say "Kyocera PPD installer v.$VERSION"
    say "Machine: $(uname -m), $(getconf LONG_BIT)-bit"
    case $(uname -m) in
        x86_64 | amd64 | i?86) ;;
        *) say "  PROBLEM: these drivers work only on x86 PCs." && problems=1 ;;
    esac

    if ! find_cups_dirs; then
        say "CUPS: not installed"
        exit 1
    fi
    say "CUPS: filter directory $FILTER_DIR, PPD directory $MODEL_DIR"
    cups_running && say "CUPS scheduler: running" || say "CUPS scheduler: not running"

    f=$DESTDIR$FILTER_DIR/rastertokpsl
    if [ ! -e "$f" ]; then
        say "Filter: not installed" && problems=1
    elif is_current_wrapper "$f"; then
        say "Filter: installed"
    elif is_our_wrapper "$f"; then
        say "Filter: installed by an earlier version of this installer (run the installer to upgrade)" && problems=1
    else
        say "Filter: an older or foreign rastertokpsl, which fails on jobs with long names" && problems=1
        [ -n "$(file_owner "$FILTER_DIR/rastertokpsl")" ] && say "  It belongs to the package \"$(file_owner "$FILTER_DIR/rastertokpsl")\"."
    fi
    if [ -e "$DESTDIR$FILTER_DIR/rastertokpsl-bin" ]; then
        [ -x "$DESTDIR$FILTER_DIR/rastertokpsl-bin" ] || { say "  PROBLEM: rastertokpsl-bin is not executable" && problems=1; }
        missing=$(missing_libraries "$DESTDIR$FILTER_DIR/rastertokpsl-bin")
        [ -n "$missing" ] && say "  PROBLEM: missing libraries: $(echo $missing)" && problems=1
        if is_our_wrapper "$f" && [ -z "$missing" ]; then
            self_test && say "  Self-test: passed" || { say "  PROBLEM: self-test failed, the filter does not run" && problems=1; }
        fi
    fi

    for f in "${PPD_FILES[@]}"; do
        [ -f "$DESTDIR$MODEL_DIR/$f" ] || { say "PPD files: $f is missing" && problems=1; }
    done

    others=$(other_kpsl_ppds)
    if [ -n "$others" ]; then
        say "Other Kyocera KPSL PPD files (they show up as duplicate drivers):"
        echo "$others" | sed 's/^/  /'
    fi

    if [ -z "$DESTDIR" ]; then
        if [ "$EUID" != 0 ]; then
            say "Printers: run as root to check them"
        else
            while read -r name ppd; do
                if [ "$ppd" == "-" ]; then
                    say "Printer \"$name\": uses rastertokpsl with a model this installer does not include"
                else
                    say "Printer \"$name\": ${ppd%GDI.ppd}"
                fi
            done < <(kpsl_printers)
        fi
    fi

    [ $problems == 0 ] && say "No problems found." || say "Problems found. Run the installer to fix them."
    return $problems
}

ASSUME_YES=0
ACTION=install
for arg in "$@"; do
    case $arg in
        -y | --yes) ASSUME_YES=1 ;;
        --uninstall) ACTION=uninstall ;;
        --check) ACTION=check ;;
        --install) ACTION=install ;;
        -h | --help) usage; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

case $ACTION in
    install)
        usage | head -4
        if [ $ASSUME_YES == 0 ] && ! confirm "Do you want to install?"; then
            say "Exited"
            exit 0
        fi
        install_drivers
        ;;
    uninstall) uninstall_drivers ;;
    check) check_installation ;;
esac
exit
