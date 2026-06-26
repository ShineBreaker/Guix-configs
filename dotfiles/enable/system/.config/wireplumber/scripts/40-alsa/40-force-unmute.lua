-- WirePlumber — force-unmute ALSA output routes
--
-- SPDX-FileCopyrightText: 2026 BrokenShine <xchai404@gmail.com>
--
-- SPDX-License-Identifier: MIT
--
-- 背景：即便禁用了 device/automute-* setting，路由状态恢复、profile
-- 切换、蓝牙事件等其他场景仍可能让某个 ALSA 输出 route（特别是内置
-- Speaker）保持 muted。这个脚本是兜底：每当有 ALSA Sink 节点就绪时，
-- 强制把它对应的 route 取消静音。
--
-- 加载顺序：目录名 "40-alsa" 决定了它在同 prefix 下的相对优先级，
-- 这里比系统自带的 "50-alsa" 早一步注册 hook。

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
