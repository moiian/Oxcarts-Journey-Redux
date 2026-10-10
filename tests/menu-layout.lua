local function preset(name)
    local p={name=name,enabled=true,teleportPlayer=false,player={x=1},pawns={},driver={x=2},driver_camera={fov=70}}
    for i=1,9 do p.pawns[i]={x=i} end
    return p
end
local unified_presets=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/presets.lua'))()
local options={Presets={Normal={preset('Normal 1'),preset('Normal 2')},Rainy={preset('Rain 1')},Wealthy={preset('Luxury 1')}}}
local preset_cursor={Normal=1,Rainy=1,Wealthy=1}
local driving_bus={}
local pawn_seat_physics,seat_bindings={},{}
local seating_lock_active=true
local function find_active_ox() return {} end
local function find_cart_body() return {} end
local function classify_cart_model() return 'Normal' end
local function collect_companions() return {{},{},{}} end
local saved,applied,edited,tables,headers=0,0,{},0,{}
local function persist_options() saved=saved+1 end
local function restore_default_key_bindings() end
local function bind_pawns_to_seats(value) assert(value);applied=applied+1 end
function pawn_seat_physics.queue_preset(family,index)
    pawn_seat_physics.pending_preset={family=family,preset=options.Presets[family][index]}
end
local function behavior()
    local q=pawn_seat_physics.pending_preset
    pawn_seat_physics.pending_preset=nil
    if not q then return end
    for i,p in ipairs(options.Presets[q.family]) do
        if p==q.preset then preset_cursor[q.family]=i;bind_pawns_to_seats(true);return end
    end
end
local function draw_seat_editor(label) edited[#edited+1]=label or 'Player parameter' end
local input_bindings={imgui_rebind_button=function(_,v) return false,v end}
local callback,tree_depth,id_depth,table_depth=nil,0,0,0
local combo_requests,button_requests={},{}
local last_player_mode
local button_order={}
local imgui={}
function imgui.tree_node(label)
    local open=label~='Other Settings'
    if open then tree_depth=tree_depth+1 end
    return open
end
function imgui.tree_pop() tree_depth=tree_depth-1;assert(tree_depth>=0) end
function imgui.push_id() id_depth=id_depth+1 end
function imgui.pop_id() id_depth=id_depth-1;assert(id_depth>=0) end
function imgui.begin_table(_,n) assert(n==3);table_depth=table_depth+1;tables=tables+1;return true end
function imgui.end_table() table_depth=table_depth-1;assert(table_depth>=0) end
function imgui.table_next_row() assert(table_depth>0) end
function imgui.table_next_column() assert(table_depth>0) end
function imgui.table_header(label) headers[label]=true end
function imgui.same_line() end
function imgui.spacing() end
function imgui.separator() end
function imgui.text() end
function imgui.checkbox(label,value) assert(label~='Freeze companion FSM' and label~='Enabled');return false,value end
function imgui.input_text(_,value) return false,value end
function imgui.button(label) button_order[#button_order+1]=label;return button_requests[label]==true end
function imgui.combo(label,index,names)
    assert(label=='Cart type' or label=='Active layout' or label=='Player seat')
    assert(#names>0)
    if label=='Player seat' then
        last_player_mode=index
        assert(names[1]=='When player as driver' and names[2]=='When player as passenger')
    end
    if combo_requests[label] then return true,combo_requests[label] end
    return false,index
end
local re={on_draw_ui=function(fn) callback=fn end}
-- UI IMPLEMENTATION --
local function draw()
    callback()
    assert(tree_depth==0 and id_depth==0 and table_depth==0,'Unbalanced menu scopes')
end
draw();assert(tables==1 and headers.Action and headers.Gamepad and headers.Keyboard,'Backup keybind table missing')
assert(#edited==4 and edited[1]=='Player parameter','Menu displayed multiple preset editors or hid player parameters')
local add_index,delete_index
for i,label in ipairs(button_order) do
    if label=='+ Add New Preset (Max 15)###add_preset_Normal' then add_index=i end
    if label=='Delete Preset###del_Normal1' then delete_index=i end
end
assert(add_index and delete_index and add_index<delete_index,'Add button is not left of Delete')
combo_requests={['Active layout']=2};draw()
assert(preset_cursor.Normal==1 and applied==0 and pawn_seat_physics.pending_preset,'Menu applied a pose during UI draw')
behavior();assert(preset_cursor.Normal==2 and applied==1,'Queued layout was not applied in behavior phase')
combo_requests={['Cart type']=2};draw()
assert(pawn_seat_physics.menu.category==2 and applied==1,'Editing another cart applied it to current cart')
combo_requests={['Cart type']=1};draw();combo_requests={}
button_requests={['Delete Preset###del_Normal2']=true};draw()
button_requests={['Confirm Delete###conf_Normal2']=true};draw()
behavior()
assert(#options.Presets.Normal==1 and preset_cursor.Normal==1 and saved>0,'Delete left invalid cursor')
button_requests={};draw()
local current=preset('Custom current')
current.teleportPlayer=true;current.player.x=8;current.pawns[9].x=99;current.driver.x=9
options.Presets.Normal[2]=current;combo_requests={['Active layout']=2};draw();behavior();combo_requests={}
button_requests={['+ Add New Preset (Max 15)###add_preset_Normal']=true};draw();button_requests={}
local copied=options.Presets.Normal[3]
assert(copied.teleportPlayer and copied.player.x==8 and copied.pawns[9].x==99 and copied.driver.x==9,'Add did not copy current layout')
assert(copied.player~=current.player and copied.pawns[9]~=current.pawns[9] and copied.driver~=current.driver,'Add shares editable tables')
assert(copied.driver_builtin_id==nil,'Custom copy retained built-in reset identity')
draw()
local busy,driver_draws=false,0
driving_bus.driver={draw_ui=function() end,player_is_driver=function() return busy end,
    draw_player=function() driver_draws=driver_draws+1 end}
draw();assert(last_player_mode==2 and driver_draws==0,'Non-driver did not display passenger editor')
busy=true;draw();assert(last_player_mode==1 and driver_draws==1,'Driver entry did not automatically select driver parameters')
combo_requests={['Player seat']=2};draw();combo_requests={};draw()
assert(last_player_mode==2,'Manual editor selection was overwritten every frame')
busy=false;draw();assert(last_player_mode==2,'Leaving driver did not automatically select passenger parameters')
print('PASS: dropdown family/layout editing, apply only current cart, single editor, delete cursor, balanced UI and three-column keybinds')
