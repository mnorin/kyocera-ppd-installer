Kyocera PPD files installer
==================

Current version: v.1.1.0

Language: bash

This installer contains i386 and x86_64 linux drivers for Kyocera FS printers and multi-functional units (English only).
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

These files can be downloaded from Kyocera website. These files are to distribute under license defined by Kyocera.
If you want to update these files in installation package, please let me know.

Binary files
============

These files you can also download from Kyocera website.

License
=======

The installer script itself is distributed under GPLv2 license (see license text in LICENSE.txt)

F.A.Q.
======

**Q:** How to install drivers?<br>
**A:** Download file kyocera_ppds_installer.sh, grant execution rights and start with root privileges:

    chmod +x kyocera_ppds_installer.sh
    sudo ./kyocera_ppds_installer.sh

From a checkout of this repository, `sudo ./install.sh` does the same.
The installer also:
- offers to install CUPS and the libraries the driver needs, if they are missing;
- replaces an older or Kyocera's own `rastertokpsl` filter (it fails on jobs with long names);
- moves printers that are already set up to the new PPD file, keeping their default options;
- checks that the installed filter runs.

Add `--yes` to install without questions.

**Q:** How to check what is installed and whether something is wrong?<br>
**A:** `./kyocera_ppds_installer.sh --check` (as root it also lists the printers that use these drivers). It changes nothing.

**Q:** My documents with long names do not print. Why?<br>
**A:** Kyocera's filter crashes ("buffer overflow detected") when the job title is 64 bytes or longer or the user name is 32 bytes or longer; a Cyrillic file name reaches 64 bytes at only 32 letters. The wrapper installed by this installer shortens both to what the printer's job header holds (31 and 15 characters), transliterating Cyrillic and accented letters. Only the name shown on the printer is shortened; the document prints in full.

**Q:** Why do you need root privileges?<br>
**A:** These privileges are needed so the script could copy PPD files and necessary binaries to system directories

**Q:** Why don't you just create deb/rpm package?<br>
**A:** There are too many package managers, I just want it to work on any Linux distribution (well, as many as possible).

**Q:** How to uninstall these things?<br>
**A:** Use this: sudo ./kyocera_ppds_installer.sh --uninstall

**Q:** How to change the drivers and build the installer?<br>
**A:** Change the files in the repository, run `tests/test_wrapper.sh` and `tests/test_installer.sh` (no root needed, nothing is installed on the system), then `./build_installer.sh` to make kyocera_ppds_installer.sh.

**Q:** How to test on a real printer?<br>
**A:** `tests/make_test_print.sh ~/kyocera-test-print` makes documents whose names crash Kyocera's own driver (long, Cyrillic, special characters, exactly 63 and 64 bytes) and a `CHECKLIST.txt` with the name the printer should show for each. Print them all with `~/kyocera-test-print/print_all.sh <printer-name>`.

P.S.
====

Unfortunatelly, I don't have any Kyocera devices anymore, and I will not be able to test any fixes.
It would be nice to hear from you how it works.

Contacts
========
Website: https://mnorin.com<br>
E-mail: maxim.norin@gmail.com, mnorin@mnorin.com<br>
Skype: m.norin<br>
Linkedin: https://www.linkedin.com/in/mnorin

Changes
=======

v.1.1.0
- Fixed jobs with long names or long user names not printing (the Kyocera filter aborts on a user name of 32+ or a title of 64+ bytes; the wrapper now cuts them to what the printer's job header holds)
- Cyrillic (Russian, Ukrainian, Belarusian) and accented letters in job titles and user names are transliterated instead of being garbled on the printer
- Wrapper no longer drops the input file argument, expands wildcards in the title, or depends on bash and egrep
- Uninstallation now really removes the filter files, and leaves a filter it did not install alone
- Installer finds the CUPS filter directory instead of assuming /usr/lib/cups/filter, sets file permissions explicitly and cleans up its temporary files
- Installer offers to install CUPS and missing libraries, refuses to install on non-x86 machines, updates printers that are already set up, and tests the installed filter
- New options: --check, --yes, --help
- One installer script (install.sh) for both the repository and the single-file download; the driver files are checked for damage when unpacked
- PPD files: filter is referenced by name instead of by absolute path, removed constraints on an InputSlot option that does not exist
- Added tests (tests/test_wrapper.sh, tests/test_installer.sh)

v.1.0.4
- Uninstallation added

v.1.0.3.
- Changed architecture detection method

v.1.0.2.
- Minor fix for ROSA linux. Don't know if it will work, but it probably should
