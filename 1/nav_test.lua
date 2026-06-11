local nav = peripheral.find("navigation_table")
local gimbal = peripheral.find("gimbal_sensor")

print(nav.getRelativeAngle())
print(textutils.serialize(gimbal.getAngles()))