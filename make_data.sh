#!/bin/bash
tar -cjf kyocera_files.tar.bz2 *.ppd rastertokpsl_i386 rastertokpsl_i686 rastertokpsl_x86_64 rastertokpsl_wrapper
base64 kyocera_files.tar.bz2 > kyocera_files.tar.bz2.encoded
