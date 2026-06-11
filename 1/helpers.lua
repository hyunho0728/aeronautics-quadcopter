local M = {}

-- 모니터의 특정 행(row)에 텍스트를 출력하는 함수
function M.displayLine(monitor, row, text)
    monitor.setCursorPos(1, row)
    monitor.clearLine()
    monitor.write(text)
end

-- 값이 최소값과 최대값 범위를 벗어나지 않도록 고정하는 함수
function M.clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

return M