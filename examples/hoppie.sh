#!/bin/bash

# Send POST request to Hoppie
curl -d "email=${EMAIL}&logon=${HOPPIE_LOGON}&network=${NETWORK}" \
     -X POST https://www.hoppie.nl/acars/system/account.html 2>&1 >/dev/null
