# Kill-Nano

**Scripts to disable Chrome’s local AI model, remove `weights.bin`, and prevent it from being downloaded again using a system policy (Linux & Windows).**

---

## 🔍 Context

While reading about Google’s silent installation of a local AI model in Chrome, I discovered that Chrome downloads a large file called **`weights.bin`**, related to its **on-device AI / Gemini Nano** features.
This file is stored in the Chrome user profile, inside a folder named **`OptGuideOnDeviceModel`**.

**Example path on Ubuntu:**
```bash
/home/aur3ns/.config/google-chrome/OptGuideOnDeviceModel/2025.8.8.1141/weights.bin
```
This file can take up **several gigabytes** of disk space.

---

## ✅ Solution

This repository provides scripts to:
1. **Disable** Chrome’s local AI model via system policy:
   ```ini
   GenAILocalFoundationalModelSettings = 1
   ```
2. **Remove** already downloaded model folders.
3. **Check** if `weights.bin` is still present.

---

## 📁 Repository Contents

| Script | OS | Description |
|--------|----|-------------|
| [`kill-google-nano.sh`](disable-chrome-ai-model.sh) | Linux/Ubuntu | Bash script to disable the AI model and clean up files. |
| [`kill-google-nano.ps1`](disable-chrome-ai-model.ps1) | Windows | PowerShell script for Windows (requires admin rights). |

---

## 🚀 Usage

### 🐧 Linux/Ubuntu
1. Make the script executable:
   ```bash
   chmod +x disable-chrome-ai-model.sh
   ```
2. Run the script:
   ```bash
   ./disable-chrome-ai-model.sh
   ```
   > ⚠️ **Do not run directly with `sudo`.** The script will ask for sudo only when creating the Chrome system policy.

### 🪟 Windows
1. Open **PowerShell as Administrator**.
2. Allow script execution:
   ```powershell
   Set-ExecutionPolicy Bypass -Scope Process -Force
   ```
3. Run the script:
   ```powershell
   .\disable-chrome-ai-model.ps1
   ```

---

## ✅ Verification

After running the script:
1. **Restart Chrome**.
2. Open:
   ```
   chrome://policy/
   ```
   You should see:
   ```ini
   GenAILocalFoundationalModelSettings = 1
   ```

3. **Manual check on Linux:**
   ```bash
   find ~/.config/google-chrome ~/.cache/google-chrome -type f -name "weights.bin" 2>/dev/null
   ```
   > If no results appear, the file has been successfully removed.

---

## ⚠️ Disclaimer

- This is a **personal cleanup script**.
  It **does not** remove your bookmarks, passwords, history, or extensions.
- **Use at your own risk.**
- **Always read scripts before running them.**

---

Would you like me to add anything else, such as a "Why disable this model?" section or more details about Chrome policies?
