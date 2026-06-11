-- vControll.lua (최종 완벽본)

--------------------------------------------------------------------------------
-- 1. 설정 (CONFIG)
--------------------------------------------------------------------------------

local MODEM_SIDE = "left"     -- 💡 기체 컴퓨터에 무선/엔더 모뎀이 장착된 방향
local CHANNEL = 55           -- 💡 원격 조종기와 맞출 무선 채널 번호

local TARGET_ALT = sublevel.getLogicalPose().position.y -- 목표 고도 (미터 단위)

-- Create 모드의 회전 속도 컨트롤러(RPM 제어기) 주변기기 이름
local MOTOR_FL = "Create_RotationSpeedController_5" 
local MOTOR_FR = "Create_RotationSpeedController_4" 
local MOTOR_BL = "Create_RotationSpeedController_6" 
local MOTOR_BR = "Create_RotationSpeedController_7" 

local GIMBAL_NAME = "back" 
local MONITOR_SIDE = "right"

-- 릴레이 이름
REDSTONE_RELAY_NAME = "redstone_relay_14"

-- 고도 PID 게인
local ALT_KP = 3.0
local ALT_KI = 0.1
local ALT_KD = 2.0  

-- 고도 PID 출력 및 적분 제한값
local ALT_CORR_MIN, ALT_CORR_MAX = -100, 100
local ALT_INTEG_MIN, ALT_INTEG_MAX = -20, 60 

-- 자세 안정화 PID 게인
local STAB_KP = 0.3
local STAB_KI = 0.0001
local STAB_KD = 0.1

local STAB_CORR_MIN, STAB_CORR_MAX = -80, 80
local STAB_INTEG_MIN, STAB_INTEG_MAX = -20, 20

-- 모터 RPM 제어 범위
local MOTOR_MIN = -256
local MOTOR_MAX = 256

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

-- 릴레이 연결
local relay = peripheral.wrap(REDSTONE_RELAY_NAME)

-- 💡 [핵심 누락 수정] 순수 모뎀 연결 및 채널 오픈
local modem = peripheral.wrap(MODEM_SIDE)

-- 필수 장치 연결 확인
if not motorFL then error("Not found motor: FL") end
if not motorFR then error("Not found motor: FR") end
if not motorBL then error("Not found motor: BL") end
if not motorBR then error("Not found motor: BR") end
if not gimbal  then error("Not found Gimbal Sensor") end
if not monitor then error("Not found Monitor") end
if not modem   then error("Not found Modem on side: " .. MODEM_SIDE) end

-- 💡 해당 채널을 열어두어야 원격 신호를 수신할 수 있습니다.
modem.open(CHANNEL)

--------------------------------------------------------------------------------
-- 3. PID 제어기 인스턴스 초기화
--------------------------------------------------------------------------------

local altPID = pid.new(TARGET_ALT, ALT_KP, ALT_KI, ALT_KD) 
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

local FALLBACK_C = 61.81
local function getFeedforward(pressure, mass, gravity)
    if pressure == nil or pressure == 0 then return 0 end
    return FALLBACK_C / pressure
end

--------------------------------------------------------------------------------
-- 5. 메인 제어 루프 (MAIN CONTROL LOOP)
--------------------------------------------------------------------------------

local function controlLoop()
    local lastTime = os.clock()
    local prevVelY = 0

    -- 엔진 시작용 레드스톤 링크 조작
    relay.setAnalogueOutput("bottom", 0)

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

        local ff = getFeedforward(pressure, mass, gravity)
        
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
        helpers.displayLine(monitor, 1,  "Target: " .. TARGET_ALT .. " m")
        helpers.displayLine(monitor, 2,  string.format("Alt:   %6.2f m",    pos.y))
        helpers.displayLine(monitor, 3,  string.format("Err:   %+6.2f m",    TARGET_ALT - pos.y))
        helpers.displayLine(monitor, 4,  string.format("FF:   %+6.2f rpm",  ff))
        helpers.displayLine(monitor, 5,  string.format("Corr: %+6.2f rpm",  altCorr))
        helpers.displayLine(monitor, 6,  string.format("Base: %+6.2f rpm",  baseRPM))
        helpers.displayLine(monitor, 7,  string.format("Roll: %+6.2f deg / Out: %+5.1f", rollErr, rollOutput))
        helpers.displayLine(monitor, 8,  string.format("Ptch: %+6.2f deg / Out: %+5.1f", pitchErr, pitchOutput))
        helpers.displayLine(monitor, 9,  string.format("FL:%+5.0f FR:%+5.0f", fl, fr))
        helpers.displayLine(monitor, 10, string.format("BL:%+5.0f BR:%+5.0f", bl, br))
        helpers.displayLine(monitor, 11, string.format("Mass: %.2f kg", mass))
        helpers.displayLine(monitor, 12, string.format("Grav: %.2f m/s²", gravity))
        helpers.displayLine(monitor, 13, string.format("Pres: %.2f Pa", pressure))
        helpers.displayLine(monitor, 14, string.format("VelY: %.2f m/s", velY))
        helpers.displayLine(monitor, 15, string.format("Current KD: %.1f", altPID.kd))

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
        
        if type(packet) == "table" then
            -- 💡 고도 설정 명령 수신
            if packet.type == "SET_ALT" then
                local newAlt = tonumber(packet.value)

                if newAlt then
                    TARGET_ALT = newAlt
                    altPID.sp  = newAlt   
                    altPID.integral   = 0 
                    altPID.prev_error = 0 
                    print("Received -> Set Target Alt: " .. newAlt .. " m (Dist: " .. string.format("%.1f", distance or 0) .. "m)")
                else
                    print("Warning: Invalid height value received.")
                end
                
            -- 💡 원격 종료(EXIT) 명령 수신
            elseif packet.type == "EXIT" then
                print("\n[EXIT] Received exit command from remote.")
                print("Stopping all motors and shutting down main system...")
                
                -- 안전을 위해 모든 모터의 목표 속도를 대기 속도(1)로 변경하여 정지 유도
                setMotorSpeeds(1, 1, 1, 1)
                -- 종료전에 엔진 종료
                relay.setAnalogueOutput("bottom", 15)
                -- 함수를 종료(return)하여 parallel.waitForAny가 main 전체를 종료시키도록 함
                return 
            end
        end
    end
end

return {
    controlLoop = controlLoop,
    inputLoop = inputLoop
}