#!/bin/bash

cat kyocera_ppds_installer.bin.part1 kyocera_files.tar.bz2.encoded kyocera_ppds_installer.bin.part2 > kyocera_ppds_installer.bin
chmod +x kyocera_ppds_installer.bin
