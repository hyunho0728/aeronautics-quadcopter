-- remote.lua
local MODEM_SIDE = "back"   -- Pocket computers usually use "back"
local CHANNEL = 55          -- 무선 채널 번호

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then
    error("Error: Modem not found on side " .. MODEM_SIDE)
end
modem.open(CHANNEL)

-- 💡 [수정] 포켓 컴퓨터 내부에 생성된 helpers 모듈을 올바르게 참조합니다.
-- 컴퓨터크래프트 환경에 따라 require("helpers") 또는 require("./helpers")를 사용합니다.
local helpers = require("helpers")

-- 상단 계기판 UI 드로잉 함수 (helpers.displayLine 적용)
local function drawUI(curAlt, tarAlt, dist)
    helpers.displayLine(term, 1, "== Remote Monitor ==")
    helpers.displayLine(term, 2, string.format("Target : %6.2f m", tarAlt or 0))
    helpers.displayLine(term, 3, string.format("Current: %6.2f m", curAlt or 0))
    helpers.displayLine(term, 4, string.format("Error  : %+6.2f m", (tarAlt or 0) - (curAlt or 0)))
    helpers.displayLine(term, 5, string.format("Dist   : %6.1f m", dist or 0))
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

-- [스레드 2] 사용자 고도 조작 입력 루프 (read 버퍼 간섭 완벽 해결)
local function inputLoop()
    while true do
        -- 💡 6번 줄을 공백으로 밀어두어 read() 실행 시 상단 계기판이 깨지는 것을 격리
        helpers.displayLine(term, 6, "")

        -- 💡 가이드라인 도움말은 read() 버퍼의 영향을 받지 않도록 아래쪽(9~10번 줄)에 배치
        helpers.displayLine(term, 9, "--------------------")
        helpers.displayLine(term, 10, "Ex: 70, +1, -2, exit")
        
        -- 💡 입력창 위치를 7번 줄로 확실하게 고정
        term.setCursorPos(1, 7)
        term.clearLine()
        io.write("> ")
        local input = read()
        
        -- 💡 전송 결과 메시지는 화면 가장 하단인 12번 줄 안전지대에서 출력
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
        
        -- 루프가 끝나기 전 결과 안내 라인 깔끔하게 청소
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