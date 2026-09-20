// SPDX-License-Identifier: MIT
//
// dsh-agent-extensions — bundle patch 挂载的 host 入口。
//
// 此入口必须由裸包名行挂载（见 cordis.patch.yml 文件头）：客户端半边只有在
// loader row 是精确包说明符时才被扫描到，子路径行会让 dsh.client 声明被静默
// 跳过。config 形如 { gate: {...}, globalContext: {...} }。

import * as gate from "./gate.js";
import * as globalContext from "./global-context.js";
import * as lifecycle from "./lifecycle.js";

export const name = "agent-extensions";
export const inject = [...new Set([...gate.inject, ...globalContext.inject, ...lifecycle.inject])];

export function apply(ctx, config = {}) {
	gate.apply(ctx, config.gate ?? {});
	globalContext.apply(ctx, config.globalContext ?? {});
	lifecycle.apply(ctx, config.lifecycle ?? {});
}
