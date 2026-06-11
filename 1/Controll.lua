-- peripheral.wrap을 사용해 고유 장치 이름으로 직접 연결 (껐다 켜도 절대 안 꼬임)
local monitor = peripheral.wrap("top")                
local altitude_sensor = peripheral.wrap("left")       
local velocity_sensor_x = peripheral.wrap("front")    
local velocity_sensor_z = peripheral.wrap("right")    

-- 릴레이 장치 고정 (필요 시 입력/출력 제어용으로 활용 가능)
local relays = { peripheral.wrap("redstone_relay_12"), peripheral.wrap("redstone_relay_13") }

local current_velocity_x = 0 -- 현재 X축 속도
local current_velocity_z = 0 -- 현재 Z축 속도
local current_altitude = altitude_sensor.getHeight() -- 현재 고도
local target_altitude = current_altitude -- 목표 고도
local tolerance = 4
local altitude_dist = target_altitude - current_altitude

-- PID 제어 게인 설정
local Kp = 2.5   -- P(비례): 제어 반응 속도
local Ki = 0.05  -- I(적분): 중력을 버티고 고도를 유지하는 핵심 값 (부드러운 유지를 위해 0.05 지정)
local Kd = 4.5   -- D(미분): 출렁거림을 잡는 브레이크

-- PID 내부 계산용 변수
local integral = 0
local previous_error = 0
local dt = 0.05

-- 네트워크에 잡힌 고유 이름(thruster_번호)으로 배열 직접 매핑
local left_thrusters = { peripheral.wrap("thruster_8"), peripheral.wrap("thruster_7") }
local right_thrusters = { peripheral.wrap("thruster_11"), peripheral.wrap("thruster_12") }
local front_thruster = { peripheral.wrap("thruster_9"), peripheral.wrap("thruster_10") } 
local back_thrusters = { peripheral.wrap("thruster_14"), peripheral.wrap("thruster_13") } 
local bottom_thrusters = { peripheral.wrap("thruster_20"), peripheral.wrap("thruster_21"), peripheral.wrap("thruster_24"), peripheral.wrap("thruster_23") } 

-- 신호 종류
-- w : 앞으로 가속
-- s : 뒤로 가속
-- a : 왼쪽으로 가속
-- d : 오른쪽으로 가속
-- q : 왼쪽으로 회전
-- e : 오른쪽으로 회전
-- space : 모든 상승
-- shift : 모든 하강

function main()
    while true do
        -- 위치값 업데이트
        current_velocity_x = velocity_sensor_x.getVelocity()
        current_velocity_z = velocity_sensor_z.getVelocity()
        current_altitude = altitude_sensor.getHeight()

        if relays[1].getAnalogInput("top") == 15 then
            target_altitude = target_altitude + 0.3
        elseif relays[2].getAnalogInput("top") == 15 then
            target_altitude = target_altitude - 0.3
        end
        
        -- PID 제어를 위한 오차(Error) 계산
        local error = target_altitude - current_altitude
        altitude_dist = error

        -- P 항 계산
        local P = Kp * error

        -- I 항 계산 (고도 유지의 원동력, 오차가 작을 때 정밀하게 누적)
        if math.abs(error) < 3 then
            integral = integral + (error * dt)
        else
            integral = 0
        end
        local I = Ki * integral

        -- D 항 계산
        local derivative = (error - previous_error) / dt
        local D = Kd * derivative

        previous_error = error

        -- PID 총 출력값 계산
        local final_power = P + I + D

        -- [개선된 하강 및 유지 제약 조건]
        -- 목표 고도보다 높아져서 내려가야 할 때도 추진기를 완전히 끄지 않고, 
        -- 최소한의 출력(예: 1.5)을 유지하여 추락하지 않고 부드럽게 내려앉도록 합니다.
        if final_power > 15 then
            final_power = 15
        elseif final_power < 1.5 then 
            final_power = 1.5 -- 하강 시 최소 출력 제한 (완전히 꺼지는 것 방지)
        end

        -- 하단 추진기에 부드럽게 조절된 파워 적용
        for _, thruster in ipairs(bottom_thrusters) do
            thruster.setPower(final_power)
        end

        -- 주변 추진기들은 다른 조종 신호가 없을 때는 대기(0) 상태 유지
        for _, thruster in ipairs(left_thrusters) do thruster.setPower(0) end
        for _, thruster in ipairs(right_thrusters) do thruster.setPower(0) end
        for _, thruster in ipairs(front_thruster) do thruster.setPower(0) end
        for _, thruster in ipairs(back_thrusters) do thruster.setPower(0) end

        --출력
        if monitor then
            monitor.clear()
            monitor.setCursorPos(1, 1)
            monitor.write(string.format("Velocity X: %.2f m/s", current_velocity_x))
            monitor.setCursorPos(1, 2)
            monitor.write(string.format("Velocity Z: %.2f m/s", current_velocity_z))
            monitor.setCursorPos(1, 3)
            monitor.write(string.format("Current Altitude: %.2f m", current_altitude))
            monitor.setCursorPos(1, 4)
            monitor.write(string.format("Target Altitude: %.2f m", target_altitude))
            monitor.setCursorPos(1, 5)
            monitor.write(string.format("Thruster Power: %.1f", final_power))
        end

        os.sleep(0.05) -- 1초마다 상태를 업데이트합니다
    end
end

main()