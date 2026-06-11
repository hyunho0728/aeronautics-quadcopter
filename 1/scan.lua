-- 네트워크에 연결된 모든 주변장치의 이름을 가져옵니다
local devices = peripheral.getNames()

-- 연결된 장치가 하나도 없다면 프로그램을 종료합니다
if #devices == 0 then
    print( "Error: No devices found on the network" )
    print( "Check your wired modems and right-click them!" )
    return
end

-- 파일 쓰기 모드(w)로 'methods.txt'를 생성하거나 엽니다
local file = fs.open("methods.txt", "w")
if not file then
    print( "Error: Cannot create file" )
    return
end

-- 화면 출력(print)과 파일 저장(writeLine)을 동시에 처리하는 헬퍼 함수
local function writeLog(text)
    print(text)
    file.writeLine(text)
end

writeLog( "=== Network Device Scanner ===" )
writeLog( "Found " .. #devices .. " device(s).\n" )

-- 찾은 장치들을 하나씩 반복하며 검사합니다
for _, name in ipairs(devices) do
    -- 장치의 종류(Type)를 가져옵니다 (예: drive, monitor 등)
    local pType = peripheral.getType(name)
    
    writeLog( ">> Device Name: " .. name )
    writeLog( "   Type: " .. pType )
    writeLog( "   --- Available Methods ---" )
    
    -- 해당 장치가 가진 모든 함수(메서드) 목록을 가져옵니다
    local methods = peripheral.getMethods(name)
    
    if methods then
        -- 함수 이름들을 하나씩 화면과 파일에 출력합니다
        for _, method in ipairs(methods) do
            writeLog( "   - " .. method )
        end
    else
        writeLog( "   (No methods available)" )
    end
    
    -- 장치 간의 구분을 위해 줄바꿈을 하나 넣어줍니다
    writeLog( "" )
end

-- 모든 작업이 끝났으므로 파일을 안전하게 닫아줍니다
file.close()

print( "----------------------------------------" )
print( "Success: Results saved to 'methods.txt'" )