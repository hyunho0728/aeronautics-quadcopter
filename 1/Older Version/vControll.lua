-- vControll.lua (안정성 및 급강하 충돌 방지 수정본)

--------------------------------------------------------------------------------
-- 1. 설정 (CONFIG)
--------------------------------------------------------------------------------

local MODEM_SIDE = "left"     -- 💡 기체 컴퓨터에 무선/엔더 모뎀이 장착된 방향
local CHANNEL = 55           -- 💡 원격 조종기와 맞출 무선 채널 번호

local TARGET_ALT = sublevel.getLogicalPose().position.y -- 최종 목표 고도 (미터 단위)
local RAMP_ALT = TARGET_ALT                             -- PID가 실제로 추적할 가상 목표 고도 (램프 적용)

-- Create 모드의 회전 속도 컨트롤러(RPM 제어기) 주변기기 이름
local MOTOR_FL = "Create_RotationSpeedController_5" 
local MOTOR_FR = "Create_RotationSpeedController_4" 
local MOTOR_BL = "Create_RotationSpeedController_6" 
local MOTOR_BR = "Create_RotationSpeedController_7" 

local GIMBAL_NAME = "back" 
local MONITOR_SIDE = "right" 

-- 고도 PID 게인
local ALT_KP = 3.0
local ALT_KI = 0.15 -- 💡 잔류 오차를 더 빠르게 없애기 위해 Ki 약간 상향
local ALT_KD = 2.0  

-- 고도 PID 출력 및 적분 제한값
local ALT_CORR_MIN, ALT_CORR_MAX = -100, 100
local ALT_INTEG_MIN, ALT_INTEG_MAX = -60, 60 -- 💡 고도가 높을 때 RPM을 충분히 깎을 수 있도록 하한선 완화 (-20 -> -60)

-- 자세 안정화 PID 게인
local STAB_KP = 0.3
local STAB_KI = 0.0001
local STAB_KD = 0.1

local STAB_CORR_MIN, STAB_CORR_MAX = -80, 80
local STAB_INTEG_MIN, STAB_INTEG_MAX = -20, 20

-- 모터 RPM 제어 범위
local MOTOR_MIN = -256
local MOTOR_MAX = 256

-- 하강 프로파일 설정 (추락 방지)
local MAX_DESCENT_SPEED = 8.0 -- 💡 초당 최대 하강 속도 제한 (8m/s). 이 속도로 부드럽게 내려갑니다.

--------------------------------------------------------------------------------
-- 2. 라이브러리 로드 및 주변기기 연결
--------------------------------------------------------------------------------

local helpers = require("helpers")
local pid     = require("pid")

-- 모터 주변기기 래핑
local motorFL = peripheral.wrap(MOTOR_FL)
local motorFR = peripheral.wrap(MOTOR_FR)
local motorBL = peripheral.wrap(MOTOR_BL)
local motorBR = peripheral.wrap(MOTOR_BR)

-- 짐벌 센서 및 모니터 래핑
local gimbal  = peripheral.wrap(GIMBAL_NAME)
local monitor = peripheral.wrap(MONITOR_SIDE)

-- 순수 모뎀 연결 및 채널 오픈
local modem = peripheral.wrap(MODEM_SIDE)

-- 필수 장치 연결 확인
if not motorFL then error("Not found motor: FL") end
if not motorFR then error("Not found motor: FR") end
if not motorBL then error("Not found motor: BL") end
if not motorBR then error("Not found motor: BR") end
if not gimbal  then error("Not found Gimbal Sensor") end
if not monitor then error("Not found Monitor") end
if not modem   then error("Not found Modem on side: " .. MODEM_SIDE) end

-- 해당 채널을 열어두어야 원격 신호를 수신할 수 있습니다.
modem.open(CHANNEL)

--------------------------------------------------------------------------------
-- 3. PID 제어기 인스턴스 초기화
--------------------------------------------------------------------------------

-- 초기 생성 시 RAMP_ALT를 기준으로 타겟을 설정합니다.
local altPID = pid.new(RAMP_ALT, ALT_KP, ALT_KI, ALT_KD) 
altPID:clampOutput(ALT_CORR_MIN, ALT_CORR_MAX)
altPID:limitIntegral(ALT_INTEG_MIN, ALT_INTEG_MAX)

local pitchPID = pid.new(0, STAB_KP, STAB_KI, STAB_KD)
pitchPID:limitIntegral(STAB_INTEG_MIN, STAB_INTEG_MAX)
pitchPID:clampOutput(STAB_CORR_MIN, STAB_CORR_MAX)

local rollPID = pid.new(0, STAB_KP, STAB_KI, STAB_KD)
rollPID:limitIntegral(STAB_INTEG_MIN, STAB_INTEG_MAX)
rollPID:clampOutput(STAB_CORR_MIN, STAB_CORR_MAX)

--------------------------------------------------------------------------------
-- 4. 헬퍼 함수
--------------------------------------------------------------------------------

local function setMotorSpeeds(fl, fr, bl, br)
    motorFL.setTargetSpeed(helpers.clamp(fl, MOTOR_MIN, MOTOR_MAX))
    motorFR.setTargetSpeed(helpers.clamp(fr, MOTOR_MIN, MOTOR_MAX))
    motorBL.setTargetSpeed(helpers.clamp(bl, MOTOR_MIN, MOTOR_MAX))
    motorBR.setTargetSpeed(helpers.clamp(br, MOTOR_MIN, MOTOR_MAX))
end

-- 💡 [수정] 질량, 중력, 기압을 모두 고려한 물리 기반 피드포워드 계산 함수
local FALLBACK_C = 61.81
local function getFeedforward(pressure, mass, gravity)
    if pressure == nil or pressure == 0 then return 0 end
    -- 기체의 무게(mass * gravity)에 비례하고 기압(pressure)에 반비례하도록 중력 스케일링 적용
    -- 기본 설계값(예: mass=1000kg, gravity=9.81m/s²) 대비 변동 수치를 반영합니다.
    local baseWeight = 10000 -- 기준 무게 스케일 (테스트 환경에 맞게 자동 보정)
    local weightFactor = (mass * gravity) / baseWeight
    if weightFactor <= 0 then weightFactor = 1 end

    return (FALLBACK_C * weightFactor) / pressure
end

--------------------------------------------------------------------------------
-- 5. 메인 제어 루프 (MAIN CONTROL LOOP)
--------------------------------------------------------------------------------

local function controlLoop()
    local lastTime = os.clock()
    local prevVelY = 0

    while true do
        local now = os.clock()
        local dt  = math.max(now - lastTime, 0.001)
        lastTime  = now

        local pose       = sublevel.getLogicalPose()
        local pos        = pose.position
        local angVel     = sublevel.getAngularVelocity()
        local pressure   = aero.getAirPressure(pos)
        local mass       = sublevel.getMass()
        local gravityVec = aero.getGravity()
        local gravity    = math.abs(gravityVec.y)
        local velocity   = sublevel.getLinearVelocity()
        local velY       = velocity.y

        local vertAccel = (velY - prevVelY) / dt
        prevVelY = velY

        ------------------------------------------------------------------------
        -- 💡 [핵심 추가] 하강 속도 제한을 위한 타겟 램프(Ramp) 로직
        ------------------------------------------------------------------------
        if RAMP_ALT > TARGET_ALT then
            -- 최종 목표가 현재 추적 목표보다 낮으면(하강 필요), 초당 MAX_DESCENT_SPEED 만큼만 깎음
            RAMP_ALT = math.max(RAMP_ALT - (MAX_DESCENT_SPEED * dt), TARGET_ALT)
        elseif RAMP_ALT < TARGET_ALT then
            -- 상승 시에는 램프 없이 즉시 타겟 반영 (혹은 원할 시 상승 제한도 가능)
            RAMP_ALT = TARGET_ALT
        end
        altPID.sp = RAMP_ALT -- PID 제어기의 목표치를 점진적으로 변하는 RAMP_ALT로 갱신
        ------------------------------------------------------------------------

        local ff = getFeedforward(pressure, mass, gravity)
        
        -- 하강 중 브레이크(D항 변조) 로직 유지하되 낙하 상태 분석에 도움을 줌
        if velY < -0.1 then
            altPID.kd = ALT_KD * 2.5
        else
            altPID.kd = ALT_KD
        end

        local altCorr = altPID:step(pos.y, dt)
        local baseRPM = ff + altCorr

        local tiltErr = gimbal.getAngles()
        local rollErr = tiltErr[1]
        local pitchErr = tiltErr[2]

        local rollOutput  = rollPID:step(rollErr, dt)  - STAB_KD * angVel.z
        local pitchOutput = pitchPID:step(pitchErr, dt) - STAB_KD * angVel.x

        rollOutput  = helpers.clamp(rollOutput,  STAB_CORR_MIN, STAB_CORR_MAX)
        pitchOutput = helpers.clamp(pitchOutput, STAB_CORR_MIN, STAB_CORR_MAX)

        local fl = (baseRPM + pitchOutput) - rollOutput
        local fr = (baseRPM + pitchOutput) + rollOutput
        local bl = (baseRPM - pitchOutput) - rollOutput
        local br = (baseRPM - pitchOutput) + rollOutput

        setMotorSpeeds(fl, fr, bl, br)

        monitor.setTextScale(0.5)
        helpers.displayLine(monitor, 1,  string.format("Final TG: %.1f m", TARGET_ALT))
        helpers.displayLine(monitor, 2,  string.format("Ramp TG:  %.1f m", RAMP_ALT)) -- 현재 깎여 내려가는 중인 가상 타겟
        helpers.displayLine(monitor, 3,  string.format("Alt:      %6.2f m", pos.y))
        helpers.displayLine(monitor, 4,  string.format("Err(Rmp): %+6.2f m", RAMP_ALT - pos.y))
        helpers.displayLine(monitor, 5,  string.format("FF:       %+6.2f rpm", ff))
        helpers.displayLine(monitor, 6,  string.format("Corr:     %+6.2f rpm", altCorr))
        helpers.displayLine(monitor, 7,  string.format("Base:     %+6.2f rpm", baseRPM))
        helpers.displayLine(monitor, 8,  string.format("Roll: %+6.2f deg / Out: %+5.1f", rollErr, rollOutput))
        helpers.displayLine(monitor, 9,  string.format("Ptch: %+6.2f deg / Out: %+5.1f", pitchErr, pitchOutput))
        helpers.displayLine(monitor, 10, string.format("FL:%+5.0f FR:%+5.0f", fl, fr))
        helpers.displayLine(monitor, 11, string.format("BL:%+5.0f BR:%+5.0f", bl, br))
        helpers.displayLine(monitor, 12, string.format("Mass: %.2f kg", mass))
        helpers.displayLine(monitor, 13, string.format("Grav: %.2f m/s²", gravity))
        helpers.displayLine(monitor, 14, string.format("Pres: %.2f Pa", pressure))
        helpers.displayLine(monitor, 15, string.format("VelY: %.2f m/s", velY))

        sleep(0.05)
    end
end

--------------------------------------------------------------------------------
-- 6. 무선 수신 입력 루프 (WIRELESS RECEIVE LOOP)
--------------------------------------------------------------------------------
local function inputLoop()
    print("Waiting for remote altitude command... (CH: " .. CHANNEL .. ")")
    while true do
        local event, side, channel, replyChannel, packet, distance = os.pullEvent("modem_message")
        
        if type(packet) == "table" and packet.type == "SET_ALT" then
            local newAlt = tonumber(packet.value)

            if newAlt then
                TARGET_ALT = newAlt
                -- 💡 [중요 수정] 무선 신호를 받았을 때 즉시 sp와 램프를 0으로 밀어버리면 
                -- 순간적인 제어 불능(낙하)이 오므로, 오차 기록만 리셋하고 램프는 현재 고도에서부터 시작하게 유도합니다.
                RAMP_ALT = sublevel.getLogicalPose().position.y
                altPID.sp  = RAMP_ALT   
                altPID.integral   = 0 
                altPID.prev_error = 0 
                print("Received -> Set Target Alt: " .. newAlt .. " m (Dist: " .. string.format("%.1f", distance or 0) .. "m)")
            else
                print("Warning: Invalid height value received.")
            end
        end
    end
end

return {
    controlLoop = controlLoop,
    inputLoop = inputLoop
}