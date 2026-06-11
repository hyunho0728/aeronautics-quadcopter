-- remote.lua
local MODEM_SIDE = "back"   -- Pocket computers usually use "back"
local CHANNEL = 55          -- 무선 채널 번호

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then
    error("Error: Modem not found on side " .. MODEM_SIDE)
end
modem.open(CHANNEL)

-- 외부 파일 없이 안전하게 단독 구동되는 displayLine 내장
local helpers = require("helpers")

-- 상단 계기판 UI 드로잉 함수 (커서 위치 원상복구 로직 추가)
local function drawUI(curAlt, tarAlt, dist)
    -- 💡 현재 사용자가 입력 중이던 커서의 원래 위치를 백업합니다.
    local oldX, oldY = term.getCursorPos()

    helpers.displayLine(term, 1, "== Remote Monitor ==")
    helpers.displayLine(term, 2, string.format("Target : %6.2f m", tarAlt or 0))
    helpers.displayLine(term, 3, string.format("Current: %6.2f m", curAlt or 0))
    helpers.displayLine(term, 4, string.format("Error  : %+6.2f m", (tarAlt or 0) - (curAlt or 0)))
    helpers.displayLine(term, 5, string.format("Dist   : %6.1f m", dist or 0))

    -- 💡 상단 출력이 끝나면 커서를 사용자가 타이핑하던 원래 자리로 즉시 돌려놓습니다.
    -- 이 코드가 있어야 main이 켜져서 0.1초마다 화면을 갱신해도 입력창이 깨지지 않습니다.
    term.setCursorPos(oldX, oldY)
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

-- [스레드 2] 사용자 고도 조작 입력 루프
local function inputLoop()
    while true do
        -- 완충 지대 설정 및 하단 가이드라인 고정
        helpers.displayLine(term, 6, "")
        helpers.displayLine(term, 9, "--------------------")
        helpers.displayLine(term, 10, "Ex: 70, +1, -2, exit")
        
        -- 입력창 위치 잡기
        term.setCursorPos(1, 7)
        term.clearLine()
        io.write("> ")
        
        local input = read()
        
        if input == "exit" then
            local exitPacket = { type = "EXIT" }
            modem.transmit(CHANNEL, CHANNEL, exitPacket)
            helpers.displayLine(term, 12, ">> Sent EXIT")
            sleep(0.5)
            break
        end
        
        local sign, valueStr = input:match("^([%+%-])(%d+%.?%d*)$")
        
        if sign and valueStr then
            local num = tonumber(valueStr)
            if sign == "-" then num = -num end
            
            local packet = {
                type = "ADD_ALT",
                value = num
            }
            modem.transmit(CHANNEL, CHANNEL, packet)
            helpers.displayLine(term, 12, string.format(">> Sent: %+gm", num))
            sleep(0.5)
        else
            local num = tonumber(input)
            if num then
                local packet = {
                    type = "SET_ALT",
                    value = num
                }
                modem.transmit(CHANNEL, CHANNEL, packet)
                helpers.displayLine(term, 12, ">> Sent: " .. num .. "m")
                sleep(0.5)
            else
                helpers.displayLine(term, 12, "Err: Invalid input")
                sleep(0.8)
            end
        end
        
        helpers.displayLine(term, 12, "")
    end
end

-- 메인 실행부
term.clear()
drawUI(0, 0, 0)
parallel.waitForAny(receiveLoop, inputLoop)
term.clear()
term.setCursorPos(1, 1)
print("Controller closed.")