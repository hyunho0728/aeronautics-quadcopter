-- sendAlt.lua
local MODEM_SIDE = "left"     -- vControll.lua와 동일한 모뎀 방향
local CHANNEL = 55           -- 무선 채널 번호

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then 
    error("Not found Modem on side: " .. MODEM_SIDE) 
end

-- vControll 모듈을 가져옵니다.
local vControll = require("vControll")

local function mainLoop()
    print("=== Altitude Telemetry Sender Started ===")
    while true do
        -- 기체의 실시간 현재 고도 측정
        local pose = sublevel.getLogicalPose()
        local currentAlt = pose.position.y
        
        -- 💡 [수정] 함수 호출을 통해 vControll 내부의 실시간 TARGET_ALT 값을 정확하게 가져옴
        local targetAlt = 0
        if vControll and type(vControll.getTargetAlt) == "function" then
            targetAlt = vControll.getTargetAlt()
        end
        
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