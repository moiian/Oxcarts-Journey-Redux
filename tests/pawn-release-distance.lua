local player_position, body_position = {x=0,y=0,z=0}, {x=0,y=0,z=0}
local player={get_Transform=function() return {get_UniversalPosition=function() return player_position end} end}
local body={get_UniversalPosition=function() return body_position end}
local ox,body_available={},true
local function is_character_valid(ch) return ch~=nil end
local function find_cart_body() if body_available then return body end end
local ox_distance,releases,brakes=0,0,0
local function player_cart_distance() return ox_distance end
local function release_pawns_at_intermediate_stop() releases=releases+1 end
local function reset_auto_walk() end
local cart_trip={}
local status={call=function() return true end}
local function get_cart_action() return 'Dash' end
local function stop_cart_rush() brakes=brakes+1 end

-- BODY DISTANCE --

local function check()
-- RELEASE CHECK --
end

player_position.x=8;check();assert(releases==0,'Exactly 8 should not release')
player_position.x=8.01;check();assert(releases==1 and brakes==0,'Beyond body center 8 should release only pawns')
body_position.x=100;player_position.x=100;ox_distance=10;check()
assert(releases==1,'Player next to cart body should not release based on ox distance')
player_position.y=9;check();assert(releases==2,'Body-center distance must include height')
body_available=false;check();assert(releases==2,'Unknown body position must not release')
body_available=true;player_position.y=0;ox_distance=15;check()
assert(brakes==0,'Exactly 15 must not brake')
ox_distance=15.01;check()
assert(releases==2 and brakes==1,'Paid-trip brake beyond ox distance 15 should remain independent')
print('PASS: body-center release >8, exact boundary, height, unreadable body and independent paid-trip brake')
