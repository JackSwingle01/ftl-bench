-- DEVELOPMENT ONLY: presses main-menu buttons so scripts/dev-run needs no clicking.
-- Reads ftlbench/autostart ("continue" or "new"), acts once per game launch. After "new" it
-- also answers the intro event, which would otherwise keep the game paused.
-- Uses the in-game input bindings from our Hyperspace fork.

local done, ticks, clicks = false, 0, 0
local MAX_CLICKS = 5 -- never keep clicking at a screen we did not expect
local KEY_1 = 49 -- SDLK_1

---@param button any GenericButton
local function click(button)
    local box = button.hitbox
    local x, y = math.floor(box.x + box.w / 2), math.floor(box.y + box.h / 2)
    local app = Hyperspace.App
    app:OnMouseMove(x, y, 0, 0, false, false, false)
    -- The mouse takes window coordinates, which fullscreen scales away from the button's; the
    -- menu acts on the button's hover flag, so set it directly.
    button.bHover = true
    app:OnLButtonDown(x, y)
    app:OnLButtonUp(x, y)
end

-- Read once at launch: scripts/dev-run deletes the file as soon as the Run is live.
local mode
do
    local f = io.open("ftlbench/autostart", "r")
    if f then
        mode = f:read("l")
        f:close()
    else
        done = true
    end
end

local function step()
    local app = Hyperspace.App
    local menu = app.menu
    if not menu.bOpen then
        -- A new Run opens with the intro event; press "1" (its only choice) once, then stop.
        if mode == "new" and app.gui.event_pause then
            app:OnKeyDown(KEY_1)
            app:OnKeyUp(KEY_1)
        end
        done = true
        return
    end
    clicks = clicks + 1
    if clicks > MAX_CLICKS then
        done = true
        print("[ftlbench] autostart gave up; finish starting the Run by hand")
        return
    end
    if menu.shipBuilder.bOpen then
        click(menu.shipBuilder.startButton)
    elseif mode == "continue" and menu.continueButton.bActive then
        click(menu.continueButton)
    else
        click(menu.startButton)
    end
end

script.on_internal_event(Defines.InternalEvents.ON_TICK, function()
    if done then
        return
    end
    ticks = ticks + 1
    if ticks % 60 == 0 then -- give each screen a second to settle
        local ok, err = pcall(step)
        if not ok then
            done = true
            print("[ftlbench] autostart error: " .. tostring(err))
        end
    end
end)
