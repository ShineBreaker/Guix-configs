<context-index version="1">

<!-- 领域上下文路由表：按任务场景按需读取对应文件，未匹配条目仅遵循 00-core 通用原则。 -->

<domain name="coding" file="domains/coding.md">
	<when>Git 仓库内的编码、重构、调试与提交任务。zcode/omp/hermes/pi 端由 context-select.sh 自动注入；无自动注入机制的端手动读取本文件。</when>
</domain>

<domain name="verify" file="domains/verify.md">
	<when>任务验证、交付与完工汇报。判定校验对象是否为真实交付物与真实使用路径。</when>
</domain>

<domain name="agent-ops" file="domains/agent-ops.md">
	<when>不可逆操作、删除、凭据与跨会话状态变更。全平台恒定注入。</when>
</domain>

<domain name="dsh-sandbox" file="domains/dsh-sandbox.md">
	<when>DSH harness 会话（platform=dsh 自动注入）；遇到写入被拒、EROFS/只读报错、文件跨 bash 调用消失时。</when>
</domain>

</context-index>
