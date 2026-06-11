-- remote.lua
local MODEM_SIDE = "back"   -- Pocket computers usually use "back"
local CHANNEL = 55          -- 무선 채널 번호

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then
    error("Error: Modem not found on side " .. MODEM_SIDE)
end
modem.open(CHANNEL)

-- 💡 포켓 컴퓨터 내부에 생성된 helpers 모듈 참조
local helpers = require("helpers")

-- 상단 계기판 UI 드로잉 함수 (커서 위치 원상복구 로직 포함)
local function drawUI(curAlt, tarAlt, dist)
    -- 💡 실시간 수신 화면 갱신 중 사용자가 입력하던 커서 좌표를 기억합니다.
    local oldX, oldY = term.getCursorPos()

    helpers.displayLine(term, 1, "== Remote Monitor ==")
    helpers.displayLine(term, 2, string.format("Target : %6.2f m", tarAlt or 0))
    helpers.displayLine(term, 3, string.format("Current: %6.2f m", curAlt or 0))
    helpers.displayLine(term, 4, string.format("Error  : %+6.2f m", (tarAlt or 0) - (curAlt or 0)))
    helpers.displayLine(term, 5, string.format("Dist   : %6.1f m", dist or 0))

    -- 💡 출력이 끝나면 즉시 타이핑하던 원래 자리로 커서를 되돌려 놓습니다.
    term.setCursorPos(oldX, oldY)
end

-- [스레드 1] 실시간 고도 및 상태 수신 루프
local function receiveLoop()
    while true do
        local event, side, channel, replyChannel, packet, distance = os.pullEvent("modem_message")
        
        if type(packet) == "table" and packet.type == "TELEMETRY" then
            drawUI(packet.currentAlt, packet.targetAlt, distance)
        end
    end
end

-- [스레드 2] 사용자 고도 조작 및 특정 좌표 입력 처리 루프
local function inputLoop()
    while true do
        -- 💡 6번 라인을 공백으로 비워두어 read() 실행 시 상단 계기판이 터지는 현상을 완벽 격리
        helpers.displayLine(term, 6, "")
        
        -- 💡 도움말 가이드는 입력 커서보다 아래쪽(9~10번 라인)에 배치하여 간섭 원천 차단
        helpers.displayLine(term, 9, "--------------------")
        helpers.displayLine(term, 10, "Alt: 70, +1 / Pos: X Z")
        
        -- 입력창 위치 7번 라인에 고정
        term.setCursorPos(1, 7)
        term.clearLine()
        io.write("> ")
        
        local input = read()
        
        -- 💡 피드백 결과 출력은 가이드라인 아래쪽인 12번 줄 안전구역에서 수행
        if input == "exit" then
            local exitPacket = { type = "EXIT" }
            modem.transmit(CHANNEL, CHANNEL, exitPacket)
            helpers.displayLine(term, 12, ">> Sent EXIT")
            sleep(0.5)
            break
        end
        
        -- 💡 특정 좌표 입력 패턴 매칭 검사 (공백을 기준으로 숫자 2개 파싱, 예: "120 -350")
        local matchX, matchZ = input:match("^([%-%d+%.]+)%s+([%-%d+%.]+)$")
        
        if matchX and matchZ and tonumber(matchX) and tonumber(matchZ) then
            local tx = tonumber(matchX)
            local tz = tonumber(matchZ)
            
            local packet = {
                type = "MOVE_POS",
                targetX = tx,
                targetZ = tz
            }
            modem.transmit(CHANNEL, CHANNEL, packet)
            helpers.displayLine(term, 12, string.format(">> Go to X:%g Z:%g", tx, tz))
            sleep(0.5)
            
        else
            -- 기존 상대 고도 패턴 매칭 (+ 혹은 - 부호 검사)
            local sign, valueStr = input:match("^([%+%-])(%d+%.?%d*)$")
            
            if sign and valueStr then
                local num = tonumber(valueStr)
                if sign == "-" then num = -num end
                
                local packet = {
                    type = "ADD_ALT",
                    value = num
                }
                modem.transmit(CHANNEL, CHANNEL, packet)
                helpers.displayLine(term, 12, string.format(">> Sent Alt: %+gm", num))
                sleep(0.5)
            else
                -- 기존 절대 고도 숫자 처리
                local num = tonumber(input)
                if num then
                    local packet = {
                        type = "SET_ALT",
                        value = num
                    }
                    modem.transmit(CHANNEL, CHANNEL, packet)
                    helpers.displayLine(term, 12, ">> Sent Alt: " .. num .. "m")
                    sleep(0.5)
                else
                    helpers.displayLine(term, 12, "Err: Invalid Input")
                    sleep(0.8)
                end
            end
        end
        
        -- 연산 루프 종료 전 메시지 출력 라인 깔끔하게 소독
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