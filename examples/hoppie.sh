#!/bin/bash

# Send POST request to Hoppie
# network is set to the current XLauncher profile
# profile names should therefore be VATSIM, IVAO, etc.
# also expects EMAIL and HOPPIE_LOGON variables to be defined in Settings
curl -d "email=${EMAIL}&logon=${HOPPIE_LOGON}&network=${XLAUNCHER_PROFILE}" \
     -X POST https://www.hoppie.nl/acars/system/account.html 2>&1 >/dev/null
