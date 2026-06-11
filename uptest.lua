-- Device Connections
local altitude_sensor = peripheral.wrap("left")
local monitor = peripheral.wrap("top")

-- Bottom Thrusters Mapping
local bottom_thrusters = {
    peripheral.wrap("thruster_20"),
    peripheral.wrap("thruster_21"),
    peripheral.wrap("thruster_24"),
    peripheral.wrap("thruster_23")
}

local test_power = 0 -- Current test power value

-- 1. Display loop for External Monitor
function display_loop()
    while true do
        if monitor then
            monitor.clear()
            monitor.setCursorPos(1, 1)
            monitor.write("=== Altitude Test ===")
            monitor.setCursorPos(1, 3)
            monitor.write(string.format("Power: %.1f", test_power))
            monitor.setCursorPos(1, 4)
            monitor.write(string.format("Altitude: %.2f m", altitude_sensor.getHeight()))
        end
        os.sleep(0.05)
    end
end

-- 2. Input loop for Computer Terminal
function input_loop()
    -- Initialization: Stop all bottom thrusters at start
    for _, thruster in ipairs(bottom_thrusters) do
        thruster.setPower(0)
    end

    while true do
        term.clear()
        term.setCursorPos(1, 1)
        print("=== Bottom Thruster Test ===")
        print("Enter a number between 0 and 15:")
        print(string.format("Current Power: %.1f", test_power))
        print("--------------------------------")
        write("Input: ")
        
        local input = read()
        local num = tonumber(input)

        if num and num >= 0 and num <= 15 then
            test_power = num
            -- Apply power to all bottom thrusters immediately
            for _, thruster in ipairs(bottom_thrusters) do
                thruster.setPower(test_power)
            end
        else
            print("\n[Error] Invalid number. (0 ~ 15)")
            os.sleep(1.5)
        end
    end
end

-- Run both loops simultaneously
parallel.waitForAny(input_loop, display_loop)