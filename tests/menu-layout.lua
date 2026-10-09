local function preset(name)
    return {name=name,enabled=true,teleportPlayer=false,player={},pawns={{},{},{}}}
end
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
local function draw_seat_editor(label) edited[#edited+1]=label end
local input_bindings={imgui_rebind_button=function(_,v) return false,v end}
local callback,tree_depth,id_depth,table_depth=nil,0,0,0
local combo_requests,button_requests={},{}
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
function imgui.checkbox(label,value) assert(label~='Freeze companion FSM');return false,value end
function imgui.input_text(_,value) return false,value end
function imgui.button(label) return button_requests[label]==true end
function imgui.combo(label,index,names)
    assert(label=='Cart type' or label=='Active layout')
    assert(#names>0)
    if combo_requests[label] then return true,combo_requests[label] end
    return false,index
end
local re={on_draw_ui=function(fn) callback=fn end}
-- UI IMPLEMENTATION --
local function draw()
    callback()
    assert(tree_depth==0 and id_depth==0 and table_depth==0,'Unbalanced menu scopes')
end
draw();assert(tables==2 and headers.Action and headers.Gamepad and headers.Keyboard,'Keybind tables missing')
assert(#edited==3,'Menu displayed multiple preset editors')
combo_requests={['Active layout']=2};draw()
assert(preset_cursor.Normal==2 and applied==1,'Active dropdown did not apply selected layout')
combo_requests={['Cart type']=2};draw()
assert(pawn_seat_physics.menu.category==2 and applied==1,'Editing another cart applied it to current cart')
combo_requests={['Cart type']=1};draw();combo_requests={}
button_requests={['Delete Preset###del_Normal2']=true};draw()
button_requests={['Confirm Delete###conf_Normal2']=true};draw()
assert(#options.Presets.Normal==1 and preset_cursor.Normal==1 and saved>0,'Delete left invalid cursor')
button_requests={};draw()
print('PASS: dropdown family/layout editing, apply only current cart, single editor, delete cursor, balanced UI and three-column keybinds')
