-- WirePlumber — ALSA Sink 就绪时强制取消输出 route 静音（兜底）
-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
-- SPDX-License-Identifier: MIT
--
-- 不变量：save=false —— 只改运行时状态，不写回路由持久化；
-- 目录名 "40-alsa" 保证先于系统 "50-alsa" 注册 hook。
-- 背景与排障见 docs/scripts/misc-scripts.md §40-force-unmute

cutils = require ("common-utils")
log = Log.open_topic ("s-force-unmute")

function unmuteRoute (device, route)
  local param = Pod.Object {
    "Spa:Pod:Object:Param:Route", "Route",
    index = route.index,
    device = route.device,
    props = Pod.Object {
      "Spa:Pod:Object:Param:Props", "Route",
      mute = false
    },
    save = false,
  }
  log:info (device, "Force-unmuting route " .. route.name)
  device:set_param ("Route", param)
end

unmute_hook = SimpleEventHook {
  name = "force-unmute/alsa-sink-ready",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-state-changed" },
      Constraint { "media.class", "matches", "Audio/Sink" },
      Constraint { "device.api", "=", "alsa" },
    },
  },
  execute = function (event)
    local source = event:get_source ()
    local node = event:get_subject ()
    local new_state = event:get_properties ()["event.subject.new-state"]
    if new_state ~= "running" then
      return
    end

    local device_id = node.properties ["device.id"]
    local cpd = node.properties ["card.profile.device"]
    local device_om = source:call ("get-object-manager", "device")
    for device in device_om:iterate {
        Constraint { "device.id", "=", device_id, type = "pw-global" },
      } do
      for p in device:iterate_params ("Route") do
        local route = cutils.parseParam (p, "Route")
        if route and route.direction == "Output"
            and route.device == cpd then
          unmuteRoute (device, route)
        end
      end
    end
  end
}

unmute_hook:register ()
