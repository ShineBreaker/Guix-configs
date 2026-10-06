# udev / hidraw 设备权限（WebHID 与用户态驱动）

> 场景：浏览器网页驱动（WebHID）、厂商配置工具或其他用户态程序要访问 `/dev/hidrawN`，当前用户却打不开节点。
> 规则落点是 `source/config.org` 的 `udev-static-rules` 块；udev 规则属**系统层**，agent 只能 `blue --dry-run rebuild`，固化必须用户跑 sudo。

## 1. 权限模型

- hidraw 节点**默认不带任何 tag**（不像 `input` 事件节点被 `50-udev-default.rules` 之类波及），`ls -l` 显示 `crw------- root root`。某些设备能打开，是因为**别的规则**已经给它打了 tag（例：数位板靠 `70-opentabletdriver.rules`）。
- 授权方式二选一，语义差别很大：

| 写法 | 效果 | 适用 |
| --- | --- | --- |
| `MODE="0666"` | 本机**所有**用户可读写该节点 | 只在确需共享时用；单为一个浏览器需求付这个代价不值 |
| `TAG+="uaccess"` + `TAG+="udev-acl"` | elogind 的 `elogind-uaccess-command` 给**当前活动会话用户**加 ACL（`ls -l` 出现 `+`） | 默认选择，上游对 WebHID 的推荐做法 |

- `TAG=="uaccess"` 会经 `71-seat.rules` 自动补 `seat` tag，两个 tag 同时加是安全的。
- **WebHID 只有 Chromium 系实现**（Chrome / Edge / Brave / Chromium），Firefox 没有——动手前先确认用户用的是哪种浏览器。

## 2. 规则写法（一个设备一条 service）

```
KERNEL=="hidraw*", ATTRS{idVendor}=="28e9", ATTRS{idProduct}=="31ff", TAG+="uaccess", TAG+="udev-acl"
```

- `ATTRS{...}` 沿 sysfs **父链上溯**到 usb_device 层匹配，所以一条规则覆盖该设备的全部接口（键盘 / 鼠标 / 厂商集合各有 hidraw 节点，一并授权）。
- `KERNEL=="hidraw*"` 限定只动 hidraw，不碰 event 节点。
- VID/PID 从 `lsusb -d <vid>:` 或 `/sys/bus/usb/devices/<path>/{idVendor,idProduct}` 取；规则里大小写均可（udev 统一小写比较）。
- 命名沿用 `60-<设备名>.rules` 文件名前缀，`udev-rules-service` 的符号名用小写连字符（如 `'ichip-keyboard`）。
- 换设备 = 加一条，不要把多个厂商塞进同一条规则（难按设备撤销，也失去可读性）。
- 旧规则若是 `MODE="0666"`，顺手迁移到双 tag，并把迁移理由写进块旁 org 正文——下一个人会问为什么改。

## 3. 诊断流程（先定位，再动手）

1. **列出目标设备的全部 hidraw 节点**：

   ```bash
   for h in /sys/class/hidraw/hidraw*; do
     grep -l '0003:28E9:31FF' "$h/device/uevent" 2>/dev/null
   done
   ```

   （uevent 里 `HID_ID=0003:VID:PID` 的字母是**大写**。）

2. **看现有 tag**（最快一步）：

   ```bash
   udevadm info --query=property --name=/dev/hidrawN | grep -E 'TAGS|DEVNAME'
   ```

   含 `:seat:uaccess:` = 已授权；`TAGS` 为空或只有 `:seat:` = 需要加规则。

3. **对照一个已知能用的同类设备**（强证据）：本机鼠标 / 数位板的 hidraw 能打开，说明整条链路是通的，差异只在规则。跳过对照直接改规则，会在规则之外的地方浪费时间。

4. **直接探测**（最终判据，以当前用户身份）：

   ```bash
   python3 -c "import os; os.open('/dev/hidrawN', os.O_RDWR|os.O_NONBLOCK)"
   ```

   `PermissionError` = 未授权；能打开 = 已授权。写个小脚本一次探多个节点 + 一个已知可用节点做对照，比逐条手敲可靠。

5. 需要确认匹配键时用 `udevadm info -a -n /dev/hidrawN` 看 `ATTRS{idVendor}` 等属性落在哪一层父设备上（输出的第一段是设备自身，属性匹配要数准父设备段）。

**`udevadm test /sys/class/hidraw/hidrawN` 只是模拟**：不执行 RUN 程序、不写 `/run/udev/data`，只能看规则命中与最终 mode/tags，不能替代部署后的真实探测。

## 4. 部署与临时验证

- **正式**：改 `config.org` 的 `udev-static-rules` → `blue --dry-run rebuild`（agent 可跑）→ 用户 `sudo blue rebuild`（agent 禁跑 sudo）。
- **临时验证**（不动仓库、不动系统代）：把同一条规则写到 `/etc/udev/rules.d/60-<name>.rules`，然后

  ```bash
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=hidraw
  ```

  规则只对 add 事件生效，已有节点 `trigger` 不灵就**重新插拔**。`/etc` 下的改动下次系统代即丢，验证通过后仍要落 `config.org` 并让用户正式部署，最后复查 `/etc/udev/rules.d/` 的实际文件与源码一致。
- 块级编辑走 `blue block-show` / `blue block-replace` 时，注意 body 头两行陷阱（SKILL.md §9.2 坑 6）。

## 5. 为新设备复用旧设备配置

用户说"照我旧键盘那样弄"时，顺序固定：

1. `agenote search <设备类型> udev 权限` 找旧设备的落地记录（含当初为什么这么写）
2. `grep -n idVendor source/config.org` 定位旧设备的规则块
3. 复制一条，改 VID/PID，换符号名与规则文件名
4. `blue --dry-run rebuild` 验证
5. 提示用户 sudo 部署，并在汇报里明确区分「源码已落地」与「已生效」——udev 规则在用户跑完 rebuild 前，`/dev/hidraw*` 的权限一行都没变

