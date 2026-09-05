<context-index version="1">

<!-- 领域上下文路由表：只回答「什么时候读哪个文件」，域内容以各文件为准，不在此重复。
     识别到匹配任务时主动 Read 对应 file 全文；未匹配任何条目的会话只用 00-core 通用原则。 -->

<domain name="coding" file="domains/coding.md">
	<when>git 仓库内的编码、重构、调试、提交任务。zcode / omp / hermes 端由
	context-select.sh 自动注入，无需手动拉取；crush 端无注入机制，识别到
	编码任务时手动 Read 本文件。</when>
</domain>

</context-index>
