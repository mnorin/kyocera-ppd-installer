Kyocera PPD files installer
==================

Current version: v.1.0.2

Language: bash

This installer contains i386 and x86_64 linux drivers for Kyosera FS printers and multi-functional units (English only).
Included models:
- Kyocera FS-1020MFP
- Kyocera FS-1025MFP
- Kyocera FS-1040
- Kyocera FS-1060DN
- Kyocera FS-1120MFP
- Kyocera FS-1125MFP

-------

PPD Files
=========

These files can be downloaded from Kyocera website.
If you want to update these files in installation package, please let me know.

Binary files
============

These files you can also download from Kyocera website.

F.A.Q.
======

**Q:** How to install drivers?
**A:** Download file that ends with .bin, grant execution rights and start with root privileges.

**Q:** Why do you need rott privileges?
**A:** These privileges are needed so the script could copy PPD files and necessary binaries to system directories

**Q:** Why don't you just create deb/rpm package?
**A:** There are too many package managers, I just want it to work on any Linux distribution (well, as many as possible).

P.S.
====

Unfortunatelly, I don't have any Kycera devices anymore, so I will not be able to test any fixes.
So, it would be nice to hear from you

Changes
=======

v.1.0.2.
- Minor fix for ROSA linux. Don't now if it will work, but it probably should
