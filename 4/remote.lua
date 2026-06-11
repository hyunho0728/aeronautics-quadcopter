-- remote.lua
local MODEM_SIDE = "back"   -- Pocket computers usually use "back"
local CHANNEL = 55          -- Must match the drone's channel

-- 이제 기체 ID(TARGET_ID)를 일일이 맞추지 않아도 채널만 같으면 제어 가능합니다.
while true do
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Remote Altitude Controller ===")
    print("Channel: " .. CHANNEL)
    print("----------------------------------")
    io.write("Enter new target altitude (m): ")
    
    local input = read()
    
    if input == "exit" then
        print("Closing controller...")
        break
    end
    
    local num = tonumber(input)
    if num then
        local modem = peripheral.wrap(MODEM_SIDE)
        if modem then
            -- 💡 vControll.lua 규격에 맞는 패킷 구조로 변경
            local packet = {
                type = "SET_ALT",
                value = num
            }
            modem.transmit(CHANNEL, CHANNEL, packet)
            print(">> Transmitted: " .. num .. "m")
            sleep(0.7)
        else
            print("Error: Modem not found on side " .. MODEM_SIDE)
            sleep(1)
        end
    else
        print("Error: Input is not a number!")
        sleep(1)
    end
end