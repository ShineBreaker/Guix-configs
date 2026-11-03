// SPDX-License-Identifier: MIT
//
// agent-extensions lifecycle 半边：dsh web 服务的进程生命周期命令。
//
// 背景：插件源码改动（link: 部署的本地包）不热载——运行中的 host 持有旧模块
// 图，必须重启进程才生效。「什么时候该重启、哪些实例是残留」只能靠人肉 ps/ss
// 排查，所以把三件事收进斜杠命令，供命令面板与客户端按钮共用：
//
//   /dsh-services     列出全部 dsh 服务进程（pid/端口/启动时间/是否本进程）
//   /dsh-kill-others  SIGTERM 除本进程外的 dsh 服务进程（清残留测试实例）
//   /dsh-restart      重启本进程：有 supervisor 时委托给它，否则 watcher 自拉
//
// 重启为什么要分两种模式：进程被 shepherd/systemd 托管时，服务进程退出后
// supervisor 会**立刻自己**拉一个新的。此时再跑「等本 PID 死后 exec 原 argv」
// 的 watcher，就有两个进程抢同一个监听端口——抢输的那个退出，supervisor 见
// 状又拉一个，形成每几秒一次的 EADDRINUSE 振荡（2026-11-03 实测：3.5 秒一轮，
// 持续十几分钟，web.log 涨了几百条）。所以托管场景只发重启请求，由 supervisor
// 独占「停旧 + 起新」。
//
// 「dsh 服务进程」的判据：cmdline 指向 dsh/lib/bin.js，且在 ss -tlnp 的监听表
// 里有条目。CLI 短命令（dsh plugin 等）不监听端口，天然被排除；只匹配 cmdline
// 不够，因为 `dsh web` 起的服务进程（包装器最终 exec 的也是 CLI 本体）与一次性
// CLI 的 cmdline 形态相同。
//
// 重启不新开窗口也不走 `dsh web`：cookie 由 .credentials.yaml 持久化密钥签名
// （30 天），浏览器旧窗口断开重连即可，重启只需让同样的 bin.js 重新监听同端口。

import { spawn, spawnSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";

export const name = "agent-extensions-lifecycle";
export const inject = ["commands"];

/** pid → [ports] 监听表。ss 不可用时返回空 Map（调用方降级为 cmdline 判定）。 */
function listeningPorts() {
	const ports = new Map();
	try {
		const res = spawnSync("ss", ["-tlnpH"], { encoding: "utf8", timeout: 5000 });
		if (res.status !== 0) return ports;
		for (const line of res.stdout.split("\n")) {
			const local = line.match(/\S+:(\d+)\s+\S+/);
			const pid = line.match(/pid=(\d+)/);
			if (!local || !pid) continue;
			const key = Number(pid[1]);
			ports.set(key, [...(ports.get(key) ?? []), Number(local[1])]);
		}
	} catch {
		/* ss 缺失/超时 → 空表 */
	}
	return ports;
}

function argvOf(pid) {
	try {
		return readFileSync(`/proc/${pid}/cmdline`, "utf8").split("\0").filter(Boolean);
	} catch {
		return [];
	}
}

function startedAt(pid) {
	try {
		const stat = statSync(`/proc/${pid}`);
		return stat.birthtime?.getTime() ? stat.birthtime : stat.ctime;
	} catch {
		return undefined;
	}
}

/**
 * 全部 dsh 服务进程 [{pid, argv, ports, started, self}]。
 * 判据：argv 指向 dsh/lib/bin.js，且（监听 TCP 或首参是 web/serve 子命令）。
 */
export function dshServers() {
	const ports = listeningPorts();
	const rows = [];
	for (const name of readdirSync("/proc")) {
		if (!/^\d+$/.test(name)) continue;
		const pid = Number(name);
		const argv = argvOf(pid);
		const bin = argv[1] ?? "";
		if (!bin.includes("dsh") || !bin.endsWith("bin.js")) continue;
		const listening = ports.get(pid) ?? [];
		const firstArg = argv[2] ?? "";
		if (listening.length === 0 && firstArg !== "web" && firstArg !== "serve") continue;
		rows.push({ pid, argv, ports: listening, started: startedAt(pid), self: pid === process.pid });
	}
	return rows.sort((a, b) => a.pid - b.pid);
}

function describe(row) {
	const port = row.ports.length > 0 ? `:${row.ports.join(",:")}` : "(无监听)";
	const when = row.started ? row.started.toISOString().slice(5, 19).replace("T", " ") : "?";
	return `  pid=${row.pid} ${port} 启动于 ${when}${row.self ? " ← 本进程" : ""}`;
}

/** shell 单引号转义（respawn 脚本拼 argv 用）。 */
function shq(arg) {
	return `'${String(arg).replaceAll("'", "'\\''")}'`;
}

/** shepherd 里承载 web 服务的单元名。与 source/config.org 的服务名一致。 */
const SHEPHERD_UNIT = "dsh-web";

/**
 * 本进程若由 shepherd 托管，返回单元名；否则 null。
 *
 * 两层判据缺一不可：PPID 的 comm 是 shepherd（服务进程由 guix home shepherd
 * 直接拉起），且该 shepherd 里确实注册了 dsh-web。只认 PPID 会让手动 `dsh web`
 * 起的测试实例误按服务处理；只认 herd 则会让任何进程都去重启服务实例。
 */
function shepherdUnit() {
	try {
		if (readFileSync(`/proc/${process.ppid}/comm`, "utf8").trim() !== "shepherd") return null;
	} catch {
		return null;
	}
	const probe = spawnSync("herd", ["status", SHEPHERD_UNIT], { encoding: "utf8", timeout: 5000 });
	return probe.status === 0 ? SHEPHERD_UNIT : null;
}

export function apply(ctx, config = {}) {
	if (config.enabled === false) return;

	ctx.commands.register({
		definitionId: "agent-extensions.dsh-services",
		name: "dsh-services",
		description: "列出所有 dsh 服务进程（pid/端口/启动时间）",
		handler: () => {
			const rows = dshServers();
			const text = rows.length === 0
				? "没有发现 dsh 服务进程（连本进程都没匹配到——判据可能失效，检查 ss/proc）"
				: [`dsh 服务进程（${rows.length} 个）：`, ...rows.map(describe)].join("\n");
			return { kind: "success", text };
		},
	});

	ctx.commands.register({
		definitionId: "agent-extensions.dsh-kill-others",
		name: "dsh-kill-others",
		description: "SIGTERM 除本进程外的所有 dsh 服务进程（清理残留实例）",
		handler: () => {
			const others = dshServers().filter((row) => !row.self);
			if (others.length === 0) return { kind: "success", text: "没有其他 dsh 服务进程。" };
			const killed = [];
			for (const row of others) {
				try {
					process.kill(row.pid, "SIGTERM");
					killed.push(row);
				} catch (error) {
					ctx.logger.warn(`agent-extensions: kill ${row.pid} 失败: ${String(error)}`);
				}
			}
			return {
				kind: "success",
				text: [`已 SIGTERM ${killed.length} 个残留实例：`, ...killed.map(describe)].join("\n"),
			};
		},
	});

	ctx.commands.register({
		definitionId: "agent-extensions.dsh-restart",
		name: "dsh-restart",
		description: "重启当前 dsh web 服务（同 argv 重拉；浏览器 cookie 跨重启有效）",
		handler: () => {
			const unit = shepherdUnit();
			if (unit !== null) {
				// 托管模式：只发重启请求。延迟一拍让命令回执先送到客户端，
				// detached 让 herd 在本进程被停掉后仍能跑完这次请求。
				setTimeout(() => {
					spawn("herd", ["restart", unit], { detached: true, stdio: "ignore", env: process.env }).unref();
				}, 500);
				return { kind: "success", text: `正在通过 shepherd 重启 ${unit}（浏览器会自动重连）…` };
			}
			// 非托管模式：detached watcher 轮询本 PID，死后 exec 原 argv。
			// 轮询而非裸 sleep——SIGTERM 走优雅停机（dispose 最长 ~5s），端口释放时刻不定。
			const argv = [process.execPath, ...process.argv.slice(1)].map(shq).join(" ");
			const watcher = [
				`for i in $(seq 1 200); do kill -0 ${process.pid} 2>/dev/null || break; sleep 0.2; done`,
				"sleep 0.5",
				`exec ${argv}`,
			].join("; ");
			spawn("bash", ["-c", watcher], {
				detached: true,
				stdio: "ignore",
				env: process.env,
				cwd: process.cwd(),
			}).unref();
			// 让命令响应先回到客户端再停机
			setTimeout(() => process.kill(process.pid, "SIGTERM"), 300);
			return { kind: "success", text: "正在重启 dsh 服务（浏览器会自动重连）…" };
		},
	});
}
