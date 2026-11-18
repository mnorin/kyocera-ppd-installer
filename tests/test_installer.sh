#!/usr/bin/env bash
# Tests for install.sh and the single-file installer made by build_installer.sh.
# Everything is installed into staging directories (DESTDIR), so no root is
# needed and the system is not touched.

cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAILED=0
ok() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; [ -n "$2" ] && echo "$2" | sed 's/^/       /'; FAILED=1; }
check() { # description, command...
    local d=$1 out
    shift
    if out=$("$@" 2>&1); then ok "$d"; else fail "$d" "$out"; fi
}

BITS=$(getconf LONG_BIT)
FILTER_DIR=$(DESTDIR=/nonexistent bash -c "source <(sed -n '/^find_cups_dirs()/,/^}/p' install.sh); find_cups_dirs; echo \$FILTER_DIR")
MODEL_DIR=$(DESTDIR=/nonexistent bash -c "source <(sed -n '/^find_cups_dirs()/,/^}/p' install.sh); find_cups_dirs; echo \$MODEL_DIR")
PPDS=(Kyocera_FS-1020MFPGDI.ppd Kyocera_FS-1025MFPGDI.ppd Kyocera_FS-1040GDI.ppd
    Kyocera_FS-1060DNGDI.ppd Kyocera_FS-1120MFPGDI.ppd Kyocera_FS-1125MFPGDI.ppd)

perm() { stat -c %a "$1"; }

installed_ok() { # stage
    local s=$1 f
    for f in "${PPDS[@]}"; do
        [ -f "$s$MODEL_DIR/$f" ] || { echo "missing $f"; return 1; }
        [ "$(perm "$s$MODEL_DIR/$f")" == 644 ] || { echo "$f has mode $(perm "$s$MODEL_DIR/$f")"; return 1; }
    done
    [ "$(perm "$s$FILTER_DIR/rastertokpsl")" == 755 ] || { echo "wrapper mode $(perm "$s$FILTER_DIR/rastertokpsl")"; return 1; }
    [ "$(perm "$s$FILTER_DIR/rastertokpsl-bin")" == 755 ] || { echo "binary mode $(perm "$s$FILTER_DIR/rastertokpsl-bin")"; return 1; }
    cmp "$REPO/rastertokpsl_wrapper" "$s$FILTER_DIR/rastertokpsl" || return 1
    cmp "$REPO/rastertokpsl_$BITS" "$s$FILTER_DIR/rastertokpsl-bin" || return 1
}

nothing_installed() { # stage
    local left
    left=$(find "$1" -type f)
    [ -z "$left" ] || { echo "left behind: $left"; return 1; }
    [ ! -d "$1$MODEL_DIR" ] || { echo "$MODEL_DIR still exists"; return 1; }
}

output_has() { # text, command...
    local text=$1 out
    shift
    out=$("$@" 2>&1)
    grep -qF -- "$text" <<< "$out" || { echo "\"$text\" not in output:"; echo "$out"; return 1; }
}

# --- Command line ---

check "--help exits 0 and shows usage" output_has "--uninstall" ./install.sh --help
check "unknown option exits 2" bash -c './install.sh --bogus > /dev/null 2>&1; [ $? == 2 ]'
if [ "$EUID" != 0 ]; then
    check "installing without root or DESTDIR is refused" \
        bash -c './install.sh --yes > /dev/null 2>&1; [ $? == 1 ]'
fi

# --- Build ---

check "build_installer.sh builds the single-file installer" ./build_installer.sh "$WORK/built.sh"
./build_installer.sh "$WORK/built2.sh" > /dev/null
check "the build is reproducible" cmp "$WORK/built.sh" "$WORK/built2.sh"
check "the built installer is executable" test -x "$WORK/built.sh"

# --- Install, check and uninstall, from the checkout and as a single file ---

mkdir "$WORK/elsewhere"
cp "$WORK/built.sh" "$WORK/elsewhere/kyocera_ppds_installer.sh"

for variant in checkout single-file; do
    if [ $variant == checkout ]; then
        INSTALLER=$REPO/install.sh
    else
        # Run from a directory with no driver files, so they must come from the payload.
        INSTALLER=$WORK/elsewhere/kyocera_ppds_installer.sh
    fi
    STAGE=$WORK/stage-$variant
    mkdir "$STAGE"
    export DESTDIR=$STAGE

    check "$variant: answering no installs nothing" \
        bash -c "echo n | '$INSTALLER' > /dev/null 2>&1 && [ -z \"\$(find '$STAGE' -type f)\" ]"
    check "$variant: answering yes installs" bash -c "echo y | '$INSTALLER'"
    check "$variant: files are installed with the right contents and modes" installed_ok "$STAGE"
    check "$variant: --check finds no problems" output_has "No problems found." "$INSTALLER" --check
    check "$variant: --check self-test passes" output_has "Self-test: passed" "$INSTALLER" --check
    check "$variant: installing again works" "$INSTALLER" --yes
    check "$variant: --uninstall removes everything" "$INSTALLER" --uninstall
    check "$variant: nothing is left behind" nothing_installed "$STAGE"
    unset DESTDIR
done

# --- Upgrades and other drivers ---

STAGE=$WORK/stage-upgrade
mkdir -p "$STAGE$FILTER_DIR"
export DESTDIR=$STAGE

# The wrapper installed by version 1.0.4.
cat > "$STAGE$FILTER_DIR/rastertokpsl" << 'EOF'
#!/usr/bin/env bash

jobname=$(echo $3 | egrep -o '[[:alnum:]]' | tr -d "\n" | tail -c 20)
/usr/lib/cups/filter/rastertokpsl-bin "$1" "$2" "$jobname" "$4" "$5"
EOF
check "an earlier version is reported by --check" \
    output_has "installed by an earlier version of this installer" ./install.sh --check
check "an earlier version is upgraded" output_has "Upgrading" ./install.sh --yes
check "the upgrade installs the current files" installed_ok "$STAGE"
./install.sh --uninstall > /dev/null 2>&1

# A filter that this installer did not put there, e.g. from Kyocera's own package.
mkdir -p "$STAGE$FILTER_DIR"
cp "$REPO/rastertokpsl_$BITS" "$STAGE$FILTER_DIR/rastertokpsl"
check "a foreign filter is reported by --check" output_has "older or foreign rastertokpsl" ./install.sh --check
check "uninstall leaves a foreign filter alone" \
    bash -c "./install.sh --uninstall > /dev/null 2>&1 && cmp '$REPO/rastertokpsl_$BITS' '$STAGE$FILTER_DIR/rastertokpsl'"
check "install replaces a foreign filter" output_has "Replacing an older rastertokpsl filter" ./install.sh --yes
check "the replacement installs the current files" installed_ok "$STAGE"

mkdir -p "$STAGE/usr/share/ppd/kyocera"
cp "$REPO/Kyocera_FS-1025MFPGDI.ppd" "$STAGE/usr/share/ppd/kyocera/Kyocera_FS-1025MFP.ppd"
check "other copies of the PPD files are reported by --check" \
    output_has "/usr/share/ppd/kyocera/Kyocera_FS-1025MFP.ppd" ./install.sh --check
unset DESTDIR

# --- A damaged single-file installer ---

head -c -2000 "$WORK/built.sh" > "$WORK/elsewhere/broken.sh"
chmod +x "$WORK/elsewhere/broken.sh"
mkdir "$WORK/stage-broken"
check "a damaged installer stops with an error" \
    bash -c "! DESTDIR='$WORK/stage-broken' '$WORK/elsewhere/broken.sh' --yes > /dev/null 2>&1"
check "a damaged installer installs nothing" \
    bash -c "[ -z \"\$(find '$WORK/stage-broken' -type f)\" ]"

# --- The whole CUPS filter chain, PDF to printer data, with a long title ---

if command -v cupsfilter > /dev/null && command -v gs > /dev/null && [ -d "$FILTER_DIR" ]; then
    STAGE=$WORK/stage-cups
    mkdir "$STAGE"
    DESTDIR=$STAGE ./install.sh --yes > /dev/null 2>&1
    # A copy of the system's filter directory with this driver in it.
    mkdir -p "$WORK/serverbin/filter"
    ln -s "$FILTER_DIR"/* "$WORK/serverbin/filter/" 2> /dev/null
    rm -f "$WORK/serverbin/filter/rastertokpsl" "$WORK/serverbin/filter/rastertokpsl-bin"
    cp -p "$STAGE$FILTER_DIR"/rastertokpsl* "$WORK/serverbin/filter/"
    printf 'ServerBin %s\n' "$WORK/serverbin" > "$WORK/cups-files.conf"

    printf '%%!\n/Helvetica findfont 40 scalefont setfont 72 700 moveto (Test page) show showpage\n' > "$WORK/t.ps"
    gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$WORK/t.pdf" "$WORK/t.ps"
    # Prints t.pdf with a long Cyrillic title and user name into the file given.
    # A script rather than a function, so it can also run under "bash -c".
    {
        echo '#!/usr/bin/env bash'
        printf 'cupsfilter -c %q -p %q' "$WORK/cups-files.conf" "$STAGE$MODEL_DIR/Kyocera_FS-1025MFPGDI.ppd"
        printf ' -t %q' "Очень длинное имя файла для проверки печати — итоговый отчёт за ноябрь 2026 года.pdf"
        printf ' -U averyveryverylongdomainusername.example -m printer/kyocera -e %q' "$WORK/t.pdf"
        echo ' > "$1" 2> "$1.log"'
    } > "$WORK/print_job.sh"
    chmod +x "$WORK/print_job.sh"
    print_job() { "$WORK/print_job.sh" "$@"; }

    # The job header holds the title as UTF-16LE.
    has_title() { # text, job file
        local hex
        hex=$(printf '%s' "$1" | iconv -f ASCII -t UTF-16LE | xxd -p | tr -d '\n')
        xxd -p "$2" | tr -d '\n' | grep -q "$hex"
    }

    check "CUPS chain: a long Cyrillic title prints" print_job "$WORK/job.kpsl"
    check "CUPS chain: the output is a KPSL job" bash -c "[ \"\$(head -c 4 '$WORK/job.kpsl')\" == LSPK ]"
    check "CUPS chain: the transliterated title is in the job" \
        has_title "Ochen dlinnoe imya fayla dlya p" "$WORK/job.kpsl"

    # Without the wrapper, the same job crashes Kyocera's filter. This shows the
    # test above really exercises the problem the wrapper fixes.
    cp "$WORK/serverbin/filter/rastertokpsl-bin" "$WORK/serverbin/filter/rastertokpsl"
    check "CUPS chain: without the wrapper the same job fails" bash -c "! '$WORK/print_job.sh' '$WORK/bare.kpsl'"
else
    echo "skip - CUPS chain tests need cupsfilter, gs and CUPS"
fi

[ $FAILED == 0 ] && echo "All tests passed." || echo "Some tests FAILED."
exit $FAILED
