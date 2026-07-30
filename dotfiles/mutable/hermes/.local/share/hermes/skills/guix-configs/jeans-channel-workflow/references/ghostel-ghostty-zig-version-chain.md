# Ghostel ↔ Ghostty Zig 版本连锁依赖（2026-07-30 实测）

## 现象

auto-update 脚本把 `emacs-ghostel` 从 0.45.0 升到 0.46.0 后，即使
`native-inputs` 里的 `zig-0.15` 同步改为 `zig-0.16`，构建仍然失败。

## 根因链

```
ghostel 0.46.0 build.zig
  └─ comptime 检查 required_zig = 0.16.0
       └─ native-inputs: zig-0.15 → zig-0.16 ← 第一步修复

ghostel 0.46.0 build.zig.zon
  └─ .ghostty = .{ .url = "github.com/ghostty-org/ghostty/archive/ab0b9da..." }
       └─ ghostty commit ab0b9da 的 build.zig.zon 声明 minimum_zig_version = "0.16.0"
            └─ ghostty 的依赖（libxev/vaxis/z2d/zig-objc/zig-js/uucode/zig-wayland/zf/gobject）
               全部是 zig-0.16 兼容版本，但 build scripts 仍调用 zig-0.15 API

ghostty 内联在 ghostel 的 ./deps/ghostty/ 目录
  └─ zig build 遍历 deps/ghostty/ 时执行 ghostty 的 build.zig
       └─ deps/ghostty/src/build/zig.zig:13:9:
          error: Your Zig version v0.16.0 does not meet the required build version of v0.15.2
       └─ deps/ghostty/pkg/zlib/build.zig:15:8:
          error: no field or member function named 'linkLibC' in 'Build.Step.Compile'
       └─ deps/uucode/build.zig:211:18:
          error: member function expected 3 argument(s), found 2
```

## 关键洞察

1. **ghostty 的 zig-0.16 迁移（issue #12228）** 在 2026-04 完成，但迁移后
   build scripts 的 API 调用（如 `linkLibC`、`b.modules.put` 签名）并未完
   全适配 zig-0.16。`minimum_zig_version = "0.16.0"` 声明的只是"能用 0.16
   编译"，不代表所有依赖的 build scripts 都通过 0.16 编译。

2. **ghostel 的 Guix 包通过 `./deps/ghostty/` 目录内联 ghostty 源码**，
   不走 ghostty 的官方 release tarball。`build.zig.zon` 里的 `.url` 指向
   `github.com/ghostty-org/ghostty/archive/<commit-hash>.tar.gz`，但 Guix
   build phase 把 tarball 解压到 `./deps/ghostty/`，再让 zig build 直接
   从源码目录构建 libghostty-vt。

3. **zig-0.16 API 破坏性变更**（`linkLibC` 字段移除、`environ_map` 字段
   移除、`b.modules.put` 签名从 2 变 3 参数）来自 zig 标准库重构，不是
   ghostty 自身的 bug。这意味着**无法通过 patch ghostty 的 build scripts
   来"修复"**——除非把所有依赖（libxev/vaxis/z2d/zig-objc/zig-js/uucode/
   zig-wayland/zf/gobject）全部同步更新到 zig-0.16 兼容版本。

## 修复决策树

```
ghostel 版本升级后 zig build 失败？
├─ 错误含 "ghostel requires exactly Zig 0.16.0, found 0.15.2"
│   └─ native-inputs: zig-0.15 → zig-0.16 → 重试
│       ├─ 仍失败，错误含 "linkLibC" / "environ_map" / "member function expected N argument(s)"
│       │   └─ vendored ghostty build scripts 与 zig-0.16 不兼容
│       │       └─ 不要继续调试 → revert 版本升级 → 报告用户
│       └─ 成功 → 完成
└─ 其他错误 → 正常排查
```

## 未来可行的修复路径

等 ghostty 1.4.0 正式发布后，ghostel 下一版本大概率会引用包含完整
zig-0.16 适配的 ghostty commit。届时升级 ghostel 即可自然解决。

如果必须提前修复：需要 patch `./deps/ghostty/` 下所有 build scripts 的
zig-0.16 API 调用（预计 20+ 文件），且每次 ghostel 升级都要重新 patch。
**不建议这样做**——工作量远大于等待上游发布。

## 诊断命令速查

```bash
# 查 ghostel 的 zig 版本要求
grep -A2 "required_zig" /gnu/store/*-emacs-ghostel-*/checkout/build.zig

# 查 vendored ghostty 的 zig 版本要求
cat /gnu/store/*-emacs-ghostel-*/checkout/deps/ghostty/build.zig.zon | grep minimum_zig_version

# 查 ghostty build scripts 是否有 zig-0.15 API 调用
grep -rn "linkLibC\|environ_map\|b.modules.put" /gnu/store/*-emacs-ghostel-*/checkout/deps/ghostty/
```