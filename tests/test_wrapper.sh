#!/usr/bin/env bash
# Tests for rastertokpsl_wrapper.
#
# The Kyocera filter binary copies the user name (argv[2]) and the job title
# (argv[3]) into fixed-size buffers: it aborts when the user name is 32 bytes
# or longer, or the title is 64 bytes or longer, and it garbles non-ASCII bytes.
# The wrapper has to hand it short, plain ASCII values (transliterated where
# possible) and pass everything else through untouched.

cd "$(dirname "$0")/.." || exit 1
REPO=$PWD
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

FAILED=0
check() { # description, expected, actual
    if [ "$2" == "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1"
        echo "       expected: [$2]"
        echo "       actual:   [$3]"
        FAILED=1
    fi
}

# --- Part 1: argument handling, checked with a stub in place of the binary ---

mkdir "$WORK/stub"
cp rastertokpsl_wrapper "$WORK/stub/rastertokpsl"
cat > "$WORK/stub/rastertokpsl-bin" << 'EOF'
#!/bin/sh
echo "argc=$#"
for a in "$@"; do echo "[$a]"; done
EOF
chmod +x "$WORK/stub/rastertokpsl" "$WORK/stub/rastertokpsl-bin"

# Run the wrapper from a directory with files in it, so that an unquoted
# expansion of a title containing "*" would be caught.
mkdir "$WORK/cwd"
touch "$WORK/cwd/leaked_file_name"
wrap() { (cd "$WORK/cwd" && "$WORK/stub/rastertokpsl" "$@"); }
arg() { sed -n "$(($1 + 1))p" | sed 's/^\[\(.*\)\]$/\1/'; } # N-th argument seen by the stub

LONG=$(printf 'a%.0s' {1..200})

check "long title is cut to 31 characters" \
    "$(printf 'a%.0s' {1..31})" "$(wrap 1 alice "$LONG" 1 "" | arg 3)"
check "long user name is cut to 15 characters" \
    "$(printf 'a%.0s' {1..15})" "$(wrap 1 "$LONG" title 1 "" | arg 2)"
check "spaces and punctuation in the title are kept" \
    "Report (final) v2.pdf" "$(wrap 1 alice "Report (final) v2.pdf" 1 "" | arg 3)"
check "Cyrillic title is transliterated" \
    "Otchet No5 (itog).pdf" "$(wrap 1 alice "Отчёт №5 (итог).pdf" 1 "" | arg 3)"
check "Cyrillic multi-letter sounds and capitals are transliterated" \
    "Shchelkovo Ezhik ZhEK" "$(wrap 1 alice "Щёлково Ёжик ЖЭК" 1 "" | arg 3)"
check "Ukrainian letters are transliterated" \
    "Yizhak Yevgen Ivan Gont" "$(wrap 1 alice "Їжак Євген Іван Ґонт" 1 "" | arg 3)"
check "long Cyrillic title is transliterated, then cut to 31 characters" \
    "Ochen dlinnoe imya fayla dlya p" "$(wrap 1 alice "Очень длинное имя файла для проверки печати.pdf" 1 "" | arg 3)"
check "repeated spaces are squeezed" \
    "a b c" "$(wrap 1 alice "  a    b   c  " 1 "" | arg 3)"
check "title with no letters or digits left falls back to the job id" \
    "job-42" "$(wrap 42 alice "日本語の文書" 1 "" | arg 3)"
check "question marks in the title are kept" \
    "What? Why?.pdf" "$(wrap 1 alice "What? Why?.pdf" 1 "" | arg 3)"
check "characters that cannot be transliterated are dropped" \
    "05 .pdf" "$(wrap 1 alice "05 日本語の文書 📄 测试打印 テスト用の長いファイル名です.pdf" 1 "" | arg 3)"
check "invalid UTF-8 in the title does not break the wrapper" \
    "bad name.pdf" "$(wrap 1 alice "$(printf 'bad\377\376 name.pdf')" 1 "" | arg 3)"
check "empty title falls back to the job id" \
    "job-42" "$(wrap 42 alice "" 1 "" | arg 3)"
check "Cyrillic user name is transliterated" \
    "Ivan" "$(wrap 1 "Иван" title 1 "" | arg 2)"
check "user name with no letters or digits left falls back to a placeholder" \
    "user" "$(wrap 1 "山田" title 1 "" | arg 2)"
# Accented letters need iconv with transliteration, which not every system has.
if [ "$(printf 'é' | LC_ALL=C.UTF-8 iconv -f UTF-8 -t ASCII//TRANSLIT 2> /dev/null)" == "e" ]; then
    check "accented letters are transliterated" \
        "Cafe resume -- final.pdf" "$(wrap 1 alice "Café résumé — final.pdf" 1 "" | arg 3)"
    check "accented letters are transliterated next to ones that cannot be" \
        "Cafe ? naive.pdf" "$(wrap 1 alice "Café ? ﾃ日本 📄 naïve.pdf" 1 "" | arg 3)"
    check "accented letters are transliterated next to invalid UTF-8" \
        "Cafe naive.pdf" "$(wrap 1 alice "$(printf 'Café \377\376 naïve.pdf')" 1 "" | arg 3)"
else
    echo "skip - iconv cannot transliterate accented letters here"
fi
check "title is not glob-expanded or treated as echo options" \
    "-n -e *" "$(wrap 1 alice "-n -e *" 1 "" | arg 3)"
check "options are passed through unchanged" \
    "PageSize=A4 Duplex=None job-uuid=urn:uuid:1" \
    "$(wrap 1 alice title 1 "PageSize=A4 Duplex=None job-uuid=urn:uuid:1" | arg 5)"
check "without a file argument the binary gets 5 arguments" \
    "argc=5" "$(wrap 1 alice title 1 "" | head -1)"
check "the file argument is passed on" \
    "/some/file name.ras" "$(wrap 1 alice title 1 "" "/some/file name.ras" | arg 6)"

# --- Part 2: the real binary, if it can run here and a raster can be made ---

BIN=$REPO/rastertokpsl_$(getconf LONG_BIT)
can_run() { "$BIN" < /dev/null > /dev/null 2>&1; local rc=$?; [ $rc != 126 ] && [ $rc != 127 ]; }
if command -v gs > /dev/null && command -v cupsfilter > /dev/null && can_run; then
    mkdir "$WORK/real"
    cp rastertokpsl_wrapper "$WORK/real/rastertokpsl"
    cp "$BIN" "$WORK/real/rastertokpsl-bin"
    chmod +x "$WORK/real/rastertokpsl" "$WORK/real/rastertokpsl-bin"
    export PPD=$REPO/Kyocera_FS-1025MFPGDI.ppd

    printf '%%!\n/Helvetica findfont 40 scalefont setfont 72 700 moveto (Test page) show showpage\n' > "$WORK/t.ps"
    gs -q -dNOPAUSE -dBATCH -sDEVICE=pdfwrite -sOutputFile="$WORK/t.pdf" "$WORK/t.ps"
    cupsfilter -p "$PPD" -m application/vnd.cups-raster "$WORK/t.pdf" > "$WORK/t.ras" 2> /dev/null

    if [ -s "$WORK/t.ras" ]; then
        "$WORK/real/rastertokpsl" 1 alice short 1 "" < "$WORK/t.ras" > "$WORK/ref.bin" 2> /dev/null
        REF_SIZE=$(stat -c %s "$WORK/ref.bin")
        # The timestamp in the job header changes from run to run, so compare sizes.
        real() { "$WORK/real/rastertokpsl" "$@" > "$WORK/out.bin" 2> /dev/null; echo "rc=$? size=$(stat -c %s "$WORK/out.bin")"; }

        check "real binary: 200-character title prints" \
            "rc=0 size=$REF_SIZE" "$(real 1 alice "$LONG" 1 "" < "$WORK/t.ras")"
        check "real binary: long Cyrillic title prints" \
            "rc=0 size=$REF_SIZE" "$(real 1 alice "Очень длинное название документа для проверки печати — итоговый отчёт за ноябрь 2026 года.pdf" 1 "" < "$WORK/t.ras")"
        check "real binary: 200-character user name prints" \
            "rc=0 size=$REF_SIZE" "$(real 1 "$LONG" title 1 "" < "$WORK/t.ras")"
        check "real binary: raster given as a file argument prints" \
            "rc=0 size=$REF_SIZE" "$(real 1 alice title 1 "" "$WORK/t.ras" < /dev/null)"
    else
        echo "skip - could not generate a test raster"
    fi
else
    echo "skip - real binary tests need gs, cupsfilter and a runnable $BIN"
fi

[ $FAILED == 0 ] && echo "All tests passed." || echo "Some tests FAILED."
exit $FAILED
