;(function()
local bus=_G.DD2_OxcartControl
local display=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/display.lua'))()
_G.OJR_CompanionDisplay=display
local cart={ox=ox,cow=cow,body=body,anchor=body,status=status}
local function near(a,b) assert(math.abs(a-b)<0.00001,tostring(a)..' ~= '..tostring(b)) end
bus.journey.begin_manual(cart)
bus.journey.bind_manual(cart)
local bindings=bus.journey.records()
assert(#bindings==3,'Missing companions')
local binding=bindings[1]
local ch=binding.char
local root=binding.root_spec
-- A slider edit affects display only; physical seat remains captured preset [1].
binding.seat_spec.y=root.y+1.25
clock=clock+0.02;bus.journey.manual_tick()
near(ch.pos.y,ch.test_controller.position.y+1.25)
local physics_y=ch.test_controller.position.y
display.restore()
near(ch.pos.y,physics_y)
display.apply(binding,body)
near(ch.pos.y,physics_y+1.25)
clock=clock+0.02;bus.journey.manual_tick()
near(ch.pos.y,physics_y+1.25);near(ch.test_controller.position.y,physics_y)
-- Photo-mode placement is display-only: no extra warp/fall/animation request.
local warps,falls=ch.test_controller.warps,ch.test_fall.reset_calls
is_paused=true;gui['<IsDispPhotoModeAll>k__BackingField']=true
clock=clock+0.02;bus.journey.manual_tick()
near(ch.pos.y,physics_y+1.25)
assert(ch.test_controller.warps==warps and ch.test_fall.reset_calls==falls)
is_paused=false;gui['<IsDispPhotoModeAll>k__BackingField']=false
local final_y=ch.pos.y
bus.journey.end_manual()
near(ch.test_controller.position.y,final_y)
near(ch.test_position_context.Position.y,final_y)
assert(ch.machine.enabled and #bus.journey.records()==0 and next(display.states)==nil)
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: real seat pipeline keeps physics on preset [1], displays slider edits, photo does not warp, exit hands display to physics and restores FSM')
end)()
