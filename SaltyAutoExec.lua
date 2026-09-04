--// Salty AutoExec Loader
--// Put this file in your executor's autoexec folder.

repeat task.wait(0.1) until game:IsLoaded()
task.wait(0.5)

local RAW_URL = "https://raw.githubusercontent.com/MrRos3/SaltyAutoLevel/main/SaltyAutoLevel.lua"

local ok, err = pcall(function()
    loadstring(game:HttpGet(RAW_URL))()
end)

if not ok then
    warn("[Salty] autoexec loader failed:", err)
end
