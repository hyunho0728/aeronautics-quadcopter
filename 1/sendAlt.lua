-- sendAlt.lua
local MODEM_SIDE = "left"     -- vControll.lua와 동일한 모뎀 방향
local CHANNEL = 55           -- 무선 채널 번호

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then 
    error("Not found Modem on side: " .. MODEM_SIDE) 
end

-- vControll의 TARGET_ALT를 읽어오기 위해 모듈 참조
local vControll = require("vControll")

local function mainLoop()
    print("=== Altitude Telemetry Sender Started ===")
    while true do
        -- 기체의 실시간 현재 고도 측정
        local pose = sublevel.getLogicalPose()
        local currentAlt = pose.position.y
        
        -- vControll.lua 안에서 갱신되는 TARGET_ALT 값을 전역 변수 형태로 참조
        local targetAlt = _G.TARGET_ALT or 0 
        
        local packet = {
            type = "TELEMETRY",
            currentAlt = currentAlt,
            targetAlt = targetAlt
        }
        
        -- 무선으로 고도 패킷 송신
        modem.transmit(CHANNEL, CHANNEL, packet)
        
        sleep(0.1) -- 0.1초마다 반복 송신
    end
end

return {
    start = mainLoop
}