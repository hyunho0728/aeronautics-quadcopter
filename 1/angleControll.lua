local helpers = require("helpers")

local DEFAULT_ANGLE = 90 -- 조립 후 동쪽을 바라봤을때 각도 (0 ~ 360 범위)

local MOTER_FL = peripheral.wrap("Create_RotationSpeedController_15") -- 전방 좌측 (북향)
local MOTER_FR = peripheral.wrap("Create_RotationSpeedController_14") -- 전방 우측 (남향)
local MOTER_BL = peripheral.wrap("Create_RotationSpeedController_17") -- 후방 좌측 (북향)
local MOTER_BR = peripheral.wrap("Create_RotationSpeedController_13") -- 후방 우측 (남향)

local monitor = peripheral.find("monitor")
local navigation_table = peripheral.find("navigation_table")

if not MOTER_FL then error("Not connect Moter: FL (Front Left)") end
if not MOTER_FR then error("Not connect Moter: FR (Front Right)") end
if not MOTER_BL then error("Not connect Moter: BL (Back Left)") end
if not MOTER_BR then error("Not connect Moter: BR (Back Right)") end
if not monitor then error("Not connect Monitor")   end
if not navigation_table then error("Not connect navigation_table") end

-- 튜닝 파라미터 (진동을 줄이기 위해 값을 낮췄습니다)
local Kp = 0.8            -- 비례 상수 (값이 클수록 격하게 반응하고, 작을수록 부드럽게 반응합니다)
local BASE_SPEED = 10     -- 기본 유지 속도 (1 ~ 256 사이, 모터가 부드럽게 출발하도록 조절)

-- 0~360도 시스템 전용 최단 경로 오차 계산 함수
local function getMinAngleError(target, current)
    local error = target - current
    
    if error > 180 then
        error = error - 360
    elseif error < -180 then
        error = error + 360
    end
    
    return error
end

-- 메인 제어 루프
local function mainLoop()
    while true do
        -- 1. 현재 각도 실시간 측정 (0 ~ 360 범위)
        local currentAngle = navigation_table.getRelativeAngle()
        
        -- 2. 0~360도 범위를 고려한 최단 오차 계산
        local angleError = getMinAngleError(DEFAULT_ANGLE, currentAngle)
        
        -- 3. 제어 입력값(보정 속도) 계산
        local controlValue = angleError * Kp
        
        -- 4. 대각선 모터 쌍으로 속도 배분 (부호 반전 적용)
        -- 기체가 반대로 돌던 문제를 해결하기 위해 오차 보정 방향을 뒤집었습니다.
        local speedGroupA = helpers.clamp(BASE_SPEED - controlValue, 1, 256)
        local speedGroupB = helpers.clamp(BASE_SPEED + controlValue, 1, 256)
        
        -- 5. 모터에 속도 명령 전달
        MOTER_FL.setTargetSpeed(speedGroupA)
        MOTER_BR.setTargetSpeed(speedGroupA)
        
        MOTER_FR.setTargetSpeed(speedGroupB)
        MOTER_BL.setTargetSpeed(speedGroupB)
        
        -- 6. 모니터 출력
        if monitor then
            helpers.displayLine(monitor, 22, "Target: " .. DEFAULT_ANGLE)
            helpers.displayLine(monitor, 23, "Current: " .. string.format("%.2f", currentAngle))
            helpers.displayLine(monitor, 24, "Error: " .. string.format("%.2f", angleError))
            helpers.displayLine(monitor, 25, "A_Grp(FL,BR): " .. math.floor(speedGroupA) .. " / B_Grp(FR,BL): " .. math.floor(speedGroupB))
        end
        
        os.sleep(0.1) -- 0.1초마다 반복 연산
    end
end

return {
    start = mainLoop
}