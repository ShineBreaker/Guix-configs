/**
 * Default Timeout Extension
 *
 * 为所有命令执行工具注入默认超时，防止命令无限挂起。
 * LLM 显式指定 timeout 时保留原值。
 *
 * 覆盖工具：
 *   bash              — timeout 单位：秒
 *   ctx_execute       — timeout 单位：毫秒
 *   ctx_execute_file  — timeout 单位：毫秒
 *   ctx_batch_execute — timeout 单位：毫秒
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";

const BASH_TIMEOUT_SECONDS = 120;
const CTX_TIMEOUT_MS = 120_000;

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event) => {
    if (isToolCallEventType("bash", event)) {
      if (event.input.timeout === undefined || event.input.timeout === null) {
        event.input.timeout = BASH_TIMEOUT_SECONDS;
      }
    }

    // context-mode MCP 工具（通过 tool_call hook 拦截，即使非内置工具也可修改 input）
    if (event.toolName === "ctx_execute" || event.toolName === "ctx_execute_file") {
      if (event.input.timeout === undefined || event.input.timeout === null) {
        event.input.timeout = CTX_TIMEOUT_MS;
      }
    }

    if (event.toolName === "ctx_batch_execute") {
      if (event.input.timeout === undefined || event.input.timeout === null) {
        event.input.timeout = CTX_TIMEOUT_MS;
      }
    }
  });
}
