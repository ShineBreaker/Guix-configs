# Initramfs Analysis Without Standard Tools

Guix lacks `cpio`, `lsinitrd`, `lsinitramfs`, and `journalctl`. This reference provides Python-based alternatives.

## 1. Split + decompress initramfs

Dracut initramfs format: one or more uncompressed cpio archives (microcode) followed by one zstd-compressed cpio archive (main payload).

```python
import os

with open("/efi/initrd-<version>", "rb") as f:
    data = f.read()

cpio_magic = b'070701'  # newc format
pos = 0
while pos < len(data):
    if data[pos:pos+6] == cpio_magic:
        namesize = int(data[pos+94:pos+102], 16)
        filesize = int(data[pos+54:pos+62], 16)
        name = data[pos+110:pos+110+namesize-1].decode('ascii', errors='replace')
        name_end = pos + 110 + namesize
        name_end = (name_end + 3) & ~3
        data_end = name_end + filesize
        data_end = (data_end + 3) & ~3
        if name == 'TRAILER!!!':
            next_pos = data_end
            while next_pos < len(data) and data[next_pos] == 0:
                next_pos += 1
            # Detect compression
            magic = data[next_pos:next_pos+6]
            if magic[:4] == b'\x28\xb5\x2f\xfd':
                comp = 'zstd'
            elif magic[:6] == b'\xfd7zXZ\x00':
                comp = 'xz'
            elif magic[:2] == b'\x1f\x8b':
                comp = 'gzip'
            with open("/tmp/initrd-main.comp", "wb") as out:
                out.write(data[next_pos:])
            break
        pos = data_end
    else:
        break
```

Then decompress: `zstd -d initrd-main.comp -o initrd-main.cpio`

## 2. Extract files from cpio (Python)

```python
import os

infile = '/tmp/initrd-main.cpio'
outdir = '/tmp/initrd-content'
os.makedirs(outdir, exist_ok=True)

with open(infile, 'rb') as f:
    data = f.read()

magic = b'070701'
pos = 0
while pos < len(data):
    if data[pos:pos+6] != magic:
        break
    namesize = int(data[pos+94:pos+102], 16)
    filesize = int(data[pos+54:pos+62], 16)
    mode = int(data[pos+14:pos+22], 16)
    name = data[pos+110:pos+110+namesize-1].decode('ascii', errors='replace')
    name_end = pos + 110 + namesize
    name_end = (name_end + 3) & ~3
    file_start = name_end
    file_end = file_start + filesize
    file_end = (file_end + 3) & ~3
    if name == 'TRAILER!!!':
        break
    # Extract only interesting files
    lname = name.lower()
    if any(k in lname for k in ['crypt', 'luks', 'plymouth', 'cmdline', 'dracut']):
        outpath = os.path.join(outdir, name.lstrip('./'))
        os.makedirs(os.path.dirname(outpath) or '.', exist_ok=True)
        if mode & 0o170000 != 0o040000:  # not directory
            with open(outpath, 'wb') as out:
                out.write(data[file_start:file_end])
    pos = file_end
```

## 3. Extract text from binary journal (without journalctl)

```bash
sudo strings /mnt/target/var/log/journal/<machine-id>/system.journal | \
  grep -iE "lightdm|display.manager|greeter|plymouth|crypt|luks|failed|timeout" | \
  grep -v "dhcp\|NetworkManager"
```

This loses timestamps and ordering, but reveals error messages and service state transitions.

## 4. Diagnostic checklist: what to look for inside the initramfs

| File | What it should contain | Red flag if missing/wrong |
|---|---|---|
| `etc/cmdline.d/20-crypt.conf` | `rd.luks.uuid=luks-<UUID>` | Missing → LUKS partition won't be decrypted |
| `etc/cmdline.d/20-root-dev.conf` | `root=UUID=... rootfstype=btrfs rootflags=...,subvol=...` | Wrong UUID or subvol → root mount fails |
| `usr/lib/dracut/modules.txt` | Lists `crypt plymouth dm rootfs-block` | Missing plymouth → no password prompt on splash |
| `usr/share/plymouth/themes/` | Theme .plymouth files + PNGs | Missing → plymouthd crashes, no prompt rendered |
| `usr/bin/systemd-cryptsetup` | Binary (or symlink to it) | Missing → can't unlock LUKS at all |
| `usr/lib64/plymouth/renderers/drm.so` | DRM renderer plugin | Missing → plymouth can't draw to screen |

## 5. Comparing two initramfs versions

When investigating a kernel upgrade regression, extract both old and new initramfs and diff the key files:

```bash
diff /tmp/initrd-old-content/etc/cmdline.d/20-crypt.conf \
     /tmp/initrd-content/etc/cmdline.d/20-crypt.conf

diff /tmp/initrd-old-content/usr/lib/dracut/modules.txt \
     /tmp/initrd-content/usr/lib/dracut/modules.txt
```

Note: same timestamp on both initrds means dracut regenerated them in the same run — this is normal, not evidence they're identical.
