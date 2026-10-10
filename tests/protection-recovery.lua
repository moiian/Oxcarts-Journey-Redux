local protection=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/protection.lua'))()
local messages={}
local state=protection.new(function(s) messages[#messages+1]=s end)
local function controller(id,initial)
    return {value=initial,writes=0,get_Valid=function() return true end,get_address=function() return id end,
        call=function(self,method,value)
            if method=='get_IsInvincible()' then return self.value end
            assert(method=='set_IsInvincible(System.Boolean)')
            self.value=value;self.writes=self.writes+1
        end}
end
local function go(id)
    return {get_Valid=function() return true end,get_address=function() return id end}
end
local a,b=controller(1,false),controller(2,true)
local ga,gb=go(10),go(20)
local targets={{go=ga,label='ox'},{go=gb,label='part'}}
local function resolve(g) return {g==ga and a or b} end
state:tick(targets,resolve,100)
assert(a.value and b.value and a.writes==1 and b.writes==0)
state:tick(targets,resolve,100.25)
assert(a.writes==1 and #messages==2,'Unchanged refresh spammed setters/logs')
a.value=false;state:tick(targets,resolve,100.5);assert(a.value,'Native flag not renewed')
state:tick({targets[2]},resolve,101)
assert(not a.value and b.value,'Leaving cart did not restore ox')
state:clear();assert(b.value and next(state.owned)==nil,'Original invincibility lost')
state:tick({targets[1]},resolve,102);state:clear();assert(not a.value,'Reset leaked protection')
state:tick({targets[1]},function() error('Unsupported API') end,103)
assert(not a.value and #messages>2,'Unsupported API was silent')
print('PASS: native invincibility enable/readback, refresh, prior true state, cart change, reset and failure logging')

local pelvis=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/pelvis.lua'))()
Vector3f={new=function(x,y,z) return {x=x,y=y,z=z} end};log={error=error}
local hip={p={x=0,y=1.42,z=0},writes=0,get_Valid=function() return true end,get_Name=function() return 'hip' end}
function hip:get_Position() return self.p end
function hip:set_Position(p) self.p=p;self.writes=self.writes+1 end
local tr={get_Position=function() return {x=0,y=0,z=0} end,
    get_Joints=function() return {get_elements=function() return {hip} end} end}
local ch={get_Valid=function() return true end,get_Transform=function() return tr end}
local anchor={get_Valid=function() return true end,get_AxisY=function() return {x=0,y=1,z=0} end}
local binding={char=ch,slot=1}
local function tick(t) pelvis.tick({binding},anchor,{},true,t) end
tick(100);assert(pelvis.states[binding].baseline==nil)
tick(100.299);assert(hip.writes==0 and pelvis.states[binding].baseline==nil)
hip.p.y=0.77;tick(100.301)
assert(math.abs(pelvis.states[binding].baseline-0.77)<0.00001 and hip.writes==0,'Captured unstable baseline')
hip.p={x=0,y=1.42,z=0};tick(101)
assert(math.abs(hip.p.y-0.77)<0.00001,'Post-delay compensation failed')
pelvis.invalidate(binding);tick(102);tick(102.299)
assert(pelvis.states[binding].baseline==nil,'New pose did not restart delay')
hip.p={x=0,y=0.9,z=0};tick(102.301)
assert(math.abs(pelvis.states[binding].baseline-0.9)<0.00001,'New pose retained prior height')
pelvis.tick({binding},anchor,{},false,103)
assert(next(pelvis.states)==nil)
print('PASS: pelvis 0.3s delayed baseline, settled height, new-pose delay restart and disabled cleanup')

local f=assert(io.open('reframework/autorun/Oxcarts Journey Redux/journey.lua','r'))
local source=f:read('*a');f:close()
local exit=assert(source:match('if prior_player_seat_state and not physically_sitting then(.-)\n    end\n    prior_player_seat_state'))
local released=0
local env={seat_bindings={},release_pawns_at_intermediate_stop=function() released=released+1 end,
    stop_cart_rush=function() error('Standing up must not stop rush') end,
    cart_trip=setmetatable({}, {__newindex=function() error('Standing up must not reset speed') end})}
assert(load(exit,'passenger exit','t',env))()
assert(released==1,'Standing up did not release companions')
print('PASS: actual passenger-exit branch releases companions without cancelling speed lease or manual speed')
