local function vec(x,y,z) return {x=x,y=y,z=z} end
Vector3f={new=vec};Quaternion={new=function(x,y,z,w) return {x=x,y=y,z=z,w=w} end}
local errors={};log={error=function(s) errors[#errors+1]=s end}
local function near(a,b) assert(math.abs(a-b)<0.00001,tostring(a)..' ~= '..tostring(b)) end
local actor={p=vec(10,0,20),q=Quaternion.new(0,0,0,1),get_Valid=function() return true end}
function actor:get_Position() return self.p end
function actor:set_Position(p) self.p=p end
function actor:get_Rotation() return self.q end
function actor:set_Rotation(q) self.q=q end
function actor:get_Transform() return self end
function actor:get_Joints() error('Display must not access skeleton') end
function actor:call() error('Display must not write physics') end
function actor:lookAt(target,up) self.facing=target;self.up=up;self.q=Quaternion.new(0,1,0,0) end
local anchor={p=vec(10,0,20),get_Valid=function() return true end,
 get_Position=function(self) return self.p end,get_AxisX=function() return vec(1,0,0) end,
 get_AxisY=function() return vec(0,1,0) end,get_AxisZ=function() return vec(0,0,1) end}
local binding={char=actor,root_spec={x=0,y=0,z=0},seat_spec={x=2,y=3,z=4,lookX=1,lookZ=0}}
local display=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/display.lua'))()
local function tick() display.tick({binding},function() return anchor end) end
tick();near(actor.p.x,12);near(actor.p.y,3);near(actor.p.z,24);near(actor.facing.x,13)
tick();near(actor.p.y,3);display.restore();near(actor.p.x,10);near(actor.p.y,0);near(actor.q.w,1)
-- Preserve newer engine/physics output.
tick();actor.p=vec(11,1,21);display.restore();near(actor.p.x,11);near(actor.p.y,1)
tick();display.release(binding);near(actor.p.x,11);near(actor.p.y,1)
tick();display.commit(binding,anchor);near(actor.p.x,12);display.restore();near(actor.p.x,12)
actor.p=vec(10,0,20);actor.q=Quaternion.new(0,0,0,1)
for _,q in ipairs({Quaternion.new(1,0,0,0),Quaternion.new(0,1,0,0),Quaternion.new(0,0,1,0)}) do
 actor.q=q
 for _,axis in ipairs({'x','y','z'}) do
  binding.seat_spec={x=0,y=0,z=0,lookX=0,lookZ=1};binding.seat_spec[axis]=0.5
  tick();near(actor.p.x,10+(axis=='x' and 0.5 or 0))
  near(actor.p.y,axis=='y' and 0.5 or 0);near(actor.p.z,20+(axis=='z' and 0.5 or 0))
  display.clear()
 end
end
anchor.get_AxisX=function() return vec(0,1,0) end
anchor.get_AxisY=function() return vec(-1,0,0) end
binding.seat_spec={x=2,y=3,z=4,lookX=1,lookZ=0}
tick();near(actor.p.x,7);near(actor.p.y,2);near(actor.p.z,24)
near(actor.up.x,-1);near(actor.facing.y,3);display.clear()
local original_look=actor.lookAt
actor.lookAt=function() error('Injected facing failure') end
tick();near(actor.p.x,10);near(actor.p.y,0);tick();assert(#errors==1,'Repeated display failure spammed logs')
actor.lookAt=original_look;display.clear()
_G.OJR_EnableRuntimeDiagnostics=nil
json={dump_file=function() error('Normal play wrote diagnostics') end}
local quiet=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/diagnostics.lua'))()
quiet.begin_pose({});quiet.mark_pose({});quiet.sample_pose({});quiet.cancel_pose({});quiet.close()
assert(next(quiet.traces)==nil)
local pelvis=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/pelvis.lua'))()
pelvis.tick({binding},anchor,{},true,1)
assert(next(pelvis.states)==nil,'Missing per-role flag enabled pelvis correction')
print('PASS: Transform display, cart axes/tilt, restore/commit, no skeleton/physics writes, error recovery, diagnostics off and pelvis opt-in')
