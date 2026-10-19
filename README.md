# Kill-Nano

Prevent **Google Chrome** from downloading and using its **local foundational generative-AI model** on Linux or Windows. Optionally remove already-downloaded model directories without force-closing the browser.

> **Scope:** This project controls the local foundational model (including the Chrome component commonly stored under `OptGuideOnDeviceModel`). It does **not** disable all Chrome AI features, remote AI services, or Chrome extensions. It is not a privacy or malware-removal tool.

## How it works

Kill-Nano installs Chrome's supported **machine-level managed policy**:

| Policy | Value | Effect |
| --- | --- | --- |
| `GenAILocalFoundationalModelSettings` | `1` | Do not download or use Chrome's local foundational model; Chrome also removes an existing model. |

Google documents this policy for **Chrome 124+** on Linux/Windows. It is dynamically refreshed by Chrome, although restarting Chrome makes verification easier.

The scripts also attempt to remove the **specific model directories** used by Chrome (only if the browser is closed). They do not delete the whole Chrome profile, browsing history, bookmarks, passwords, or extensions. If Chrome is running, cleanup is skipped instead of forcibly terminating it. The managed policy remains the primary download-prevention mechanism even when cleanup is skipped.

To minimize collateral damage, the scripts only delete the `OptGuideOnDeviceModel` directory in the current user's Chrome profile (plus its dedicated Chrome cache location on Linux). Unlike the older release, they **do not recursively delete** `optimization_guide_model_store`, which could also contain unrelated components. Chrome is responsible for removing the disabled foundational model after it processes the policy.

## Important: Secure DNS / DNS-over-HTTPS

**Machine-level Chrome management can disable automatic DNS-over-HTTPS when no DNS policy is configured.** A user reported this at [issue #1](https://github.com/Aur3ns/Kill-Nano/issues/1). Chrome may show *“This setting is disabled on managed browsers”* under **Use secure DNS**. This is a side effect of managed-browser policy, not a separate DNS modification by Kill-Nano.

Kill-Nano **does not change DNS settings by default**. If you want to explicitly enable Chrome's DNS-over-HTTPS in managed mode, choose the optional setting below:

| Platform | Opt-in switch | What it does |
| --- | --- | --- |
| Linux | `--doh-automatic` | Sets `DnsOverHttpsMode` to `automatic` in a separate managed policy file. |
| Windows | `-DnsAutomatic` | Sets `DnsOverHttpsMode` to `automatic` in the Chrome policy registry key. |

`automatic` **attempts encrypted DNS first when an appropriate resolver is available but can fall back to unencrypted DNS**. It does **not** guarantee encrypted DNS for every query, and the Chrome setting can remain locked because the DNS mode is itself managed. Opt in only if you accept that trade-off. Kill-Nano refuses to overwrite a conflicting existing policy. Don't use it to override company, school, or other administrator policies.

See [Chrome's DNS-over-HTTPS policy](https://chromeenterprise.google/policies/dns-over-https-mode/) and [local model policy](https://chromeenterprise.google/policies/gen-ai-local-foundational-model-settings/).

## Requirements

- Google Chrome 124+ on Ubuntu/Debian or Windows 10/11 (not Chromium or other Chrome-based browsers).
- Linux: Bash, `sudo`, `pgrep` (`procps`), and administrator permission to write `/etc/opt/chrome/policies/managed`. Run as the affected **normal desktop user**, **not** as root.
- Windows: PowerShell 5.1+ running **as Administrator**. The model directory inspected belongs to the account that runs PowerShell; avoid launching as a *different* administrator account if you intend to clean your own model files.

## Linux (Ubuntu/Debian)

```bash
git clone https://github.com/Aur3ns/Kill-Nano.git
cd Kill-Nano
chmod +x kill-google-nano.sh
./kill-google-nano.sh --dry-run          # Preview without any changes
./kill-google-nano.sh                    # Install policy; clean if Chrome is closed
./kill-google-nano.sh --status           # Inspect Kill-Nano's policy files
```

Optional:

```bash
./kill-google-nano.sh --doh-automatic    # Also explicitly manage DoH in automatic mode
./kill-google-nano.sh --skip-cleanup     # Install the policy, leave model files alone
./kill-google-nano.sh --restore          # Remove only unmodified Kill-Nano policy files
```

Linux writes `/etc/opt/chrome/policies/managed/disable-genai-local-model.json` and, only if explicitly requested, `/etc/opt/chrome/policies/managed/kill-nano-doh.json`. Existing files with different content are **not overwritten**. If you had customized the old Kill-Nano policy file, back it up and reconcile it manually.

**Linux ownership caveat:** `--restore` verifies the exact expected file content and filename, not a cryptographic installation record. A separately created file with identical content at the same location would also match. On shared or company-managed computers, inspect the policy's ownership before using restore.

## Windows (PowerShell)

Open PowerShell **as Administrator** in the cloned project directory:

```powershell
.\kill-google-nano.ps1 -DryRun
.\kill-google-nano.ps1
.\kill-google-nano.ps1 -Action Status
```

Optional:

```powershell
.\kill-google-nano.ps1 -DnsAutomatic
.\kill-google-nano.ps1 -SkipCleanup
.\kill-google-nano.ps1 -Action Restore
```

PowerShell execution policies may block local scripts. Use your existing organization-approved execution configuration; do **not** weaken a managed execution policy just to run this script.

Windows sets `HKLM\SOFTWARE\Policies\Google\Chrome\GenAILocalFoundationalModelSettings` (DWORD 1). Kill-Nano tracks only values it created under `HKLM\SOFTWARE\KillNano` so `-Action Restore` does not delete a pre-existing administrator policy. **Legacy installations** made before this ownership tracking may require manual removal of the old value after confirming its provenance.

## Verify that it worked

1. Restart Chrome, open `chrome://policy/`, select **Reload policies**, and check `GenAILocalFoundationalModelSettings = 1` with a valid status.
2. Optionally check `DnsOverHttpsMode = automatic` **only if** you used the DoH switch. Verify DoH behavior separately if it matters for your network.
3. Close Chrome and run the script again if its output says model cleanup was skipped.
4. You can search for remaining `weights.bin` files, but such files can belong to other components; **a found file alone does not prove that Chrome ignored the policy**.

**Note:** Chrome can receive policies from several sources, including an enterprise/cloud administrator. `--status` / `-Action Status` reports these scripts' local settings; **`chrome://policy/` is the authoritative place to inspect Chrome's effective policy**.

## Safety and rollback

- No forced process termination, network request, or hidden scheduler is used. The scripts leave unrelated registry values and policy files intact.
- The scripts never remove an entire Chrome profile. They only attempt cleanup of known model directories **after Chrome has exited**. Keep normal backups anyway.
- `--dry-run` / `-DryRun` previews without modifying policies or deleting files.
- `--restore` / `-Action Restore` remove matching local policies where the script has sufficient ownership evidence (Linux: reserved filename and exact contents; Windows: installation marker and expected value); they **cannot** override another administrator's policy. See the Linux ownership caveat above. Restoring a policy can allow Chrome to download the model again.
- Treat model file cleanup as irreversible; no model backup is created.

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| **Secure DNS is disabled** | Read the DoH section above; opt into automatic mode only if appropriate. Managed UI restrictions may remain. |
| **Chrome says policy is managed** | Expected for machine-level policies. View the effective value at `chrome://policy/`. |
| **Chrome is running** | Close it normally, then rerun for file cleanup; no browser process is killed. |
| **A different `weights.bin` is still present** | The cleanup intentionally avoids deleting unrelated model stores; verify the effective managed policy instead of blindly removing all `weights.bin` files. |
| **A policy already exists with different content** | Inspect the existing policy first; Kill-Nano will not overwrite it. |
| **Windows restore leaves a legacy policy** | Older script versions did not record ownership; investigate before manually removing the registry entry. |
| **Policy reports an error** | Confirm Google Chrome 124+ and the policy value/data type. |

## References

- [Chrome Enterprise: GenAILocalFoundationalModelSettings](https://chromeenterprise.google/policies/gen-ai-local-foundational-model-settings/)
- [Chrome Enterprise: DnsOverHttpsMode](https://chromeenterprise.google/policies/dns-over-https-mode/)
- [User report: Secure DNS disabled by a managed policy](https://github.com/Aur3ns/Kill-Nano/issues/1)

## License

MIT — see [LICENSE](LICENSE).
