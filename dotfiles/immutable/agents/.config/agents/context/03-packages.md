<rules scope="package-management">

<rule name="软件包规范">
<critical>
禁止持久安装包，未安装的软件一律用一次性环境运行
</critical>
禁止一切写入 profile 的持久安装：`guix install`、`guix package -i/--install`、`nix-env -i/-iA/--install`、`nix profile install`
临时运行未安装的软件：
- Guix：`guix shell <pkg> -- <cmd>`（指定版本 `guix shell <pkg>@<ver> -- <cmd>`）
- Nix：`nix run nixpkgs#<pkg>` / `nix shell nixpkgs#<pkg> -c <cmd>`
- 开发环境：`guix shell -D <pkg>` / `nix develop`
</rule>

<rule name="高频收尾推荐">
若同一软件在本会话中经 shell/run 反复拉起（≥3 次），会话结束前主动向用户建议持久化安装（说明用途与建议位置，由用户决定），**不要自行安装**
</rule>

</rules>
