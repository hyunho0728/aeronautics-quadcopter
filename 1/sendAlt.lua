-- sendAlt.lua
local MODEM_SIDE = "left"     -- vControll.lua와 동일하게 설정
local CHANNEL = 55           -- 무선 채널 번호

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then 
    error("Not found Modem on side: " .. MODEM_SIDE) 
end

-- vControll의 실시간 변수를 참조하기 위해 모듈 로드
local vControll = require("vControll")

print("=== Altitude Telemetry Sender Started ===")

while true do
    -- 기체의 현재 위치 및 고도 측정
    local pose = sublevel.getLogicalPose()
    local currentAlt = pose.position.y
    
    -- vControll 모듈 환경 내에 선언된 실시간 TARGET_ALT 가져오기
    -- (주의: vControll.lua에서 TARGET_ALT가 local로 선언되어 있다면 아래 가이드를 확인해 주세요)
    local targetAlt = _G.TARGET_ALT or 0 
    
    local packet = {
        type = "TELEMETRY",
        currentAlt = currentAlt,
        targetAlt = targetAlt
    }
    
    -- 채널을 통해 고도 데이터 방송
    modem.transmit(CHANNEL, CHANNEL, packet)
    
    sleep(0.1) -- 0.1초마다 주기적으로 송신
end