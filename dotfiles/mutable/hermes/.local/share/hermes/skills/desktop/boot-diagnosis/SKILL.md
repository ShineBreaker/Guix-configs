---
name: boot-diagnosis
description: "Use when diagnosing unbootable Linux distros offline."
version: 1
author: hermes
license: MIT
metadata:
  hermes:
    tags:
      - boot
      - initramfs
      - dracut
      - luks
      - plymouth
      - btrfs
      - multiboot
---

# Boot Diagnosis (offline, from another distro)

Diagnose why a Linux distro in a btrfs+LUKS multi-boot setup won't boot — when you're running a *different* distro on the same machine and need to inspect the target offline.

## When to Use
- A distro hangs at boot (splash screen, black screen, spinner)
- No LUKS password prompt appears
- Drops to emergency shell or dracut shell
- Kernel loads but root mount or init fails

## Step 0: Confirm the boot stage (CRITICAL)

Before touching any logs, establish WHERE the boot stalls. Ask the user to describe exactly what they see:

| Symptom | Stage | Where to look |
|---|---|---|
| GRUB doesn't appear / can't find kernel | GRUB | /boot partition, grub.cfg |
| Kernel loads but hangs before login | initramfs | LUKS config, Plymouth, dracut initramfs |
| Plymouth/splash screen frozen, no password box | initramfs (LUKS) | Plymouth + systemd-ask-password |
| Root mounts but services/display fail | init/userspace | journal, display-manager logs |

**Pitfall**: Plymouth splash screen looks similar to a frozen login screen. "Can't enter password" could mean LUKS prompt (early boot) or display manager (late boot) — they are entirely different failure domains. Do NOT start investigating display-manager logs if the user is stuck before root mount. Ask explicitly: "Do you see a logo/spinner? Text console? Cursor?"

## Step 1: Mount the target distro's subvolumes

This user's setup: all distros share `/dev/mapper/root` (LUKS on nvme0n1p2), each under btrfs subvols:

```
SYSTEM/<distro>/@        ← root
SYSTEM/<distro>/@var     ← /var
SYSTEM/<distro>/@opt     ← /opt (sometimes)
DATA/Home/<distro>       ← /home
```

```bash
# List subvolumes to find the target
sudo btrfs subvolume list /path/to/mounted/btrfs | grep <distro>

# Mount root subvol
sudo mount -o subvol=/SYSTEM/<distro>/@ /dev/mapper/root /mnt/target

# Mount var subvol (for logs, package history)
sudo mount -o subvol=/SYSTEM/<distro>/@var /dev/mapper/root /mnt/target/var
```

/boot is usually a separate vfat partition (nvme0n1p1, mounted at /efi on Guix). Kernel, initrd, and grub.cfg live there, shared across distros.

## Step 2: Check package-manager history for install-time errors

The most common root cause for cross-distro chroot installs: dracut ran in the wrong environment during kernel package installation.

```bash
# openSUSE
sudo grep -E "dracut|btrfs|initrd|error|failed|command not found" \
  /mnt/target/var/log/zypp/history

# Fedora
sudo grep -E "dracut|initramfs|error" /mnt/target/var/log/dnf.log
```

Key error patterns that indicate broken initramfs generation:
- `btrfs: command not found` in dracut-functions.sh → initramfs generated in host env lacking btrfs-progs
- `ln: failed to create symbolic link '/boot/initrd': Operation not permitted` → /boot wasn't properly mounted during install

## Step 3: Analyze initramfs contents

The initramfs is a concatenation of: uncompressed cpio (microcode) + zstd-compressed cpio (main). Guix lacks `cpio` and `journalctl` — use the Python parser in `references/initramfs-analysis.md`.

What to verify inside the initramfs:
1. `etc/cmdline.d/20-crypt.conf` — should contain `rd.luks.uuid=luks-<UUID>` matching the encrypted partition
2. `etc/cmdline.d/20-root-dev.conf` — should have `root=UUID=...` matching the decrypted btrfs UUID + correct subvol
3. `usr/lib/dracut/modules.txt` — should list `crypt`, `plymouth`, `dm`, `rootfs-block`
4. Plymouth theme files under `usr/share/plymouth/themes/`

## Step 4: Plymouth and LUKS password prompt

When kernel cmdline has `quiet splash`, Plymouth owns the LUKS password display via `systemd-ask-password-plymouth.service`. The flow:

```
kernel boots → dracut parses rd.luks.uuid → systemd-cryptsetup asks for password
  → systemd-ask-password-plymouth.path detects /run/systemd/ask-password not empty
  → systemd-tty-ask-password-agent --watch --plymouth sends prompt to plymouthd
  → plymouth renders password entry box on splash screen
```

If Plymouth fails to render (bad theme, DRM issue, initramfs built wrong), the password prompt never appears and boot hangs silently.

### Immediate workaround (prepare before reboot)

Edit GRUB at boot time (press `e`), append to the `linux` line:
```
plymouth.enable=0
```
This forces the LUKS prompt to the text console. Boot proceeds normally.

### Permanent fix options

**Option A — disable Plymouth permanently** (simplest):
Edit `/etc/default/grub`, change `GRUB_CMDLINE_LINUX_DEFAULT` to include `plymouth.enable=0` instead of `quiet splash`. Regenerate grub config.

**Option B — regenerate initramfs from within the target system** (fixes root cause):
Boot into the target (using Option A workaround), then:
```bash
dracut --force --regenerate-all
grub2-mkconfig -o /boot/grub2/grub2.cfg   # openSUSE
```
This regenerates initramfs with the correct tools available (btrfs-progs, plymouth modules).

## Pitfalls

- **Cross-distro chroot install breaks dracut**: `zypper --root /mnt` or `dnf --installroot` runs dracut hooks in the *host* environment. If the host (e.g. Guix) lacks the target's btrfs-progs, the initramfs is generated incorrectly. Always plan to regenerate initramfs on first boot into the target.
- **Guix lacks standard Linux tools**: No `cpio`, `journalctl`, `lsinitrd`. Use Python for cpio parsing, `strings` for journal extraction.
- **grub.cfg is on vfat /boot (root-owned)**: need sudo to edit/backup. Always `sudo cp grub.cfg grub.cfg.bak.$(date +%Y%m%d)` before modifying.
- **`${localstatedir}` in .service files**: dracut ships systemd units with literal `${localstatedir}` — this is normal, dracut handles it at runtime. Do NOT mistake it for a broken variable expansion.
- **Two initrds with same timestamp**: when dracut regenerates, it updates all kernel initrds at once. Same timestamp doesn't mean same content — verify by extracting and comparing.

## References
- `references/initramfs-analysis.md` — Python script for parsing dracut initramfs without cpio; diagnostic checklist for what to look for inside the initramfs.
