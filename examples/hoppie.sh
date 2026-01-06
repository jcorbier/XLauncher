#!/bin/bash

# Hoppie credentials
EMAIL=""
LOGON=""

# Send POST request to Hoppie
# network is set to the current XLauncher profile
# profile names should therefore be VATSIM, IVAO, etc.
curl -d "email=${EMAIL}&logon=${LOGON}&network=${XLAUNCHER_PROFILE}" \
     -X POST https://www.hoppie.nl/acars/system/account.html 2>&1 >/dev/null
