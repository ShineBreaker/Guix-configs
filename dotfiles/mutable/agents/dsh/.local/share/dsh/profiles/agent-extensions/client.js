// SPDX-License-Identifier: MIT
//
// agent-extensions client half — custom-shortcuts 的 DSH 等价物 + 服务生命周期按钮。
//
// pi/omp 里 Shift+Tab 把编辑器内容换成 /plannotator 再回键；DSH 的等价语义是
// 原生 /plan（进入 plan mode）/ /plan off（退出）。本模块在 conversation.input.left
// slot（list 型、session 作用域，composer 工具行左侧）挂一个隐形组件，把 Shift+Tab
// 捕获在本会话 composer 的捕获阶段——菜单打开时放行（Shift+Tab 仍归菜单仲裁）。
//
// 另在 conversation.session.header.actions（list 型）挂「清残留 / 重启」按钮，
// 命令经 remote.commands 桥到 host 侧 lifecycle.js 的 /dsh-kill-others、/dsh-restart。
//
// 不得挂 conversation.input.plan：那是 single 型槽位，已被核心 ui-plan 的 PlanChip
// 独占；抢先注册会把后激活的 ui-plan 挤成 "did not activate"，整页 boot 失败。
// left 槽是 list 型（多注册者并存），sessionId/useProjection 等 session 标准 kit
// 照常注入，仅 locked owner prop 不存在（按可选处理）。
//
// 手工写成 __ModuleLoader__.load 的 CJS factory 形态（与官方 client 模块同一
// 装载协议），无构建步骤；react 由客户端模块系统作为 external 提供。
//
// 注意：所有用到 ctx 的组件/函数都必须定义在 apply(ctx) 内部——factory 顶层
// 没有 ctx，闭包捕获不到会 ReferenceError（本文件曾把 ServiceControls 放顶层，
// 按钮一点就炸）。

window.__ModuleLoader__.load({
	id: "dsh-agent-extensions",
	factory: (require) => {
		var module = { exports: {} };
		var React = require("react");
		var useEffect = React.useEffect;
		var useRef = React.useRef;

		var NAME = "agent-extensions-client";
		var INJECT = ["slots", "remote", "remote.commands"];

		var BTN_STYLE = {
			border: "1px solid currentColor",
			borderRadius: "4px",
			background: "transparent",
			color: "inherit",
			fontSize: "11px",
			lineHeight: 1.4,
			padding: "2px 8px",
			cursor: "pointer",
			opacity: 0.75,
			whiteSpace: "nowrap",
		};

		function planActive(plan) {
			return !!plan && (plan.pending ? !plan.active : plan.active);
		}

		// 找本组件所在 composer 区域的容器（向上找第一个含 contenteditable 的祖先），
		// 把监听绑在容器上而不是 document，避免多会话/多视图并存时串台。
		function composerZone(el) {
			for (var node = el.parentElement; node; node = node.parentElement) {
				if (node.querySelector && node.querySelector('[contenteditable="true"]')) return node;
			}
			return null;
		}

		function menuOpen() {
			return document.querySelector('[role="menu"],[role="listbox"],[data-dsh-menu]') !== null;
		}

		function apply(ctx) {
			function runCommand(sessionId, line) {
				return Promise.resolve(ctx.remote.commands.execute(sessionId, line, [])).catch(function () {});
			}

			// 重启后旧 launch token 即失效；认证靠 .credentials.yaml 密钥签名的持久
			// cookie（30 天），故先剥掉 ?token= 再轮询复活刷新，避免带死 token 重载。
			function restartService(sessionId) {
				if (!window.confirm("重启 dsh web 服务？当前 agent 会话会中断，页面会自动重连。")) return;
				try {
					history.replaceState({}, "", location.pathname);
				} catch (e) {}
				runCommand(sessionId, "/dsh-restart");
				var waited = 0;
				var iv = setInterval(function () {
					waited += 1;
					if (waited > 120) {
						clearInterval(iv);
						window.alert("重启超时，请手动刷新页面");
						return;
					}
					fetch("/", { method: "HEAD", cache: "no-store" })
						.then(function (res) {
							if (res.ok) {
								clearInterval(iv);
								location.reload();
							}
						})
						.catch(function () {});
				}, 1000);
			}

			function ServiceControls(props) {
				var sessionId = props.sessionId;
				var busyState = React.useState(false);
				var busy = busyState[0];
				var setBusy = busyState[1];
				var onKill = function () {
					setBusy(true);
					runCommand(sessionId, "/dsh-kill-others").then(function () {
						setBusy(false);
					});
				};
				var onRestart = function () {
					restartService(sessionId);
				};
				return React.createElement(
					"span",
					{ style: { display: "inline-flex", gap: "4px", alignItems: "center" } },
					React.createElement(
						"button",
						{
							type: "button",
							style: BTN_STYLE,
							disabled: busy,
							title: "列出并 SIGTERM 本进程之外的所有 dsh 服务进程（残留测试实例）",
							onClick: onKill,
						},
						"清残留",
					),
					React.createElement(
						"button",
						{
							type: "button",
							style: BTN_STYLE,
							title: "重启当前 dsh web 服务（插件源码改动后生效所需）",
							onClick: onRestart,
						},
						"重启",
					),
				);
			}

			function PlanKeys(props) {
				var ref = useRef(null);
				var sessionId = props.sessionId;
				var useProjection = props.useProjection;
				var plan = typeof useProjection === "function" ? useProjection("plan") : undefined;
				var active = planActive(plan);
				var locked = props.locked === true;

				useEffect(() => {
					var el = ref.current;
					if (!el) return;
					var zone = composerZone(el);
					if (!zone) return;
					var onKey = function (event) {
						if (event.key !== "Tab" || !event.shiftKey) return;
						if (event.ctrlKey || event.altKey || event.metaKey || event.isComposing) return;
						if (!sessionId || locked) return;
						if (menuOpen()) return;
						event.preventDefault();
						event.stopPropagation();
						Promise.resolve(
							ctx.remote.commands.execute(sessionId, active ? "/plan off" : "/plan", []),
						).catch(function () {});
					};
					zone.addEventListener("keydown", onKey, true);
					return () => zone.removeEventListener("keydown", onKey, true);
				}, [sessionId, active, locked]);

				return React.createElement("span", { ref: ref, style: { display: "none" } });
			}

			ctx.slots.inject("conversation.input.left", () =>
				ctx.slots.register(
					{ name: "conversation.input.left", id: "agent-extensions-plan-keys" },
					PlanKeys,
				),
			);

			// 服务生命周期按钮：header actions 是 list 型槽，带 id 并存即可。
			ctx.slots.inject("conversation.session.header.actions", () =>
				ctx.slots.register(
					{ name: "conversation.session.header.actions", id: "agent-extensions-lifecycle" },
					ServiceControls,
				),
			);
		}

		module.exports = { name: NAME, inject: INJECT, apply: apply };
		return module.exports;
	},
});
