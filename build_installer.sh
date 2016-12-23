#!/bin/bash

VERSION="1.0.3"

tar -cjf kyocera_files.tar.bz2 *.ppd rastertokpsl_32 rastertokpsl_64 rastertokpsl_wrapper

base64 kyocera_files.tar.bz2 > kyocera_files.tar.bz2.encoded

cat kyocera_ppds_installer.bin.part1 kyocera_files.tar.bz2.encoded kyocera_ppds_installer.bin.part2 > kyocera_ppds_installer_${VERSION}.sh

rm kyocera_files.tar.bz2 kyocera_files.tar.bz2.encoded

chmod +x kyocera_ppds_installer_${VERSION}.sh
