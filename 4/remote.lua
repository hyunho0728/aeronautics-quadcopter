-- remote.lua
local MODEM_SIDE = "back"   -- Pocket computers usually use "back"
local CHANNEL = 55          -- 무선 채널 번호

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then
    error("Error: Modem not found on side " .. MODEM_SIDE)
end
modem.open(CHANNEL)

-- 상단 계기판 UI 드로잉 함수
local function drawUI(curAlt, tarAlt, dist)
    -- 입력창 라인을 제외한 상단 1~6번 줄만 골라서 지우고 갱신
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

-- [스레드 1] 1/sendAlt.lua가 보내주는 실시간 고도를 수신하여 화면 상단에 갱신
local function receiveLoop()
    while true do
        local event, side, channel, replyChannel, packet, distance = os.pullEvent("modem_message")
        
        if type(packet) == "table" and packet.type == "TELEMETRY" then
            drawUI(packet.currentAlt, packet.targetAlt, distance)
        end
    end
end

-- [스레드 2] 사용자 고도 조작 입력 루프
local function inputLoop()
    while true do
        -- 하단 7~9번째 줄에 입력 프롬프트 배치
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
        
        -- 상대 고도 패턴 매칭 (+ 혹은 - 부호 검사)
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
            -- 절대 고도 숫자 처리
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

-- 메인 실행부
term.clear()
drawUI(0, 0, 0)
parallel.waitForAny(receiveLoop, inputLoop)
term.clear()
term.setCursorPos(1,1)
print("Controller closed.")