-- main.lua

local hControll = require("hControll")
local vControll = require("vControll")
local angleControll = require("angleControll")

print("=== MovingState Controll Start ===")

-- 3개의 무한 루프 스레드를 동시에 병렬 실행합니다.
parallel.waitForAny(
    hControll.start,          -- 1. 수평 조이스틱 제어 루프
    vControll.controlLoop,    -- 2. 수직 고도/자세 PID 제어 루프
    angleControll.start,
    vControll.inputLoop       -- 4. 터미널 키보드 입력 루프
)