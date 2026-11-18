#!/usr/bin/env bash
# Makes test documents for a real printer: their file names are the cases that
# make Kyocera's rastertokpsl filter crash without the wrapper (long, Cyrillic,
# special characters, right at the 64-byte limit). Each document prints the
# name the printer should show for it and has a second page, so a complete
# print shows that the whole job went through.
#
# Usage: tests/make_test_print.sh [output-directory]
# Then:  <output-directory>/print_all.sh <printer-name>

set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-kyocera-test-print}
command -v gs > /dev/null || { echo "Ghostscript (gs) is needed to make the test documents." >&2; exit 1; }
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)

# The title the printer gets, worked out by running the wrapper with a stub
# in place of Kyocera's binary.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
cp "$REPO/rastertokpsl_wrapper" "$tmp/rastertokpsl"
printf '#!/bin/sh\nprintf "%%s" "$3"\n' > "$tmp/rastertokpsl-bin"
chmod +x "$tmp/rastertokpsl" "$tmp/rastertokpsl-bin"
expected_title() { "$tmp/rastertokpsl" N user "$1" 1 "" 2> /dev/null; }

ps_string() { printf '%s' "$1" | LC_ALL=C sed 's/[\\()]/\\&/g'; }

# A name of exactly the given number of bytes, with .pdf at the end.
name_of_bytes() { # prefix, bytes
    local name=$1
    while [ $((${#name} + 4)) -lt "$2" ]; do name+=x; done
    printf '%s.pdf' "$name"
}

CASES=(
    "01 Очень длинное название документа для проверки печати — итоговый отчёт за ноябрь 2026 года (финальная версия).pdf	Long Cyrillic name, far over the 64-byte limit"
    "02 Quarterly financial report for the board of directors including all appendices, tables and charts, final revised version approved on 17 November 2026.pdf	Long English name"
    "03 Report \"final\" & 'draft' \$HOME \`date\` ; rm -rf * | (copy) [1] {a,b} 100% #tag.pdf	Quotes and shell special characters"
    "04 Звіт про діяльність за жовтень — ґрунтовний аналіз, їжа та євро; беларуская мова ў тэксце.pdf	Ukrainian and Belarusian letters"
    "05 日本語の文書 📄 测试打印 テスト用の長いファイル名です.pdf	Nothing that can be transliterated"
    "$(name_of_bytes "06a exactly 63 bytes " 63)	63-byte name: the longest Kyocera's own driver prints"
    "$(name_of_bytes "06b exactly 64 bytes " 64)	64-byte name: the shortest that crashes Kyocera's own driver"
    "07 short.pdf	Short name, for comparison"
)

page() { # heading, line...
    local y=740 line
    printf '/Helvetica-Bold findfont 22 scalefont setfont 60 %d moveto (%s) show\n' $y "$(ps_string "$1")"
    shift
    printf '/Helvetica findfont 12 scalefont setfont\n'
    y=700
    for line in "$@"; do
        printf '60 %d moveto (%s) show\n' $y "$(ps_string "$line")"
        y=$((y - 20))
    done
    # A frame 20 points inside the page edge, to check the margins.
    printf '2 setlinewidth 20 20 moveto 575 20 lineto 575 822 lineto 20 822 lineto closepath stroke\n'
}

{
    printf 'Kyocera wrapper test documents\n'
    printf 'Print them with: %s/print_all.sh <printer-name>\n\n' "$OUT"
} > "$OUT/CHECKLIST.txt"

for case in "${CASES[@]}"; do
    name=${case%%$'\t'*}
    what=${case#*$'\t'}
    title=$(expected_title "$name")
    bytes=$(printf '%s' "$name" | LC_ALL=C wc -c)
    [ "$bytes" -ge 64 ] && before="crashes, nothing printed" || before="prints"
    {
        printf '%%!PS-Adobe-3.0\n%%%%DocumentMedia: A4 595 842 0 () ()\n'
        printf '<< /PageSize [595 842] >> setpagedevice\n'
        page "Test ${name%% *}: $what" \
            "The file name is $bytes bytes long (Kyocera's filter crashes at 64 or more)." \
            "With Kyocera's own driver (no wrapper) this job $before." \
            "The printer should show this job as:" \
            "    $title" \
            "(A job with nothing printable left in its name shows as job-<job number>.)" \
            "" \
            "There is a second page: if it prints too, the whole job went through."
        printf 'showpage\n'
        page "Page 2 of 2" "Test ${name%% *} printed completely." "" "Grey ramp, for print quality:"
        printf '0 1 9 { dup 10 div setgray 50 mul 60 add 560 50 50 rectfill } for\n'
        printf 'showpage\n'
    } > "$tmp/doc.ps"
    # Ghostscript gives "%" and "|" in output names a meaning, so rename afterwards.
    gs -q -dNOPAUSE -dBATCH -dSAFER -sDEVICE=pdfwrite -sOutputFile="$tmp/doc.pdf" "$tmp/doc.ps"
    mv "$tmp/doc.pdf" "$OUT/$name"
    printf "[ ] %s\n    %s; %d bytes; Kyocera's own driver: %s\n    printer shows: %s\n\n" "$name" "$what" "$bytes" "$before" "$title" >> "$OUT/CHECKLIST.txt"
done

cat > "$OUT/print_all.sh" << 'SCRIPT'
#!/usr/bin/env bash
# Prints every test document on the printer given, using the file name as the
# job name, as desktop applications do.
set -u
printer=${1:?Usage: print_all.sh <printer-name>   (see lpstat -p for the names)}
cd "$(dirname "$0")" || exit 1
for f in [0-9]*.pdf; do
    lp -d "$printer" -- "$f" || echo "FAILED to send: $f" >&2
done
# A long user name too. CUPS may replace it with your own login name; the
# printer then shows that instead.
lp -d "$printer" -U averyveryverylongdomainusername.example -t "08 long user name" -- "07 short.pdf" ||
    echo "FAILED to send the long user name job" >&2
echo
echo "Sent. Follow the jobs with: lpstat -W all -o $printer"
echo "If a job does not print, the reason is in /var/log/cups/error_log"
SCRIPT
chmod +x "$OUT/print_all.sh"
cat >> "$OUT/CHECKLIST.txt" << 'EOF'
[ ] 08 long user name (07 short.pdf sent as user averyveryverylongdomainusername.example)
    Kyocera's own driver: crashes, nothing printed
    printer shows user: averyveryverylo (or your own login name)
EOF

echo "Test documents are in $OUT"
echo "Print them with: $OUT/print_all.sh <printer-name>"
