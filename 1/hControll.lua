local helpers = require("helpers")

local TARGET_SPEED = 0 -- 조이스틱 중립에선 항상 속도가 0으로 가도록
local DEFRALT_SPEED = 1 -- 조이스틱 중립에서 모든 방향 프로펠러가 작동하는 속도

local MONITOR_SIDE = "right" -- 모니터가 연결된 방향 (기본값: 위쪽)

local MOTOR_MIN, MOTOR_MAX = -256, 256
local MOTER_B = peripheral.wrap("Create_RotationSpeedController_8")
local MOTER_R = peripheral.wrap("Create_RotationSpeedController_9")
local MOTER_F = peripheral.wrap("Create_RotationSpeedController_10")
local MOTER_L = peripheral.wrap("Create_RotationSpeedController_11")

local monitor = peripheral.wrap(MONITOR_SIDE) -- 모니터 연결

local RELAY = peripheral.wrap("redstone_relay_14")

if not MOTER_B then error("not found MOTER_B") end
if not MOTER_R then error("not found MOTER_R") end
if not MOTER_F then error("not found MOTER_F") end
if not MOTER_L then error("not found MOTER_L") end
if not RELAY then error("not found RELAY") end

local function ResetHMoters()
    MOTER_B.setTargetSpeed(1)
    MOTER_R.setTargetSpeed(1)
    MOTER_F.setTargetSpeed(1)
    MOTER_L.setTargetSpeed(1)
end

local function SetHMoterSpeeds(f, b, l, r)
    MOTER_F.setTargetSpeed(helpers.clamp(f, MOTOR_MIN, MOTOR_MAX)) -- 나중에 clamp 사용으로 변경
    MOTER_B.setTargetSpeed(helpers.clamp(b, MOTOR_MIN, MOTOR_MAX)) -- 나중에 clamp 사용으로 변경
    MOTER_L.setTargetSpeed(helpers.clamp(l, MOTOR_MIN, MOTOR_MAX)) -- 나중에 clamp 사용으로 변경
    MOTER_R.setTargetSpeed(helpers.clamp(r, MOTOR_MIN, MOTOR_MAX)) -- 나중에 clamp 사용으로 변경
end

local AnalogToSpeed = {1, 18, 35, 52, 69, 86, 103, 120, 137, 154, 171, 188, 205, 222, 239, 256}

ResetHMoters()

--메인 루프
local function mainLoop()
    ResetHMoters()
    
    while true do
        -- 1. 조이스틱 아날로그 입력값 수집 (0 ~ 15)
        local r_front = RELAY.getAnalogInput("front")
        local r_back  = RELAY.getAnalogInput("back")
        local r_left  = RELAY.getAnalogInput("left")
        local r_right = RELAY.getAnalogInput("right")

        -- 2. 기체의 실시간 이동 속도
        local velocity = sublevel.getLinearVelocity()
        local velX = velocity.x -- 💡 전후진 속도 (X축)
        local velZ = velocity.z -- 💡 좌우 이동 속도 (Z축)

        -- 3. 조이스틱 입력에 따른 기본 속도 매핑 (중립일 때는 0)
        local f_speed = (r_back == 0)  and 0 or AnalogToSpeed[r_back + 1]
        local b_speed = (r_front == 0) and 0 or AnalogToSpeed[r_front + 1]
        local l_speed = (r_right == 0) and 0 or AnalogToSpeed[r_right + 1]
        local r_speed = (r_left == 0)  and 0 or AnalogToSpeed[r_left + 1]

        -- 4. 브레이크 로직
        local BRAKE_GAIN = 60.0 -- 브레이크 감도

        -- 모든 조이스틱이 완전히 중립(0)일 때만 관성 제동 작동
        if r_front == 0 and r_back == 0 and r_left == 0 and r_right == 0 then
            
            -- [앞/뒤 제동 - X축 속도 제어]
            if math.abs(velX) > 0.1 then
                -- 속도의 크기(절대값)를 구해서 언제나 '양수'인 브레이크 속도를 계산합니다.
                local p_brake = math.min(math.abs(velX) * BRAKE_GAIN, MOTOR_MAX)
                
                if velX > 0.05 then
                    -- 앞으로 전진 중일 때 -> 앞쪽(F) 모터를 양수 속도로 가동
                    f_speed = p_brake
                else
                    -- 뒤로 후진 중일 때 -> 뒤쪽(B) 모터를 양수 속도로 가동
                    b_speed = p_brake
                end
            end

            -- [좌/우 제동 - Z축 속도 제어]
            if math.abs(velZ) > 0.1 then
                -- 언제나 '양수'인 브레이크 속도 계산
                local y_brake = math.min(math.abs(velZ) * BRAKE_GAIN, MOTOR_MAX)
                
                if velZ < -0.05 then
                    -- 왼쪽으로 이동 중일 때 -> 왼쪽(L) 모터를 양수 속도로 가동
                    l_speed = y_brake
                else
                    -- 오른쪽으로 이동 중일 때 -> 오른쪽(R) 모터를 양수 속도로 가동
                    r_speed = y_brake
                end
            end
        end

        -- 5. 조이스틱 중립 및 완전 정지 시 최소 대기 속도(DEFRALT_SPEED = 1) 부여
        if f_speed == 0 then f_speed = DEFRALT_SPEED end
        if b_speed == 0 then b_speed = DEFRALT_SPEED end
        if l_speed == 0 then l_speed = DEFRALT_SPEED end
        if r_speed == 0 then r_speed = DEFRALT_SPEED end

        -- 6. 최종 모터 출력 적용
        SetHMoterSpeeds(f_speed, b_speed, l_speed, r_speed)
        
        -- 디버깅 모니터 출력
        helpers.displayLine(monitor, 20, string.format("velx : %.3f", velX))
        helpers.displayLine(monitor, 21, string.format("vely : %.3f", velZ))
        
        sleep(0.05)
    end
end

return {
    start = mainLoop
}