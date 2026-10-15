print("[llm_bridge] io=" .. tostring(io) .. " os=" .. tostring(os))
if io then
    local f = io.open("llm_bridge_probe.txt", "w")
    f:write("io works\n")
    f:close()
end
