-- DEVELOPMENT ONLY: replays an Action log for the determinism check (#15). Reads
-- ftlbench/replay.jsonl (a copied actions.jsonl) once per launch and sends each Command to the
-- bridge's inbox so the bridge handles it on the frame it was logged at.
local actions, next_action = {}, 1
do
    local f = io.open("ftlbench/replay.jsonl", "r")
    if f then
        for line in f:lines() do
            local frame = tonumber(line:match('"frame":(%d+)'))
            local command = line:match('"command":"(.-)"')
            if frame and command then
                actions[#actions + 1] = { frame = frame, command = command }
            end
        end
        f:close()
        print(("[ftlbench] replay: %d actions"):format(#actions))
    end
end

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    local frame = FtlBench.frame
    if not frame or next_action > #actions then
        return
    end
    if actions[next_action].frame > frame then
        return
    end
    local inbox = io.open("ftlbench/live/inbox.txt", "a")
    if not inbox then
        return
    end
    while next_action <= #actions and actions[next_action].frame <= frame do
        inbox:write(("replay-%d\t0\t%s\n"):format(next_action, actions[next_action].command))
        next_action = next_action + 1
    end
    inbox:close()
end)
