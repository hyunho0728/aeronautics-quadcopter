-- remote.lua
local MODEM_SIDE = "back"   -- Pocket computers usually use "back"
local CHANNEL = 55          -- 무선 채널 번호

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then
    error("Error: Modem not found on side " .. MODEM_SIDE)
end
modem.open(CHANNEL)

-- 화면 UI를 그려주는 전용 함수
local function drawUI(curAlt, tarAlt, dist)
    -- 입력창(화면 하단)을 방해하지 않고 상단 1~6줄만 청소 후 갱신
    for i = 1, 6 do
        term.setCursorPos(1, i)
        term.clearLine()
    end
    
    term.setCursorPos(1, 1)
    print("=== Remote Controller & Monitor ===")
    print(string.format(" Drone Target  : %6.2f m", tarAlt or 0))
    print(string.format(" Drone Current : %6.2f m", curAlt or 0))
    print(string.format(" Error         : %+6.2f m", (tarAlt or 0) - (curAlt or 0)))
    print(string.format(" Signal Distance: %6.1f m", dist or 0))
    print("-----------------------------------")
end

-- [스레드 1] 실시간 고도 수신 루프
local function receiveLoop()
    while true do
        local event, side, channel, replyChannel, packet, distance = os.pullEvent("modem_message")
        
        if type(packet) == "table" and packet.type == "TELEMETRY" then
            drawUI(packet.currentAlt, packet.targetAlt, distance)
        end
    end
end

-- [스레드 2] 사용자 키보드 입력 및 조작 루프
local function inputLoop()
    while true do
        -- 하단 입력 위치 고정 (7번째 줄부터 입력)
        term.setCursorPos(1, 7)
        term.clearLine()
        print("Enter absolute(e.g. 70), relative(e.g. +1, -2) or 'exit'")
        io.write("Command: ")
        
        local input = read()
        
        if input == "exit" then
            local exitPacket = { type = "EXIT" }
            modem.transmit(CHANNEL, CHANNEL, exitPacket)
            term.setCursorPos(1, 10)
            print(">> Transmitted EXIT command to drone.")
            sleep(0.5)
            break
        end
        
        -- 상대 고도 패턴 매칭 (+ 또는 -로 시작하는지 확인)
        local sign, valueStr = input:match("^([%+%-])(%d+%.?%d*)$")
        
        if sign and valueStr then
            local num = tonumber(valueStr)
            if sign == "-" then num = -num end
            
            local packet = {
                type = "ADD_ALT",
                value = num
            }
            modem.transmit(CHANNEL, CHANNEL, packet)
            term.setCursorPos(1, 10)
            term.clearLine()
            print(string.format(">> Sent relative: %+gm", num))
            sleep(0.5)
        else
            -- 절대 고도 입력 처리
            local num = tonumber(input)
            if num then
                local packet = {
                    type = "SET_ALT",
                    value = num
                }
                modem.transmit(CHANNEL, CHANNEL, packet)
                term.setCursorPos(1, 10)
                term.clearLine()
                print(">> Sent absolute: " .. num .. "m")
                sleep(0.5)
            else
                term.setCursorPos(1, 10)
                term.clearLine()
                print("Error: Invalid Format!")
                sleep(0.8)
            end
        end
    end
end

-- 메인 실행부: 수신과 입력을 병렬로 동시에 실행
term.clear()
drawUI(0, 0, 0)
parallel.waitForAny(receiveLoop, inputLoop)
term.clear()
term.setCursorPos(1,1)
print("Controller closed.")