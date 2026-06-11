-- hControll.lua
local helpers = require("helpers")
local pid     = require("pid") 
local vControll = require("vControll") -- 데이터 캡슐화 연동

--------------------------------------------------------------------------------
-- 1. 상수 및 기본 변수 설정
--------------------------------------------------------------------------------
local TARGET_SPEED = 0 
local DEFRALT_SPEED = 1 -- 조이스틱 중립 및 대기 시 기본 작동 속도

local MONITOR_SIDE = "right" 
local MOTOR_MIN, MOTOR_MAX = -256, 256

-- 기체를 기울이지 않고 수평 모터 직접 RPM 출력을 내기 위한 자율 주행용 PID 세팅
local POS_KP = 15.0      -- 오차에 기반한 목표 이동 가속도 계수
local POS_KI = 0.05      -- 누적 잔류 오차 상쇄용 계수
local POS_KD = 8.0       -- 관성을 효과적으로 억제하기 위한 제동 D 게인

local POS_CORR_MIN, POS_CORR_MAX = -256, 256
local POS_INTEG_MIN, POS_INTEG_MAX = -50, 50

local AnalogToSpeed = {1, 18, 35, 52, 69, 86, 103, 120, 137, 154, 171, 188, 205, 222, 239, 256}

--------------------------------------------------------------------------------
-- 2. 주변기기 연결 및 PID 초기화
--------------------------------------------------------------------------------
local MOTER_B = peripheral.wrap("Create_RotationSpeedController_16")
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

-- X축(전후)과 Z축(좌우) 자동 이동 제어용 PID 개별 인스턴스 초기화
local xPID = pid.new(0, POS_KP, POS_KI, POS_KD)
xPID:clampOutput(POS_CORR_MIN, POS_CORR_MAX)
xPID:limitIntegral(POS_INTEG_MIN, POS_INTEG_MAX)

local zPID = pid.new(0, POS_KP, POS_KI, POS_KD)
zPID:clampOutput(POS_CORR_MIN, POS_CORR_MAX)
zPID:limitIntegral(POS_INTEG_MIN, POS_INTEG_MAX)

--------------------------------------------------------------------------------
-- 3. 헬퍼 함수
--------------------------------------------------------------------------------
local function ResetHMoters()
    MOTER_B.setTargetSpeed(1)
    MOTER_R.setTargetSpeed(1)
    MOTER_F.setTargetSpeed(1)
    MOTER_L.setTargetSpeed(1)
end

local function SetHMoterSpeeds(f, b, l, r)
    MOTER_F.setTargetSpeed(helpers.clamp(f, MOTOR_MIN, MOTOR_MAX)) 
    MOTER_B.setTargetSpeed(helpers.clamp(b, MOTOR_MIN, MOTOR_MAX)) 
    MOTER_L.setTargetSpeed(helpers.clamp(l, MOTOR_MIN, MOTOR_MAX)) 
    MOTER_R.setTargetSpeed(helpers.clamp(r, MOTOR_MIN, MOTOR_MAX)) 
end

--------------------------------------------------------------------------------
-- 4. 특정 좌표 자동 이동 함수 (기체 비기울임 수평 프로펠러 직접 가동)
--------------------------------------------------------------------------------
local function moveToPosition(targetX, targetZ, dt)
    local pose = sublevel.getLogicalPose()
    local currentX = pose.position.x
    local currentZ = pose.position.z
    local velocity = sublevel.getLinearVelocity()
    
    xPID.sp = targetX
    zPID.sp = targetZ
    
    local xOutput = xPID:step(currentX, dt)
    local zOutput = zPID:step(currentZ, dt)
    
    local f_speed = 0
    local b_speed = 0
    local l_speed = 0
    local r_speed = 0
    
    -- 💡 [방향 제어 버그 수정] X축 월드 오차 값과 관성 브레이크 댐핑 부호를 뒤집었습니다.
    -- 기존: xOutput - (POS_KD * velocity.x) -> 반대로 가던 문제 해결을 위해 마이너스 변환 적용
    local xControl = -(xOutput - (POS_KD * velocity.x))
    
    if xControl > 0 then
        f_speed = math.min(xControl, MOTOR_MAX)  -- 정방향 전진 프로펠러 가동
    else
        b_speed = math.min(math.abs(xControl), MOTOR_MAX) -- 역방향 후진 프로펠러 가동
    end
    
    -- [Z축 좌우이동 프로펠러 출력 계산 및 관성 브레이크 댐핑 연산]
    local zControl = -(zOutput - (POS_KD * velocity.z))
    if zControl > 0 then
        r_speed = math.min(zControl, MOTOR_MAX)
    else
        l_speed = math.min(math.abs(zControl), MOTOR_MAX)
    end
    
    if f_speed == 0 then f_speed = DEFRALT_SPEED end
    if b_speed == 0 then b_speed = DEFRALT_SPEED end
    if l_speed == 0 then l_speed = DEFRALT_SPEED end
    if r_speed == 0 then r_speed = DEFRALT_SPEED end
    
    local errX = math.abs(targetX - currentX)
    local errZ = math.abs(targetZ - currentZ)
    local arrived = (errX < 0.3) and (errZ < 0.3) and (math.abs(velocity.x) < 0.05) and (math.abs(velocity.z) < 0.05)
    
    local velocity = sublevel.getLinearVelocity()
    helpers.displayLine(monitor, 20, string.format("velX : %.3f", velocity.x))
    helpers.displayLine(monitor, 21, string.format("velZ : %.3f", velocity.z))

    if arrived then
        ResetHMoters()
        return f_speed, b_speed, l_speed, r_speed, true
    end
    
    return f_speed, b_speed, l_speed, r_speed, false
end

--------------------------------------------------------------------------------
-- 5. 메인 제어 루프
--------------------------------------------------------------------------------
local function mainLoop()
    ResetHMoters()
    local lastTime = os.clock()
    
    while true do
        local now = os.clock()
        local dt  = math.max(now - lastTime, 0.001)
        lastTime  = now

        -- vControll의 함수 인터페이스를 호출해 안전하게 좌표 데이터 로드
        local nav = vControll.getNavState()

        if nav.autoFlight then
            -- 자동 좌표 이동 비행 상태 시 연산 모드 진입
            local f, b, l, r, arrived = moveToPosition(nav.targetX, nav.targetZ, dt)
            SetHMoterSpeeds(f, b, l, r)
            
            if arrived then
                vControll.setAutoFlight(false) -- 안전하게 플래그 상태 전환
                print("[NAV] Arrived target coordinates safely.")
            end
        else
            -- 수동 조이스틱 아날로그 제어 및 관성 브레이크 제동 로직 실행
            local r_front = RELAY.getAnalogInput("front")
            local r_back  = RELAY.getAnalogInput("back")
            local r_left  = RELAY.getAnalogInput("left")
            local r_right = RELAY.getAnalogInput("right")

            local velocity = sublevel.getLinearVelocity()
            local velX = velocity.x 
            local velZ = velocity.z 

            local f_speed = (r_back == 0)  and 0 or AnalogToSpeed[r_back + 1]
            local b_speed = (r_front == 0) and 0 or AnalogToSpeed[r_front + 1]
            local l_speed = (r_right == 0) and 0 or AnalogToSpeed[r_right + 1]
            local r_speed = (r_left == 0)  and 0 or AnalogToSpeed[r_left + 1]

            local BRAKE_GAIN = 60.0 

            if r_front == 0 and r_back == 0 and r_left == 0 and r_right == 0 then
                if math.abs(velX) > 0.1 then
                    local p_brake = math.min(math.abs(velX) * BRAKE_GAIN, MOTOR_MAX)
                    if velX > 0.05 then f_speed = p_brake else b_speed = p_brake end
                end

                if math.abs(velZ) > 0.1 then
                    local y_brake = math.min(math.abs(velZ) * BRAKE_GAIN, MOTOR_MAX)
                    if velZ < -0.05 then l_speed = y_brake else r_speed = y_brake end
                end
            end

            if f_speed == 0 then f_speed = DEFRALT_SPEED end
            if b_speed == 0 then b_speed = DEFRALT_SPEED end
            if l_speed == 0 then l_speed = DEFRALT_SPEED end
            if r_speed == 0 then r_speed = DEFRALT_SPEED end

            -- 최종 모터 출력 적용
            SetHMoterSpeeds(f_speed, b_speed, l_speed, r_speed)
            
            -- 디버깅 모니터 출력
            helpers.displayLine(monitor, 20, string.format("velX : %.3f", velX))
            helpers.displayLine(monitor, 21, string.format("velZ : %.3f", velZ))
        end
        
        sleep(0.05)
    end
end

--------------------------------------------------------------------------------
-- 6. 모듈 반환 정의
--------------------------------------------------------------------------------
return {
    start = mainLoop,
    moveToPosition = moveToPosition
}