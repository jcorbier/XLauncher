# Pre-Launch Scripts

You can attach shell scripts to profiles to run before X-Plane launches. This is useful for pre-flight tasks like authenticating on ACARS networks, starting helper utilities, or mounting network drives.

---

## Attaching Scripts to a Profile

Navigate to the **Profile Scripts** tab:

```{image} /_static/images/scripts-view.png
:alt: Screenshot of the Profile Scripts tab with attached scripts list and the Profile Environment Variables table
:align: center
```

1. Click **+** in the scripts list and select a script file on your disk.
2. Make sure the script has executable permissions (`chmod +x script.sh`).
3. Toggle the script on or off for the active profile.

---

## Environment Variables

When executing scripts before launch, X-Plane Launcher passes environment variables from three sources:

1. **Global Variables**: Configured in **Settings > Script Environment**. Shared across all profiles.
2. **Profile Variables**: Configured in the **Profile Scripts** tab. Specific to the active profile, overriding any matching global variable keys.
3. **`XLAUNCHER_PROFILE`**: Automatically set to the name of the active profile.

---

## Example: Hoppie ACARS Script

Here is an example script ([`examples/hoppie.sh`](https://github.com/jcorbier/x-plane-launcher/blob/main/examples/hoppie.sh)) that sends an authentication request to the Hoppie ACARS network:

```bash
#!/bin/bash
set -e

# Send POST request to Hoppie with environment variables
curl -s -d "email=${EMAIL}&logon=${HOPPIE_LOGON}&network=${NETWORK}" \
     -X POST https://www.hoppie.nl/acars/system/account.html > /dev/null
```

### Setup in X-Plane Launcher:
- In **Settings > Script Environment**:
  - `EMAIL` = `pilot@example.com`
  - `HOPPIE_LOGON` = `YOUR_HOPPIE_CODE`
- In **Profile Scripts (VATSIM profile)**:
  - Add `/path/to/hoppie.sh`
  - `NETWORK` = `VATSIM`
- In **Profile Scripts (IVAO profile)**:
  - Add `/path/to/hoppie.sh`
  - `NETWORK` = `IVAO`
