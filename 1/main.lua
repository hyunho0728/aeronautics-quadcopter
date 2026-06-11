-- main.lua

local hControll = require("hControll")
local vControll = require("vControll")
local angleControll = require("angleControll")
local sendAlt = require("sendAlt") -- 💡 고도 및 목표 데이터를 전송하는 모듈

print("=== MovingState Controll Start ===")

-- 5개의 무한 루프 스레드를 동시에 병렬 실행합니다.
parallel.waitForAny(
    hControll.start,          -- 1. 수평 조이스틱 및 자동 좌표 제어 루프
    vControll.controlLoop,    -- 2. 수직 고도/자세 PID 제어 루프
    angleControll.start,      -- 3. 회전 방향 제어 루프
    vControll.inputLoop,      -- 4. 터미널 무선 명령 통합 수신 루프 (고도, 좌표, EXIT)
    sendAlt.start             -- 5. 실시간 고도 데이터 무선 송신 루프
)