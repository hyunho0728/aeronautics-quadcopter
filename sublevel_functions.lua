local helpers = require("helpers")
local monitor = peripheral.find("monitor")

monitor.clear()
monitor.setTextScale(0.5)

local pose = sublevel.getLogicalPose()
-- JSON 형태로 한 줄로 압축하여 출력
print(textutils.serializeJSON(pose))