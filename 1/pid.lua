--- 제어 시스템을 다룰 때 유용하게 사용할 수 있는 기본 PID 타입 및 공통 연산 라이브러리입니다.
--
-- PID 제어에 대한 기초 설명은 [위키백과][wiki]를 참조하세요.
-- [wiki]: https://ko.wikipedia.org/wiki/PID_제어기
--
-- 만약 [CCSharp][ccsharp] 환경에서 사용하려는 경우, 호환 가능한 [PID.cs][ccsharp-pid] 파일이 존재합니다.
-- [ccsharp]: https://github.com/monkeymanboy/CCSharp
-- [ccsharp-pid]: https://github.com/monkeymanboy/CCSharp/blob/master/src/CCSharp/AdvancedMath/PID.cs
--
-- @module pid
-- @author TechTastic

local expect = require "cc.expect"
local expect = expect.expect -- 매개변수 타입 검증용 라이브러리
local metatable

--- 목표치(Setpoint)가 일반 숫자(스칼라)일 때의 PID 제어 단계를 수행합니다.
--
-- @tparam pid self PID 인스턴스 본인
-- @tparam number value 현재 측정된 값
-- @tparam number dt 이전 단계 이후 경과한 시간 (주기)
-- @treturn number 최종 제어 출력값
-- @usage output = pid:step(value)
-- @usage output = pid:step(value, 0.5)
-- @local
local function scalarStep(self, value, dt)
    expect(1, value, "number")
    expect(2, dt, "number", "nil")
    dt = dt or 1 -- dt 값이 없으면 기본값 1초 사용

    local error = self.sp - value -- 오차 계산 (목표치 - 현재치)
    local p = self.kp * error     -- P(비례) 항 계산

    -- I(적분) 항 계산 방식 선택
    if self.discrete then
        -- 이산 제어: 현재 오차를 시간에 곱해 단순 누적
        self.integral = self.integral + error * dt
    else
        -- 연속 제어: 이전 오차와 현재 오차의 평균을 사용하여 더 부드럽게 누적 (사다리꼴 공식)
        self.integral = self.integral + (error + self.prev_error) * dt * 0.5
    end

    -- 안티 윈드업 (적분 누적값 한계 제한)
    if self.integral_min and self.integral_max then
        self.integral = math.max(self.integral_min, math.min(self.integral_max, self.integral))
    end

    local i = self.ki * self.integral                       -- I(적분) 항 완성
    local d = self.kd * (error - self.prev_error) / dt      -- D(미분) 항 계산 (오차의 변화율)
    self.prev_error = error                                 -- 다음 단계를 위해 현재 오차 기록
    
    local output = p + i + d                                -- 최종 PID 출력 합산

    -- 출력값 한계 제한 (클램프)
    if self.output_min and self.output_max then
        return math.max(self.output_min, math.min(self.output_max, output))
    end
    return output
end

--- 목표치(Setpoint)가 3차원 벡터(Vector)일 때의 PID 제어 단계를 수행합니다.
--
-- @tparam pid self PID 인스턴스 본인
-- @tparam table value 현재 측정된 벡터 값
-- @tparam number dt 이전 단계 이후 경과한 시간 (주기)
-- @treturn vector 최종 제어 출력 벡터
-- @usage output = pid:step(value)
-- @usage output = pid:step(value, 0.5)
-- @local
local function vectorStep(self, value, dt)
    expect(1, value, "table")
    if (getmetatable(value) or {}).__name ~= "vector" then expect(1, value, "vector") end
    expect(2, dt, "number", "nil")
    dt = dt or 1

    local error = self.sp - value -- 벡터 오차 계산
    local p = error * self.kp     -- 벡터 비례 연산
    
    if self.discrete then
        self.integral = self.integral + error * dt
    else
        self.integral = self.integral + (error + self.prev_error) * dt * 0.5
    end

    -- 3차원 벡터 각 성분(X, Y, Z)별 적분 누적값 한계 제한
    if self.integral_min and self.integral_max then
        self.integral = vector.new(
            math.max(self.integral_min, math.min(self.integral_max, self.integral.x)),
            math.max(self.integral_min, math.min(self.integral_max, self.integral.y)),
            math.max(self.integral_min, math.min(self.integral_max, self.integral.z))
        )
    end

    local i = self.integral * self.ki
    local d = (error - self.prev_error) * (self.kd / dt)
    self.prev_error = error
    
    local output = p + i + d

    -- 3차원 벡터 각 성분(X, Y, Z)별 최종 출력값 한계 제한
    if self.output_min and self.output_max then
        return vector.new(
            math.max(self.output_min, math.min(self.output_max, output.x)),
            math.max(self.output_min, math.min(self.output_max, output.y)),
            math.max(self.output_min, math.min(self.output_max, output.z))
        )
    end
    return output
end

--- 목표치(Setpoint)가 회전 사원수(Quaternion)일 때의 PID 제어 단계를 수행합니다.
-- 기체의 회전 각속도 제어 출력을 얻을 때 사용됩니다.
--
-- @tparam pid self PID 인스턴스 본인
-- @tparam table value 현재 측정된 사원수 값
-- @tparam number dt 이전 단계 이후 경과한 시간 (주기)
-- @treturn vector 각속도 보정을 위한 최종 제어 출력 벡터
-- @usage output = pid:step(value)
-- @usage output = pid:step(value, 0.5)
-- @local
-- @see quaternion
local function quaternionStep(self, value, dt)
    expect(1, value, "table")
    if (getmetatable(value) or {}).__name ~= "quaternion" then expect(1, value, "quaternion") end
    expect(2, dt, "number", "nil")
    dt = dt or 1

    -- 사원수 회전 오차 계산 (목표 회전 상태와 현재 회전 상태의 차이 변환)
    local error_quat = self.sp * value:inverse()
    -- 사원수 오차를 회전축 벡터와 회전각(라디안) 정보의 회전 벡터로 변환
    local error_vec = error_quat:getAxis() * error_quat:getAngle()
    
    local p = error_vec * self.kp
    if self.discrete then
        self.integral = self.integral + error_vec * dt
    else
        self.integral = self.integral + (error_vec + self.prev_error) * dt * 0.5
    end

    -- 사원수 기반 제어에서도 적분 누적치 제한은 벡터 단위로 수행
    if self.integral_min and self.integral_max then
        self.integral = vector.new(
            math.max(self.integral_min, math.min(self.integral_max, self.integral.x)),
            math.max(self.integral_min, math.min(self.integral_max, self.integral.y)),
            math.max(self.integral_min, math.min(self.integral_max, self.integral.z))
        )
    end

    local i = self.integral * self.ki
    local d = (error_vec - self.prev_error) * (self.kd / dt)
    self.prev_error = error_vec

    local output = p + i + d
    if self.output_min and self.output_max then
        return vector.new(
            math.max(self.output_min, math.min(self.output_max, output.x)),
            math.max(self.output_min, math.min(self.output_max, output.y)),
            math.max(self.output_min, math.min(self.output_max, output.z))
        )
    end
    return output
end

--- 생성자 (Constructors)
--
-- @section Constructors

--- 숫자(스칼라), 벡터, 사원수 타겟에 모두 대응하는 새로운 PID 제어기를 생성합니다.
--
-- @tparam number|vector|quaternion target 도달하고자 하는 목표치 (SetPoint)
-- @tparam number p 비례 이득 (Kp) - 현재 오차에 얼마나 공격적으로 반응할지 설정
-- @tparam number i 적분 이득 (Ki) - 누적된 잔류 오차를 얼마나 공격적으로 제거할지 설정
-- @tparam number d 미분 이득 (Kd) - 오차의 변화율(진동)을 얼마나 공격적으로 억제할지 설정
-- @tparam boolean discrete 이산 시간 기반으로 연산할지(true), 연속 시간 기반으로 연산할지(false) 설정
-- @treturn table 입력된 인자들로 초기화된 PID 제어기 인스턴스
-- @usage local 제어기 = pid.new(목표고도, 3.0, 0.1, 2.0)
-- @export
-- @see quaternion
function new(target, p, i, d, discrete)
    expect(1, target, "table", "number")

    local targetMeta = getmetatable(target) or {}
    if type(target) == "table" and targetMeta.__name ~= "vector" and targetMeta.__name ~= "quaternion" then
        expect(1, target, "vector", "quaternion", "number")
    end
    expect(2, p, "number", "nil")
    expect(3, i, "number", "nil")
    expect(4, d, "number", "nil")
    expect(5, discrete, "boolean", "nil")

    -- 제어기 기본 인스턴스 테이블 생성
    local controller = {
        sp = target or 1,
        kp = p or 1,
        ki = i or 0,
        kd = d or 0,
        discrete = (discrete == nil) and true or discrete -- nil일 때 기본값 true 제공
    }
    
    -- 목표치(Target)의 데이터 타입에 따라 적절한 제어 연산 함수(step) 및 변수 타입을 동적 매핑
    if type(target) == "number" then
        controller.step = scalarStep
        controller.integral = 0
        controller.prev_error = 0
    elseif type(target) == "table" then
        if targetMeta.__name == "vector" then
            controller.step = vectorStep
            controller.integral = vector.new()
            controller.prev_error = vector.new()
        elseif targetMeta.__name == "quaternion" then
            controller.step = quaternionStep
            controller.integral = vector.new()
            controller.prev_error = vector.new()
        end
    end
    return setmetatable(controller, metatable)
end

--- PID 제어기 객체 정의 (메서드 집합)
--
-- @type PID
local pid = {
    --- 도달해야 할 목표치입니다. 데이터 형태에 따라 Vector 혹은 Quaternion 타입이 사용될 수 있습니다.
    -- @field sp
    -- @tparam number|vector|quaternion sp

    --- 비례 이득 (Proportional Gain)
    -- @field kp
    -- @tparam number kp

    --- 적분 이득 (Integral Gain)
    -- @field ki
    -- @tparam number ki

    --- 미분 이득 (Derivative Gain)
    -- @field kd
    -- @tparam number kd

    --- 시스템을 이산 제어로 처리할지 연속 제어로 처리할지 여부
    -- @field discrete
    -- @tparam boolean discrete

    --- PID 제어 단계를 1회 수행합니다. (생성자 호출 시 데이터 타입에 맞는 내부 함수로 자동 대체됩니다.)
    -- @tparam PID self PID 인스턴스 본인
    -- @tparam number|vector|quaternion value 현재 측정된 환경 데이터 값
    -- @tparam number dt 이전 단계로부터 경과한 시간
    -- @treturn number|vector|quaternion 시스템 제어를 위한 출력값
    step = function() end,

    --- 최종 제어 출력값의 최소/최대 한계 범위를 활성화하거나 설정합니다.
    --
    -- @tparam PID self PID 인스턴스 본인
    -- @tparam number min 허용할 최소 출력값
    -- @tparam number max 허용할 최대 출력값
    clampOutput = function(self, min, max)
        expect(2, min, "number", "nil")
        if min then
            expect(3, max, "number")
        else
            expect(3, max, "nil")
        end
        if min and max and min >= max then
            error("Wrong range! check min < max")
        end
        self.output_min = min
        self.output_max = max
    end,

    --- 안티 윈드업(Anti-windup)을 위한 적분 누적치(Integral)의 최소/최대 한계 범위를 설정합니다.
    --
    -- @tparam PID self PID 인스턴스 본인
    -- @tparam number min 허용할 최소 적분 누적치
    -- @tparam number max 허용할 최대 적분 누적치
    limitIntegral = function(self, min, max)
        expect(2, min, "number", "nil")
        if min then
            expect(3, max, "number")
        else
            expect(3, max, "nil")
        end
        if min and max and min >= max then
            error("Wrong range! check min < max")
        end
        self.integral_min = min
        self.integral_max = max
    end,

    --- PID 인스턴스의 현재 설정 상태를 가독성 좋은 문자열로 변환합니다.
    --
    -- @tparam PID self PID 인스턴스 본인
    -- @treturn string 현재 PID 정보 문자열
    tostring = function(self)
        local mode = self.discrete and "Discrete" or "Continuous"
        local sp = tostring(self.sp)
        -- 수정 노트: 원래 코드는 %d를 사용하여 소수점 이하 계수(예: 0.5 -> 0)를 버리는 치명적 버그가 있었습니다.
        -- %g 서식 지정자를 사용하여 소수점을 정확하게 포함한 문자열로 포맷팅합니다.
        return string.format("%s PID {SP = %s, Kp = %g, Ki = %g, Kd = %g}", mode, sp, self.kp, self.ki, self.kd)
    end
}

-- 메타테이블 연결을 통해 객체 지향 문법(인스턴스:메서드) 및 print(인스턴스) 기능 지원
metatable = {
    __name = "PID",
    __index = pid,
    __tostring = pid.tostring
}

return {new = new}