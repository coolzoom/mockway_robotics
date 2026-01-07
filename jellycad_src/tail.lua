local config = require('config')
tail = cylinder.new(config.r_flank_outer, config.h_tail)
tail:fuse(cylinder.new(config.r_flank_inner, config.h_tail_sum))
for i, deg in ipairs({ 0, 60, 120, 180, 240, 300 }) do
    local rad = deg * math.pi / 180;
    local x0 = config.r_flank_screw_pos * math.cos(rad);
    local y0 = config.r_flank_screw_pos * math.sin(rad);
    local screw_inner = cylinder.new(config.r_m3d4_nut, config.h_tail):pos(x0, y0, 0)
    tail:cut(screw_inner)
    -- 固定在电机法兰上的M3螺丝孔
    local x4 = config.r_screw_motor_flank * math.sin(rad);
    local y4 = config.r_screw_motor_flank * math.cos(rad);
    local screw_inner = cylinder.new(config.r_m3_hole, config.h_tail_sum):pos(x4, y4, 0)
    tail:cut(screw_inner)
    tail:cut(cone.new(config.r_m3_head, 0, config.r_m3_head):pos(x4, y4, 0));
end
tail:color('gray'):show()
-- tail:export_step('tail.step')
return { model = tail:copy(), m = tail:copy():scale(1e-3) }