#!/bin/bash

VERSION="1.0.2"
cat kyocera_ppds_installer.bin.part1 kyocera_files.tar.bz2.encoded kyocera_ppds_installer.bin.part2 > kyocera_ppds_installer_${VERSION}.bin
chmod +x kyocera_ppds_installer.bin
