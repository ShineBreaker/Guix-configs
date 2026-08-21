# Rust packaging patterns — compile-time config injection & cargo-build-system input labels

Patterns from packaging Rust crates that use compile-time environment
variables (`option_env!()`, `env!()`) for configuration, and the
cargo-build-system input-label resolution mechanics. Pairs with
`jeans-channel-workflow` §2.

---

## 1. Compile-time config via `option_env!()` / `env!()` — the NixOS-path trap

### The pattern

Rust programs targeting non-FHS systems (NixOS, Guix) frequently use
compile-time environment variables to bake in system-specific paths:

```rust
const DEFAULT_FOO: &CStr = unsafe {
    CStr::from_bytes_with_nul_unchecked(concat_slices!([u8]:
        match option_env!("DEFAULT_FOO") {
            Some(path) => path,
            None => "/nixos/specific/default/path",  // ← upstream's default
        }.as_bytes(),
        b"\0"
    ))
};
```

`option_env!("VAR")` reads the env var **at compile time** and bakes the
value into the binary as a literal. If unset, it returns `None` and the
fallback (often a NixOS path like `/run/current-system/sw/...`) is used.

`env!("VAR")` is the stricter variant — it's a compile error if the var
is unset.

### The failure mode

When a Rust package is built without setting the relevant env var, the
binary silently bakes the upstream's NixOS default path. At runtime, code
that uses this baked constant (e.g., opening a file at that path) hits
`ENOENT` (Posix error 2) and panics.

### Diagnosis recipe

1. **Identify the panic site.** The Rust panic message includes
   `src/file.rs:LINE:COL`. Fetch the exact upstream source at the tagged
   version and look at that line.

2. **Check if the failing call uses a `const` defined via `option_env!()`.**
   Grep the source for `option_env!` / `env!` near the panic site.

3. **Confirm the baked value.** Use `strings` on the compiled binary:
   ```bash
   strings /gnu/store/*-<pkg>-<ver>/bin/<pkg> | grep -E "nix|/run/current|<suspected-path>"
   ```
   If you see the NixOS path baked in, the env var was not set at build time.

4. **Check how upstream's nixpkgs derivation sets it.** Fetch
   `https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/<first-two>/<name>/package.nix`
   and look for `env = { ... }` or `preBuild = ''export ...''`.

### The fix

Set the env var in an `add-before 'build` phase, sourcing the correct
Guix store path from build inputs:

```scheme
(add-before 'build 'set-compile-time-config
  (lambda* (#:key inputs #:allow-other-keys)
    (let ((glibc (assoc-ref inputs "glibc")))
      (setenv "DEFAULT_NIX_LD"
              (string-append glibc "/lib/ld-linux-x86-64.so.2")))))
```

**Critical:** the input label must match what cargo-build-system actually
passes. See §2 below.

### Concrete instance: nix-ld 2.0.6 (2026-08-12)

- **Panic:** `[nix-ld] FATAL: panicked at src/main.rs:187:55: called Result::unwrap() on an Err value: Posix(2)`
- **Panic site:** `let loader = elf::ElfHandle::open(nix_ld, pagesz).unwrap();`
- **Root cause:** `nix_ld` falls back to `DEFAULT_NIX_LD` constant when
  `NIX_LD` env var is unset. That constant uses `option_env!("DEFAULT_NIX_LD")`
  with fallback `/run/current-system/sw/share/nix-ld/lib/ld.so` (NixOS path,
  doesn't exist on Guix).
- **Fix:** bake Guix glibc's `ld-linux-x86-64.so.2` store path at compile time.

```scheme
;; In arguments #:phases, add-before 'build:
(lambda* (#:key inputs #:allow-other-keys)
  ...
  (let ((glibc (assoc-ref inputs "glibc")))
    (setenv "DEFAULT_NIX_LD"
            (string-append glibc "/lib/ld-linux-x86-64.so.2"))))

;; And add glibc to native-inputs:
(native-inputs (list glibc))
```

**Why native-inputs not inputs:** For a native build (no cross-compilation),
cargo-build-system merges both into `build-inputs`, which is what the build
phase sees as the `inputs` alist. `native-inputs` is semantically correct
(glibc is a build-time dependency for path resolution, not a runtime dep of
the `#![no_std]` binary).

---

## 2. cargo-build-system input-label resolution

### How labels work

When you write `(native-inputs (list glibc))` or
`(inputs (list foo bar))`, Guix's `lower` expands each package into an
input tuple `(label package)` or `(label package sub-drv-name)`. The
**label defaults to the package's `name` field** (e.g., `glibc`'s label is
`"glibc"`).

### What the build phase sees

cargo-build-system's `lower` (in `guix/build-system/cargo.scm`) for a
**native build** (target = #f):

```
host-inputs:  source + crate sources (no regular inputs)
build-inputs: cargo + rustc + native-inputs + inputs + standard-packages
```

The `cargo-build` builder then merges `host-inputs` + `build-inputs` into
the `inputs` alist passed to each build phase. So in a build phase:

```scheme
(lambda* (#:key inputs #:allow-other-keys)
  (assoc-ref inputs "glibc"))   ; ← works if glibc is in native-inputs or inputs
```

### The dual-label gotcha

`standard-packages` (from gnu-build-system) already includes glibc, but
labeled as `"libc"` (not `"glibc"`). So the inputs alist may contain
**both** keys pointing to the same store path:

```
glibc  → /gnu/store/...-glibc-2.41
libc   → /gnu/store/...-glibc-2.41   ; same path, different label
```

Using `(assoc-ref inputs "glibc")` is correct for explicitly-added glibc.
Using `"libc"` would also work but is less explicit (depends on
standard-packages behavior).

### Verification technique (when guix build is blocked by network)

When `guix build <pkg>` fails because crate tarball downloads are blocked
(e.g., crates.io API returns 403 due to regional/proxy issues), verify
the package definition correctness without a full build:

**Step 1 — Confirm compile-time injection works** (bypass guix, use cargo
directly):

```bash
# Clone the upstream source
git clone --depth=1 --branch <version> <upstream-url> /tmp/verify-<pkg>
cd /tmp/verify-<pkg>

# Set the same env vars the guix build phase would set
export RUSTC_BOOTSTRAP=1
export NIX_SYSTEM=x86_64_linux
export DEFAULT_NIX_LD=$(ls /gnu/store/*-glibc-*/lib/ld-linux-x86-64.so.2 | head -1)
export CC=gcc   # if build-dependencies need cc-rs

cargo build --release 2>&1 | tail -5

# Verify the baked constant
strings target/release/<pkg> | grep -E "<expected-pattern>"
```

**Step 2 — Confirm build-phase input resolution** (use guix with a
throwaway verification package that dumps `inputs` keys then exits):

Write a minimal package using `cargo-build-system` with
`#:cargo-inputs '()` (bypasses crate closure expansion), `native-inputs
(list glibc)`, and a custom phase that runs right after `set-paths`:

```scheme
(add-after 'set-paths 'dump-inputs
  (lambda* (#:key inputs #:allow-other-keys)
    (let ((g (assoc-ref inputs "glibc")))
      (format #t "glibc=~a~%" g)
      (format #t "ld exists: ~a~%"
              (file-exists? (string-append g "/lib/ld-linux-x86-64.so.2"))))))
```

Build it with `guix build -e '(load "/tmp/verify.scm")'`. The build will
fail at a later phase (no Cargo.toml to compile) — that's expected; the
dump phase runs before that and prints the verification result.

This two-step approach separates "the Rust code compiles correctly with
the right config" from "the Guix package definition correctly passes the
config to the build," catching both classes of bugs without needing the
full dependency closure to download.
