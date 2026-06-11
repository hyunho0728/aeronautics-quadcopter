-- 컴퓨터 위에 모니터를 배치하거나 MONITOR_SIDE 변수를 수정하세요.
-- 또한 본인의 쿼드콥터 구조에 맞게 MOTOR_ 변수 이름을 변경해야 합니다.
-- alt_kp, ki, kd 값은 튜닝이 필요합니다.
-- stab_kp, ki, kd 값도 튜닝이 필요합니다.
-- 처음에는 튜닝 없이 그냥 시도해 보세요. 어쩌면 한 번에 작동할지도 모릅니다!

--------------------------------------------------------------------------------
-- 1. 설정 (CONFIG)
--------------------------------------------------------------------------------

local TARGET_ALT = sublevel.getLogicalPose().position.y -- 목표 고도 (미터 단위)

-- Create 모드의 회전 속도 컨트롤러(RPM 제어기) 주변기기 이름
local MOTOR_FL = "Create_RotationSpeedController_5" -- 전방 왼쪽(Front Left) 모터
local MOTOR_FR = "Create_RotationSpeedController_4" -- 전방 오른쪽(Front Right) 모터
local MOTOR_BL = "Create_RotationSpeedController_6" -- 후방 왼쪽(Back Left) 모터
local MOTOR_BR = "Create_RotationSpeedController_7" -- 후방 오른쪽(Back Right) 모터

local GIMBAL_NAME = "back" -- 쿼드콥터의 기울기(각도)를 측정할 짐벌 센서 이름

local MONITOR_SIDE = "right" -- 모니터가 연결된 방향 (기본값: 위쪽)

-- 고도 제어용 PID 계수 (Altitude PID)
local ALT_KP = 3.0    -- 비례 항 (목표 고도와 멀수록 강하게 반응)
local ALT_KI = 0.1    -- 적분 항 (오차가 지속되면 서서히 보정치를 누적)
local ALT_KD = 2.0    -- 미분 항 (고도 변화 속도를 억제하여 오버슈트 방지)

-- 자세 안정화용 PID 계수 (Stabilization PID)
local STAB_KP = 0.3      -- 비례 항 (기울어질수록 반대 방향으로 강하게 반응)
local STAB_KI = 0.0001   -- 적분 항 (미세한 기울어짐 누적치 보정)
local STAB_KD = 0.1     -- 미분 항 (기울어지는 속도를 감쇄하여 흔들림 방지)

-- 자세 제어 보정치 및 적분 누적값 제한 (안정성 확보용)
local STAB_CORR_MIN, STAB_CORR_MAX = -80, 80     -- 안정화 모터 출력 보정 범위 한계치
local STAB_INTEG_MIN, STAB_INTEG_MAX = -20, 20   -- 안정화 적분 누적값 한계치

-- 외부 충격(Disturbance) 감지: 비행기가 이착륙할 때처럼 갑작스러운 큰 기울기가 발생할 때의 기준치
local DISTURBANCE_THRESHOLD = 3.0 -- 이 각도(도)를 넘으면 급격한 외부 충격으로 판정
local INTEGRAL_BLEED        = 0.3 -- 충격 감지 시 적분 누적값을 이 비율만큼 감소시켜 과보정 방지

-- 모터 RPM 제한치 (Create 모드 속도 제어기의 최소/최대 속도)
local MOTOR_MIN, MOTOR_MAX = -256, 256

-- 고도 제어 보정치 및 적분 누적값 제한
local ALT_CORR_MIN, ALT_CORR_MAX = -100, 100    -- 고도 PID 모터 출력 보정 범위 한계치
local ALT_INTEG_MIN, ALT_INTEG_MAX = -60, 60    -- 고도 PID 적분 누적값 한계치

-- 모터 RPM과 공기압을 실제 양력(Thrust)으로 변환하는 양력 계수 (k)
-- 공식: 양력(Lift) = k * RPM * 공기압(Pressure)
local k         = nil   -- 실시간 데이터 측정을 통해 동적으로 추정 및 갱신됨
local K_MIN_RPM = 20    -- k 계수 계산을 시작할 최소 RPM 기준선
local K_ALPHA   = 0.05  -- 새로운 k 값을 반영할 때의 가중치 (지수 이동 평균 필터 필터링용)

--------------------------------------------------------------------------------
-- 2. 초기화 및 주변기기 연결 (SETUP)
--------------------------------------------------------------------------------

local pid     = require("pid") -- 외부 PID 라이브러리 로드
local monitor = peripheral.wrap(MONITOR_SIDE) -- 모니터 연결
local helpers = require("helpers") -- 공용 함수 로드

-- 각 위치별 모터 연결
local motorFL = peripheral.wrap(MOTOR_FL)
local motorFR = peripheral.wrap(MOTOR_FR)
local motorBL = peripheral.wrap(MOTOR_BL)
local motorBR = peripheral.wrap(MOTOR_BR)

-- 짐벌 센서 연결
-- .getAngles() 호출 시 반환값 양식:
-- a[1] --> 요(Yaw): 좌우 회전각 (+ 왼쪽, - 오른쪽)
-- a[2] --> 피치(Pitch) / 롤(Roll): 전후좌우 기울기 (+ 위/앞, - 아래/뒤)
local gimbal = peripheral.wrap(GIMBAL_NAME)

-- 주변기기가 하나라도 없으면 에러를 발생시키고 프로그램 종료
if not motorFL then error("Not connect Moter: FL (Front Left)") end
if not motorFR then error("Not connect Moter: FR (Front Right)") end
if not motorBL then error("Not connect Moter: BL (Back Left)") end
if not motorBR then error("Not connect Moter: BR (Back Right)") end
if not monitor then error("Not connect Monitor")   end
if not gimbal  then error("Not connect Gimbal")     end

-- 모니터 초기 설정
monitor.setTextScale(0.5) -- 글자 크기를 작게 조절하여 많은 정보가 보이도록 설정
monitor.clear()           -- 모니터 화면 초기화

-- 고도 제어 PID 객체 생성 및 제한값 설정
local altPID = pid.new(TARGET_ALT, ALT_KP, ALT_KI, ALT_KD)
altPID:clampOutput(ALT_CORR_MIN, ALT_CORR_MAX)
altPID:limitIntegral(ALT_INTEG_MIN, ALT_INTEG_MAX)

-- 롤(Roll, 좌우) 및 피치(Pitch, 전후) 자세 제어용 PID 객체 생성 및 제한값 설정
local rollPID  = pid.new(0, STAB_KP, STAB_KI, STAB_KD)
local pitchPID = pid.new(0, STAB_KP, STAB_KI, STAB_KD)
rollPID:limitIntegral(STAB_INTEG_MIN, STAB_INTEG_MAX)
pitchPID:limitIntegral(STAB_INTEG_MIN, STAB_INTEG_MAX)
rollPID:clampOutput(STAB_CORR_MIN, STAB_CORR_MAX)
pitchPID:clampOutput(STAB_CORR_MIN, STAB_CORR_MAX)

--------------------------------------------------------------------------------
-- 3. 보조 함수 (HELPERS)
--------------------------------------------------------------------------------

-- 4개의 모터에 계산된 최종 RPM 속도를 안전하게 제한하여 적용하는 함수
local function setMotorSpeeds(fl, fr, bl, br)
    motorFL.setTargetSpeed(helpers.clamp(fl, MOTOR_MIN, MOTOR_MAX))
    motorFR.setTargetSpeed(helpers.clamp(fr, MOTOR_MIN, MOTOR_MAX))
    motorBL.setTargetSpeed(helpers.clamp(bl, MOTOR_MIN, MOTOR_MAX))
    motorBR.setTargetSpeed(helpers.clamp(br, MOTOR_MIN, MOTOR_MAX))
end

-- 피드포워드(Feedforward) 계산 함수
-- PID 제어 이전에 기체가 공중에 뜨기 위해 기본적으로 필요한 베이스 RPM을 물리 법칙에 따라 선제 계산함
local FALLBACK_C = 61.81 -- k 계수가 할당되지 않았을 때 사용하는 기본 백업 상수
local function getFeedforward(pressure, mass, gravity)
    if pressure == nil or pressure == 0 then return 0 end
    local C
    if k ~= nil then
        C = (mass * gravity) / k -- 중력 대비 필요한 이상적인 RPM 상수 계산
    else
        C = FALLBACK_C
    end
    return C / pressure -- 공기압이 낮을수록 더 높은 RPM이 필요하므로 압력으로 나누어 반환
end

-- 실시간 데이터 기반 양력 계수(k) 추정 및 업데이트 함수
-- 기체의 무게, 중력, 가속도, 모터 속도, 공기압을 분석하여 실제 환경의 공기역학 상수를 학습함
local function updateK(mass, gravity, vertAccel, currentRPM, pressure)
    if currentRPM < K_MIN_RPM or pressure == nil or pressure == 0 then return end
    
    local lift = mass * (gravity + vertAccel) -- 현재 기체가 받고 있는 총 양력 계산 (F = m * a)
    if lift <= 0 then return end
    
    local kNew = lift / (currentRPM * pressure) -- 물리 공식을 역산하여 새로운 k값 도출
    
    if k == nil then
        k = kNew -- 최초 계산 시 값을 그대로 등록
    else
        -- 급격한 값 변화 방지를 위해 부드럽게 필터링하여 기존 k값에 점진적 반영 (지수 이동 평균)
        k = k * ( 1 - K_ALPHA ) + kNew * K_ALPHA
    end
end

--------------------------------------------------------------------------------
-- 4. 메인 제어 루프 (CONTROL LOOP)
--------------------------------------------------------------------------------

-- 기체의 실시간 물리 데이터를 수집하고 PID 연산을 통해 모터를 제어하는 메인 스레드
local function controlLoop()
    local lastTime = os.clock() -- 주기(dt) 계산을 위한 이전 시간 기록
    local prevVelY = 0          -- 수직 가속도 계산을 위한 이전 수직 속도 기록

    while true do
        local now = os.clock()
        local dt  = math.max(now - lastTime, 0.001) -- 시간 간격 계산 (최소 0.001초 보장)
        lastTime  = now

        -- 기체의 각종 물리 정보 및 공기역학 데이터 가져오기
        local pose       = sublevel.getLogicalPose()     -- 기체의 위치/자세 데이터
        local pos        = pose.position                 -- 월드 좌표상 현재 위치
        local angVel     = sublevel.getAngularVelocity() -- 기체의 각속도 (회전 속도)
        local pressure   = aero.getAirPressure(pos)      -- 현재 고도의 공기 가압량
        local mass       = sublevel.getMass()            -- 기체의 총 질량 (무게)
        local gravityVec = aero.getGravity()             -- 현재 세계의 중력 벡터
        local gravity    = math.abs(gravityVec.y)        -- Y축 중력 크기
        local velocity   = sublevel.getLinearVelocity()  -- 기체의 이동 속도 벡터
        local velY       = velocity.y                    -- 현재 수직 속도 (올라가는 중인지 내려가는 중인지)
        local com        = sublevel.getCenterOfMass()    -- 기체의 무게 중심 위치

        -- k 계수 학습 및 피드포워드에 필요한 수직 가속도 계산 (속도의 변화량 / 시간)
        local vertAccel = (velY - prevVelY) / dt
        prevVelY = velY

        -- 현재 네 모터의 평균 타겟 RPM 계산
        local currentRPM = (motorFL.getTargetSpeed() + motorFR.getTargetSpeed()
                          + motorBL.getTargetSpeed() + motorBR.getTargetSpeed()) / 4
        updateK(mass, gravity, vertAccel, currentRPM, pressure) -- 양력 계수 갱신

        -- [고도 제어 연산]
        local ff      = getFeedforward(pressure, mass, gravity) -- 붕 뜨기 위한 기본 RPM 계산
        local altCorr = altPID:step(pos.y, dt) - ALT_KD * velY   -- PID 연산 결과에 수직 속도 감쇄 적용
        local baseRPM = ff + altCorr                            -- 최종 베이스 RPM 확정

        -- [자세 안정화 제어 연산]
        local tiltErr = gimbal.getAngles() -- 짐벌 센서로부터 오차 각도 수집
        local rollErr = tiltErr[1]        -- 좌우 기울어짐 오차
        local pitchErr = tiltErr[2]       -- 전후 기울어짐 오차

        -- 만약 기체가 갑자기 심하게 흔들리면(기준치 초과) 적분 에러 누적치를 깎아서(Bleed) 튕겨 나가는 현상 방지
        if math.abs(rollErr) > DISTURBANCE_THRESHOLD then
            rollPID.integral = rollPID.integral * INTEGRAL_BLEED
        end
        if math.abs(pitchErr) > DISTURBANCE_THRESHOLD then
            pitchPID.integral = pitchPID.integral * INTEGRAL_BLEED
        end

        -- 각속도(Damping) 성분을 추가 차감하여 오버슈트(Over-correcting)와 진동을 억제하는 PID 제어값 계산
        local rollOutput  = rollPID:step(rollErr, dt)  - STAB_KD * angVel.z
        local pitchOutput = pitchPID:step(pitchErr, dt) - STAB_KD * angVel.x

        -- 제어 출력값이 범위를 벗어나지 않도록 한계 고정
        rollOutput  = helpers.clamp(rollOutput,  STAB_CORR_MIN, STAB_CORR_MAX)
        pitchOutput = helpers.clamp(pitchOutput, STAB_CORR_MIN, STAB_CORR_MAX)

        -- [모터 믹싱(Motor Mixing)] -------------------------------------------
        -- 주의: 기체의 전후좌우 모터 배치 방향이나 모드 조립 상태에 따라 부호(+, -)를 수정해야 할 수 있습니다.
        -- '렌치(Wand)' 형태의 도구 등을 보면서 Roll/Pitch 출력이 올바른 방향으로 복원력을 주는지 확인 후 커스텀하세요.
        ------------------------------------------------------------------------
        local fl = (baseRPM + pitchOutput) - rollOutput -- 전방 왼쪽 모터
        local fr = (baseRPM + pitchOutput) + rollOutput -- 전방 오른쪽 모터
        local bl = (baseRPM - pitchOutput) - rollOutput -- 후방 왼쪽 모터
        local br = (baseRPM - pitchOutput) + rollOutput -- 후방 오른쪽 모터

        setMotorSpeeds(fl, fr, bl, br) -- 각 모터에 최종 연산된 RPM 적용

        -- [모니터 디스플레이 출력 정보 업데이트]
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
        helpers.displayLine(monitor, 11, k and string.format("K:  %.6f", k) or "K:  (warmup)")
        helpers.displayLine(monitor, 13, string.format("CoM: %.2f %.2f %.2f", com.x, com.y, com.z))
        helpers.displayLine(monitor, 14, string.format("Mass: %.2f kg", mass))
        helpers.displayLine(monitor, 15, string.format("Grav: %.2f m/s²", gravity))
        helpers.displayLine(monitor, 16, string.format("Weight: %.2f N", mass * gravity))
        helpers.displayLine(monitor, 17, string.format("Pres: %.2f Pa", pressure))
        helpers.displayLine(monitor, 18, string.format("VelY: %.2f m/s", velY))
        helpers.displayLine(monitor, 19, string.format("VertAccel: %.2f m/s²", vertAccel))

        sleep(0.05) -- 컴퓨터 연산 과부하 방지 및 제어 주기 확보 (0.05초 대기)
    end
end

--------------------------------------------------------------------------------
-- 5. 사용자 입력 루프 (USER INPUT LOOP)
--------------------------------------------------------------------------------

-- 터미널을 통해 실시간으로 새로운 목표 고도를 입력받는 스레드
local function inputLoop()
    while true do
        io.write("New altitude: ")

        local input = read()
        local newAlt = tonumber(input)

        if newAlt then
            TARGET_ALT = newAlt
            altPID.sp  = newAlt   -- PID 인스턴스의 목표치(SetPoint) 변경
            altPID.integral   = 0 -- 고도가 바뀌었으므로 과거의 오차 누적값 리셋
            altPID.prev_error = 0 -- 과거 오차 데이터 리셋 (급발진 방지)
            print("Target set to " .. newAlt .. " m")
        else
            -- 숫자가 아닌 다른 문자가 입력되면 안전을 위해 모든 모터를 끄고 스크립트 강제 종료
            --setMotorSpeeds(1, 1, 1, 1)
            error("not number. exit")
        end
    end
end

--------------------------------------------------------------------------------
-- 6. 두 루프를 병렬로 동시 실행 (PARALLEL EXECUTION)
--------------------------------------------------------------------------------
-- 제어 루프와 입력 루프를 동시에 실행하며, 한쪽이 끝나거나 에러가 나면 함께 종료됩니다.
--parallel.waitForAny(controlLoop, inputLoop)

-- 메인 파일에서 병렬 처리를 제어할 수 있도록 두 루프 함수를 그대로 반환합니다.
return {
    controlLoop = controlLoop,
    inputLoop = inputLoop
}