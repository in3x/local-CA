# Prototype: Dynamic Console Login & Security Ceremony

This prototype is a self-contained testbed designed to validate the **dynamic on-screen bootstrap password** pattern without touching any production PKI configurations.

---

## What This Tests

1. **Zero Pre-Configured Password:**
   - The cloud-init manifest contains **no** static or pre-shared password in `chpasswd`.
   - On first boot, the VM automatically generates a unique temporary bootstrap password from the embedded EFF dictionary (2 words + 7 chunked digits, e.g. `acorn-agent-371-3197`).
2. **Console Display via `/etc/issue`:**
   - The VM injects the bootstrap credentials into `/etc/issue`, so the password displays directly on the Xen Orchestra console above the `login:` prompt:
     ```text
     ========================================================================
     ### FIRST-TIME BOOT CREDENTIALS ###
     Username:         stepadmin
     Initial Password: acorn-agent-371-3197

     --> Log in as 'stepadmin' using the initial password above.
         You will be required to set your permanent passphrase upon login.
     ### END FIRST-TIME BOOT CREDENTIALS ###
     ========================================================================

     test-console login:
     ```
3. **Forced Production Roll & Proof of Capture:**
   - The user logs in as `stepadmin` with the displayed temporary password.
   - The shell immediately intercepts login and generates the permanent 4-word + 7-digit chunked passphrase (`word-word-word-word-XXX-XXXX`).
   - Demands `captured` or `got it`.
   - Demands re-typing/pasting to verify proof of capture.
   - Applies the permanent passphrase and **automatically wipes the temporary credentials block from `/etc/issue`**.

---

## How to Test in Xen Orchestra

### Method A: Automated Deployment via Script (Recommended)

1. **Configure XO Credentials for Your Site:**
   Copy the example config to `site-conf/<site-name>/xo.env` (e.g. `pw-dc`):
   ```bash
   cp conf/xo.env.example site-conf/pw-dc/xo.env
   ```
   Edit `site-conf/pw-dc/xo.env` with your XO URL and API Token:
   - In Xen Orchestra: **Settings > Users > [Your User] > API Tokens** (click *New Token*).
   - Set `XO_URL="https://your-xo-host"` and `XO_TOKEN="your-token"`.

2. **Discover Templates & SRs:**
   Run the list helper for your site (uses `curl -k` to handle self-signed certificates):
   ```bash
   ./admin/ca-vm-deploy.sh pw-dc --list
   ```
   *(If you run `./admin/ca-vm-deploy.sh` with no arguments, it lists all available site names).*
   Find your cloud template name (e.g. `Ubuntu Noble 24.04 Cloud`) and set `XO_TEMPLATE` in `site-conf/pw-dc/xo.env`.

3. **Deploy the Prototype VM:**
   ```bash
   ./admin/ca-vm-deploy.sh pw-dc
   ```
   The script creates `test-console-auth`, injects the prototype's `user-data`, and boots it automatically!

---

### Method B: Manual Web UI Deployment (No Script)

1. **Create Test VM in Xen Orchestra:**
   - **Template:** Any Debian 12 or Ubuntu 24.04 Cloud Template.
   - **Name:** `test-console-auth`
   - **vCPU / RAM:** 1 vCPU, 1024 MB RAM.
   - **Network:** Connected or Disconnected (this test does not require internet).
   - **Cloud-init:** Select **Custom config** and paste the entire contents of:
     [`prototypes/dynamic-console-login/user-data`](user-data)
   - Click **Create VM**.

---

### Observing the Test on the Console

1. **Open the Console:**
   - In Xen Orchestra, open the **`test-console-auth` > Console** tab.
   - Wait ~20–30 seconds for cloud-init to finish.
   - *(Note: If the screen remains blank or only shows cloud-init messages, press **Enter** once inside the console window to prompt `agetty` to redraw the login banner).*
   - You will see the banner appear on the console screen with the initial password!
2. **Log in:**
   - Login: `stepadmin`
   - Password: `<type the initial password displayed in the banner>`
3. **Complete the Ceremony:**
   - Follow the prompt, type `got it` or `captured`, and re-enter the permanent passphrase.
4. **Verify Banner Wiped:**
   - Log out (`exit`).
   - Look at the console screen: the temporary credentials banner is **gone**, replaced by the clean Linux login prompt.
   - Log back in using your new permanent passphrase!
