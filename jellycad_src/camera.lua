--[[
Copyright (c) 2025. Li Jianbin. All rights reserved.
MIT License
JellyCAD version v0.3.10
Mockway Structure Camera Base Model File
--]]
local config = require('config')

local h_cam_base = 3

function model_cam0()
    local cam0 = cylinder.new(config.r_flank_outer, h_cam_base)
    for i = 0, 5 do
        local rad = i * math.pi / 3 -- 60° = π/3
        local x0 = config.r_flank_screw_pos * math.cos(rad);
        local y0 = config.r_flank_screw_pos * math.sin(rad);
        local screw_inner = cylinder.new(config.r_m3_hole, h_cam_base):pos(x0, y0, 0)
        cam0:cut(screw_inner)
    end
    return cam0:copy()
end

function model_cam()
    local cam = model_cam0()
    local width = 24
    local r = (width / 2) / math.sin(math.pi / 4)
    for i = 0, 3 do
        local rad = i * math.pi / 2 - math.pi / 4 -- 90° = π/2
        -- 固定在电机法兰上的M3螺丝孔
        local x4 = r * math.sin(rad);
        local y4 = r * math.cos(rad);
        local screw_inner = cylinder.new(2.2, 1.2):pos(x4, y4, h_cam_base)
        cam:fuse(screw_inner)
        cam:cut(cylinder.new(config.r_m2_tapping, h_cam_base + 1.2):pos(x4, y4, 0));
    end
    return cam:copy()
end

if config.generate_step_file then
    -- 生成STEP文件用于3D打印
    model_cam():color('gray'):export_step('camera.step')
end
if not debug.getinfo(3, "S") then
    -- 此文件为主模块时，显示完整模型
    model_cam():color('gray'):show()
end

return { m = model_cam0():scale(1e-3) }
