#!/bin/bash

VERSION="1.0.2"

tar -cjf kyocera_files.tar.bz2 *.ppd rastertokpsl_i386 rastertokpsl_i686 rastertokpsl_x86_64 rastertokpsl_wrapper

base64 kyocera_files.tar.bz2 > kyocera_files.tar.bz2.encoded

cat kyocera_ppds_installer.bin.part1 kyocera_files.tar.bz2.encoded kyocera_ppds_installer.bin.part2 > kyocera_ppds_installer_${VERSION}.bin

rm kyocera_files.tar.bz2 kyocera_files.tar.bz2.encoded

chmod +x kyocera_ppds_installer_${VERSION}.bin
