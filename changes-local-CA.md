# Standards Evaluation & Implemented Changes: local-CA

## 1. Executive Summary

`local-CA` manages a two-tier private PKI architecture (Root CA and Intermediate CA) running across hypervisors (XCP-ng, TrueNAS, Proxmox, WSL2) with Cloud-Init injection. 

Because scripts in this repository execute in **three distinct environments**, the repository was refactored from a flat `provisioning/scripts/` bucket into three dedicated directories matching their execution contexts, and all scripts were renamed to follow the `<app>-<function>.sh` naming convention.

---

## 2. The 3 Execution Contexts Taxonomy

```
local-CA/
├── admin/                         # Context 1: Workstation Management & Hypervisor Operations
│   ├── ca-site-new.sh             # Scaffolds new site profile & passwords (was new-site.sh)
│   ├── ca-vm-deploy.sh            # Talks to Xen Orchestra REST API & deploys VMs (was deploy-xo-vm.sh)
│   ├── ca-iso-build.sh            # Builds NoCloud cidata ISO for manual installs (was build-cidata-iso.sh)
│   └── ca-manifest-render.sh      # Renders customized site Cloud-Init manifests (was render-cloud-init.sh)
│
├── ceremonies/                    # Context 2: Interactive / Air-Gapped PKI Operations
│   ├── ca-root-init.sh            # Standalone Root CA generation & proof-of-capture ceremony (was init-root-ca.sh)
│   └── ca-intermediate-sign.sh    # Signs Intermediate CSR using Root CA key (was sign-intermediate.sh)
│
├── provisioning/                  # Context 3: VM Assembly & Injection Assets
│   ├── cloud-init/                # Canonical Cloud-Init manifests (root-ca, intermediate-ca)
│   ├── guest-scripts/             # Injected scripts executed INSIDE the guest VM during boot assembly
│   │   ├── ica-request-csr.sh     # Generates key & CSR inside guest VM (was request-intermediate.sh)
│   │   └── ica-bootstrap.sh       # Assembles Step-CA & starts service inside guest (was bootstrap-intermediate.sh)
│   ├── step-ca/                   # Upstream templates (ica-config.json.tpl, provisioners)
│   └── wordlists/                 # EFF large wordlist for Diceware passphrases
│
├── conf/                          # Upstream canonical configuration templates
├── site-conf/                     # Concrete site profiles (pw-dc, etc.)
└── docs/                          # Architecture, security, and hypervisor guides
```

---

## 3. Standards Compliance & Changes Implemented

| Issue | Previous State | New Compliant State | Standard Reference |
| :--- | :--- | :--- | :--- |
| **Script Segregation** | All 8 scripts lumped in `provisioning/scripts/` | Split into `admin/`, `ceremonies/`, and `provisioning/guest-scripts/` | `package-scaffolding` |
| **Script Naming** | Names lacked `<app>-` prefix (e.g. `new-site.sh`) | Strictly `<app>-<function>.sh` (`ca-site-new.sh`, `ca-vm-deploy.sh`, etc.) | `script-conventions` |
| **Agent Context** | Missing `AGENTS.md` and global skills | `AGENTS.md` linked, all 8 global skills active, project skill `init-site` preserved | Zed Agent Skills |
| **Git Hygiene** | Stray `cio.log` in repository root | Deleted `cio.log`, added `*.log` to `.gitignore` | `package-scaffolding` |
| **Relative Paths** | `REPO_ROOT` assumed 2 levels down (`../..`) | Updated to `SCRIPT_DIR/..` for `admin/` and `ceremonies/` | `script-conventions` |
| **Shared Primitives** | In-script duplication of Diceware generation | Sourcing `lib-secret.sh` from `~/.local/lib/dev-bootstrap` | Developer Platform Library |

---

## 4. Verification

- All 8 shell scripts passed `bash -n` syntax checks.
- Internal path references across `README.md`, `docs/HYPERVISOR_GUIDE.md`, and `.agents/skills/init-site/SKILL.md` updated.
- Project-local skill `init-site` remains intact alongside the 8 global skills.
