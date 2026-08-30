;;; modules/modes/rust.lisp — Rust
;;;
;;; rust-mode 镜像内建。LSP 走 rust-analyzer（stdio）。

(in-package :lem-user)

(vs-lsp-wire (vs$ :lem-rust-mode "RUST-MODE")
             "rust"
             '("Cargo.toml")
             '("rust-analyzer"))
