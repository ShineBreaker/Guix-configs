# Langpack / Resource-Merge Package Pattern

> **Pattern class:** wrapping an existing Guix package with `inherit + trivial-build-system + union-build` to add external resources (langpack .deb, theme archive, extension zip, icon pack) into the existing package's store layout.

---

## 1. When this pattern applies

Use this pattern when **all** of the following are true:

- An existing Guix package (often LibreOffice / Firefox / Chromium / Thunderbird / GIMP / Inkscape) is missing a resource — language pack, icon theme, spell-check dictionary, extension — that is officially distributed **separately** from the main binary.
- The resource is meant to live inside the application's install layout (e.g. `$prefix/lib/<app>/program/resource/<lang>/`), not at the user level (`~/.config/<app>/`).
- The application's runtime resource lookup is **relative to argv[0]** or a hard-coded bootstrap path that resolves inside the application's store path — not via `XDG_DATA_DIRS` or `XDG_CONFIG_DIRS`.

Skip this pattern (use a different approach) when:

- Resources can go to `~/.config/<app>/` (e.g. KDE themes, GNOME shell extensions via `gnome-shell-extension` package). Those work fine as separate packages.
- The upstream builds the resource in by default with `--with-lang=<lang>` — just patch the upstream package's configure-flags and skip this pattern entirely.
- The user only needs a few files in `share/` (e.g. `share/fonts/`, `share/icons/`) — those are reachable via `XDG_DATA_DIRS`, can be a separate `propagated-input`.

## 2. Why "separate package with `propagated-input`" does NOT work

It is tempting to define a `libreoffice-langpack-zh-cn` package whose output is just `share/registry/Langpack-zh-CN.xcd` + `share/registry/res/*.xcd` + `share/autotext/zh-CN/`, and add it as a sibling package so profile-derivation's `union-build` merges it in. **This does not work** for resources that must live inside the application's store.

Confirmed for LibreOffice 25.x (2026-06):

| Lookup mechanism | Reaches profile's `share/` via `XDG_DATA_DIRS`? | Reaches profile's `lib/<app>/`? |
|---|---|---|
| `fundamentalrc`'s `${ORIGIN}/..` (= `$store/lib/libreoffice/`) | ❌ no | ❌ no |
| Free-config-file scan via `XDG_DATA_DIRS` | ✅ yes | n/a |
| `XDG_CONFIG_HOME` / `~/.config/<app>/` | n/a | n/a (user-level) |

`profile-derivation` builds `share/` as a union of all packages' `share/` (because Guix's `search-paths` mechanism + `XDG_DATA_DIRS` lists them). But `lib/<app>/` is **linked as a single symlink to one package's store** — profile union does not reach inside it.

Conclusion: resources that need to be inside the application's store path **must be merged into the application's store directly**, by wrapping the application's package.

## 3. The wrapping pattern

```
┌─────────────────────────────────────────────────────────┐
│  existing: <app> (libreoffice etc.)                     │
│  → store/<hash>-<app>-<ver>/lib/<app>/...               │
└─────────────────────────────────────────────────────────┘
                          │
                          │ (inherit)
                          ▼
┌─────────────────────────────────────────────────────────┐
│  <app>-langpack-<lang>                                  │
│  (inherit <app>)                                        │
│  (source <langpack-tarball>)                            │
│  (build-system trivial-build-system)                    │
│  (arguments #:builder ...)                              │
│                                                         │
│  builder:                                               │
│    1. copy-recursively <app> → output  (full store copy)│
│    2. unpack langpack tarball                           │
│    3. union-build specific subdirs:                     │
│       - output/lib/<app>/program/resource/<lang>        │
│       - output/lib/<app>/share/registry                 │
│       - output/lib/<app>/share/autotext                 │
└─────────────────────────────────────────────────────────┘
```

### 3.1 Why `trivial-build-system` (not `gnu-build-system`)

The langpack is just files to be copied and merged; no configure/build/install phases. `trivial-build-system` gives you a single `#:builder` gexp where you run exactly the commands you need. Same pattern is used for `librewolf-nongnu` and other "wrapper" packages in jeans.

### 3.2 Why `copy-recursively` is acceptable here

- The source store path (e.g. `$libreoffice` resolved as a build input) is read-only but its files are normal regular files — `copy-recursively` works fine.
- The output is a fresh, read-write directory tree in the build sandbox.
- `guix build` will not re-execute the langpack's transitive deps (e.g. `cmake`, `boost`) — they're all available as substitutes via the existing libreoffice input.

### 3.3 What to union (and what NOT)

Always include in union (these are the ones LibreOffice's URE bootstrap reads):

- `program/resource/<lang>/LC_MESSAGES/*.mo` — UI string translations
- `share/registry/Langpack-<lang>.xcd` — registry entry declaring language as installed
- `share/registry/res/fcfg_langpack_<lang>.xcd` — fact declarations for langpack
- `share/registry/res/registry_<lang>.xcd` — actual localized registry data
- `share/autotext/<lang>/` — AutoText templates

Optional (include if present in the .deb):

- `share/registry/cjk_<lang>.xcd` — CJK-specific spell-check config (libreoffice25.2-<lang>.deb)
- `share/readmes/` — localized READMEs (skipped by default to reduce store size)

NEVER union (would break the store or conflict with libreoffice's own files):

- `program/*.bin` or other binaries — the langpack doesn't contain these
- `program/fundamentalrc` / `bootstraprc` — would override LibreOffice's core bootstrap
- `share/registry/main.xcd` or similar — would replace rather than extend

### 3.4 Collision handling

`union-build` (from `(guix build union)`) handles collisions as follows:

- **directory ⊕ directory** → recursive merge (this is what we want for `program/resource/<lang>/`, `share/registry/`)
- **file ⊕ file** → default `resolve-collision` calls `last-wins` (the langpack file overrides the existing one if names collide; harmless because LibreOffice's existing files are en-US and don't share names with zh-CN)
- **directory ⊕ file** → **error** ("union-build: collision between file and directories"). Verify the langpack's `share/registry/` only contains files, not conflicting paths.

## 4. TDF langpack .deb internals (reference)

The Document Foundation's official langpack structure is the same across LibreOffice 7.x / 24.x / 25.x:

```
LibreOffice_<fullver>_Linux_<arch>_deb_langpack_<lang>.tar.gz
└── LibreOffice_<fullver>_Linux_<arch>_deb_langpack_<lang>/
    └── DEBS/
        ├── libobasis<shortver>-<lang>_<fullver>-<rev>_<arch>.deb
        │   ├── program/resource/<lang>/LC_MESSAGES/*.mo   ← UI strings
        │   ├── share/registry/Langpack-<lang>.xcd          ← declares language installed
        │   ├── share/registry/res/fcfg_langpack_<lang>.xcd ← fact declarations
        │   ├── share/registry/res/registry_<lang>.xcd      ← localized registry
        │   └── share/autotext/<lang>/                      ← AutoText templates
        └── libreoffice<shortver>-<lang>_<fullver>-<rev>_<arch>.deb
            ├── share/registry/cjk_<lang>.xcd              ← CJK spell-check config
            └── share/readmes/                              ← localized READMEs (optional)
```

Where:

- `<shortver>` = first 3 version components (e.g. `25.2` for fullver `25.2.5.2`)
- `<fullver>` = full version with all dots (e.g. `25.2.5.2`)
- `<lang>` = locale code in LibreOffice's format (e.g. `zh-CN`, not `zh_CN`)

**Note on directory vs locale code:** langpack `.deb` uses both forms — directory `program/resource/zh_CN/` (POSIX form, with underscore) vs registry entries `Langpack-zh-CN.xcd` (BCP-47 form, with hyphen). They are NOT interchangeable. The directory is `zh_CN`; the registry files are `zh-CN`.

### 4.1 URL template

```
https://download.documentfoundation.org/libreoffice/stable/<fullver>/deb/x86_64/LibreOffice_<fullver-without-dots>_Linux_x86-64_deb_langpack_<lang>.tar.gz
```

Where `<fullver-without-dots>` keeps all dots (e.g. `25.2.5` for the fullver `25.2.5.2`).

If the primary URL 404s (older versions get archived), `guix download` automatically falls back to `web.archive.org` mirror — that's transparent, no code change needed.

## 5. Package template (minimal but complete)

```scheme
(define-public libreoffice-langpack-zh-cn
  (package
    (inherit libreoffice)
    (name "libreoffice-langpack-zh-cn")
    ;; CRITICAL: version MUST match the inherited libreoffice's version,
    ;; otherwise the .deb internal paths (<shortver>) won't align.
    (version "25.2.5.2")
    (source
     (origin
       (method url-fetch)
       (uri (string-append
             "https://download.documentfoundation.org/libreoffice/stable/"
             "25.2.5/deb/x86_64/"
             "LibreOffice_25.2.5_Linux_x86-64_deb_langpack_zh-CN.tar.gz"))
       (sha256
        (base32 "0iw26lqa0rhqzjilsvaymdgcg4x0yb02f3v2lapgkv1grr14qpgg"))))
    (build-system trivial-build-system)
    (arguments
     (list
      #:modules '((guix build utils)
                  (guix build union)
                  (srfi srfi-1))
      #:builder
      #~(begin
          (use-modules (guix build utils)
                       (guix build union)
                       (srfi srfi-1))

          (let* ((out #$output)
                 (lo-prefix (string-append out "/lib/libreoffice"))
                 (libobasis-deb "/tmp/lo-libobasis-root/opt/libreoffice25.2")
                 (lo-deb        "/tmp/lo-lo-root/opt/libreoffice25.2"))

            ;; 1. Copy entire existing libreoffice store to output
            (copy-recursively #$libreoffice out)

            ;; 2. Extract both .deb files (each .deb is an `ar` archive
            ;;    containing data.tar.xz inside)
            (define (extract-deb-data deb-path dest-prefix)
              (let ((work (string-append "/tmp/deb-work")))
                (mkdir-p work)
                (with-directory-excursion work
                  (invoke "ar" "x" deb-path)
                  (mkdir-p dest-prefix)
                  (cond
                   ((file-exists? "data.tar.xz")
                    (invoke "tar" "xf" "data.tar.xz" "-C" dest-prefix))
                   ((file-exists? "data.tar.zst")
                    (invoke "tar" "--use-compress-program=unzstd"
                            "xf" "data.tar.zst" "-C" dest-prefix))))))
            (extract-deb-data "libobasis25.2-zh-cn_25.2.5.2-2_amd64.deb" "/tmp/lo-libobasis-root")
            (extract-deb-data "libreoffice25.2-zh-cn_25.2.5.2-2_amd64.deb" "/tmp/lo-lo-root")

            ;; 3. Union each subdirectory individually
            (define (merge src)
              (when (file-exists? src)
                (union-build (string-append lo-prefix "/" (basename src))
                             (list (string-append lo-prefix "/" (basename src))
                                   src))))
            (merge (string-append libobasis-deb "/program/resource/zh_CN"))
            (merge (string-append libobasis-deb "/share/registry"))
            (merge (string-append libobasis-deb "/share/autotext"))
            (merge (string-append lo-deb        "/share/registry"))))))
    (native-inputs (list tar gzip))
    (synopsis "LibreOffice bundled with Simplified Chinese language pack")
    (description
     "Wraps libreoffice with the official zh-CN language pack from TDF.
The pack is dual-licensed under MPL-2.0 and is sourced from
@url{https://download.documentfoundation.org/libreoffice}.")
    (home-page "https://www.libreoffice.org/")
    (license license:mpl2.0)
    (supported-systems '("x86_64-linux"))))
```

## 6. Common pitfalls

### 6.1 Version drift between `inherit` and `(version ...)`

If you set `(version "25.2.5.2")` but `libreoffice` gets bumped to `25.3.0.0` upstream, the langpack deb URL will fail (or worse, silently 404 and pull a different version). Either:

- Add a comment near `(version ...)` noting "MUST match upstream libreoffice version"
- Use a Guile expression to derive from `libreoffice`: `(version (package-version libreoffice))` — cleaner, auto-updates.

### 6.2 `web.archive.org` fallback vs primary mirror

`guix download` tries primary → archive.org automatically on 404. The base32 hash is still computed over the actual downloaded bytes — but `web.archive.org` may serve slightly different bytes than primary (different compression metadata), so the hash is stable only because it's a fresh download. Once cached, the same hash is reproducible.

### 6.3 `union-build` collision error: "collision between file and directories"

Means you tried to union a directory into a location that already has a file (or vice versa). Examples:

- `(merge "/some/path")` where `/some/path` is a file in libreoffice but a directory in langpack → fail
- Langpack's `share/registry/Langpack-zh-CN.xcd` collides with libreoffice's `share/registry/Langpack-en-US.xcd` — these are different filenames, so OK (file ⊕ file with different names = fine, just two distinct entries).

### 6.4 `chmod #o444` after write — store corruption

`copy-recursively` of libreoffice's store paths: those files may be `read-only` in the source store. `copy-recursively` doesn't preserve source permissions — they become `0644` in destination (writable by owner). That's fine, but the build daemon may try to mark them `0444` before sealing. Don't pre-`chmod` to `444` yourself; let the daemon handle it.

### 6.5 `no SUBSTITUTE available` after adding the package

Substitutes are built by CI for every guix package. Your langpack wrapper is **new and private to jeans** — there will be no substitute until you publish the build to a substitute server. Local build is required on first deployment. Cost is dominated by the inherited libreoffice's inputs (libreoffice itself is a substitute, but its propagated inputs like `libreoffice-icu`, `libreoffice-script-provider-bsh` etc. may need local build on first install).

Mitigation: do `blue home --dry-run` first to confirm drv generates correctly without trying to download anything that doesn't exist.

### 6.6 `propagated-inputs` to the wrapped package

**Don't add `(propagated-inputs (list libreoffice))`** to your wrapper. It's already pulling libreoffice via `inherit`'s `inputs` chain. Adding `propagated-inputs` would cause profile to install BOTH the wrapper AND libreoffice separately, wasting disk and creating `soffice` PATH ambiguity.

## 7. Verification recipe

After building, run these in order to confirm the langpack is actually loaded:

```bash
# 1. Build succeeds
guix build -L modules libreoffice-langpack-zh-cn

# 2. Verify the output contains the langpack files
STORE=$(guix build -L modules libreoffice-langpack-zh-cn)
ls "$STORE/lib/libreoffice/share/registry/Langpack-zh-CN.xcd"     # should exist
ls "$STORE/lib/libreoffice/share/registry/res/fcfg_langpack_zh-CN.xcd"  # should exist
ls "$STORE/lib/libreoffice/program/resource/zh_CN/LC_MESSAGES/" | head  # 33 .mo files

# 3. Deploy via home (or system) reconfigure
blue home    # or `blue rebuild` if it's a system package

# 4. Run libreoffice with explicit language env to test
LANG=zh_CN.UTF-8 soffice --version   # version prints in English but locale is loaded
soffice --help                         # if language works, the UI test is next

# 5. UI test (manual)
#    Open Tools → Options → Language Settings → Languages → User Interface
#    There should be a "Simplified Chinese" entry in the dropdown.
#    Switch to it and restart soffice — menus should now be in Chinese.

# 6. Confirm registry files are wired correctly
soffice --headless --convert-to pdf /tmp/test.docx 2>&1 | head
```

## 8. Upgrade checklist

When upstream libreoffice bumps its version, the langpack wrapper must be updated:

1. `blue pull && blue update` to get the new channels (libreoffice version bump is auto-pulled).
2. Check the new libreoffice version: `guix time-machine --channels=source/channel.lock -- package -A libreoffice`.
3. Update `<langpack>.scm`:
   - `(version "X.Y.Z")` → new version
   - URL `<fullver-without-dots>/deb/x86_64/LibreOffice_<fullver-without-dots>_...` → new
   - `<shortver>` in deb file names (e.g. `libobasis25.3-zh-cn_*`) → new
   - `<shortver>` in `opt/libreoffice<shortver>/` extraction paths in builder → new
   - `base32` hash → recompute with `guix download <url>`
4. `maak build libreoffice-langpack-zh-cn` to confirm.
5. `blue home` to deploy.

If you used `(version (package-version libreoffice))` instead of hardcoded, only the URL, hash, and `<shortver>` constants need touching.

## 9. Extending this pattern to other apps

The same pattern works for any app whose bootstrap hardcodes resource paths relative to argv[0]:

| Application | Resource file to inspect | Path pattern |
|---|---|---|
| Firefox / librewolf | `omni.ja` + `chrome.manifest` | `lib/<app>/<app>/omni.ja` |
| Chromium / ungoogled-chromium | `chrome.manifest`, `resources.pak` | `lib/<app>/chrome.pak` |
| Thunderbird | `omni.ja` (same as Firefox) | `lib/thunderbird/omni.ja` |
| GIMP | gimpressionist / script-fu data | `lib/gimp/<ver>/...` |
| Inkscape | extensions/, palettes/, templates/ | `share/inkscape/extensions/` |

For Firefox-family apps, modifying `omni.ja` is more invasive than union — see `references/` in `librewolf-nongnu` (browser.scm in jeans) for the dereference → chmod → python-script → recompress pattern.

## 10. When NOT to use this pattern (decision tree)

```
Need to add resources to a Guix package.
│
├─ Resource lives in ~/.config/<app>/ at runtime?
│   └─ YES → Just provide a separate package + user-side config file.
│           (e.g. emacs packages with autoloads)
│
├─ Resource is in share/<app>/ and reachable via XDG_DATA_DIRS?
│   └─ YES → Make a separate package. Profile union handles it.
│           (e.g. icons, fonts, mime types)
│
├─ Upstream supports --with-lang= / --enable-i18n configure flag?
│   └─ YES → Patch upstream's libreoffice.scm instead.
│           (Higher work upfront, cleaner long-term.)
│
├─ Resource needs to be inside $prefix/lib/<app>/ at runtime?
│   └─ YES → USE THIS PATTERN (inherit + trivial-build-system + union).
│           (LibreOffice langpacks, Firefox langpacks, Chromium extensions)
│
└─ Resource is itself a self-contained binary (no shared install layout)?
    └─ YES → Plain pack-guix pattern.
            (e.g. Android Studio plugins, standalone JVM apps)
```