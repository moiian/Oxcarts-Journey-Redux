local options={Presets={}}
local saved,saves=nil,0
local function is_key_valid() return false end
local function rebuild_input_watchlist() end
local json={dump_file=function(path,data)
    assert(path=='OxcartsJourneyRedux.json')
    saved=data;saves=saves+1
end}

-- PRESET IMPLEMENTATION --
-- SAVE IMPLEMENTATION --

local function legacy(name,flag)
    return {name=name,enabled=false,teleportPlayer=true,custom='keep',
        player={x=1.2,y=2.3,z=-3.4,lookX=-0.5,lookZ=0.7,anim='Wait',
            freezeFsm=flag,useOxAnchor=flag,randomIdle=true,useDirectMotion=true,bankID=7,motionID=9},
        pawns={{x=4,y=5,z=6,anim='LivSitChairBook01',freezeFsm=flag,useOxAnchor=flag,
            randomIdle=true,useDirectMotion=true,bankID=11,motionID=13},{freezeFsm=false,useOxAnchor=false}}}
end
local function check_preset(preset)
    assert(preset.player.freezeFsm==nil and preset.player.useOxAnchor==nil)
    for _,slot in ipairs(preset.pawns) do
        assert(slot.freezeFsm==nil and slot.useOxAnchor==nil,'Removed pawn fields survived normalization')
    end
end
local p=legacy('User layout',true)
options.Presets={Normal={p},Rainy={legacy('Rain custom',false)}}
normalize_presets()
assert(options.Presets.Normal[1]==p and p.name=='User layout' and p.enabled==true and p.custom=='keep')
assert(p.player.x==1.2 and p.player.y==2.3 and p.player.z==-3.4 and p.player.lookX==-0.5 and p.player.lookZ==0.7)
assert(p.teleportPlayer and p.player.randomIdle and p.player.useDirectMotion and p.player.bankID==7 and p.player.motionID==9)
assert(p.pawns[1].x==4 and p.pawns[1].anim=='LivSitChairBook01' and p.pawns[1].motionID==13)
assert(#p.pawns==9 and #options.Presets.Wealthy>0,'Missing seat or family defaults lost')
for _,family in pairs(options.Presets) do for _,preset in ipairs(family) do check_preset(preset) end end
persist_options()
assert(saves==1 and saved.Presets.Normal[1]==p)
check_preset(saved.Presets.Normal[1])
normalize_presets();check_preset(p)

local old=legacy('Flat legacy',true)
old.pawns[9]={x=7,y=8,z=9,anim='LivSitPose',lookX=-1,lookZ=0,randomIdle=true}
options.Presets={old}
normalize_presets()
assert(options.Presets.Normal[1]==old and old.name=='Flat legacy','Flat legacy preset was replaced')
check_preset(old)
assert(old.pawns[9].x==7 and old.pawns[9].anim=='LivSitPose','Existing extended seat overwritten')

local cat='Normal'
local preset=old
-- ADD PRESET IMPLEMENTATION --
local copy=options.Presets.Normal[2]
assert(copy and copy.player~=old.player and copy.pawns[1]~=old.pawns[1],'New preset shares editable seats')
assert(copy.player.x==old.player.x and copy.pawns[1].motionID==old.pawns[1].motionID)
assert(#copy.pawns==9 and copy.pawns[9]~=old.pawns[9] and copy.pawns[9].x==7,'Extra seats not independently cloned')
check_preset(copy)

local labels,previous_label,same_line={},nil,false
local function field(label,value)
    if label=='Use Direct Motion' then assert(previous_label=='Random Idle' and same_line,'Random Idle must be directly left of Use Direct Motion') end
    labels[label]=true;previous_label=label;same_line=false;return false,value
end
local tooltip,hovered=nil,false
local imgui={tree_node=function() return true end,tree_pop=function() end,
    text=function(label) labels[label]=true end,is_item_hovered=function() return hovered end,
    set_tooltip=function(value) tooltip=value end,
    checkbox=field,drag_float=field,drag_int=field,input_text=field,same_line=function() same_line=true end}
-- EDITOR IMPLEMENTATION --
draw_seat_editor('Player',old.player,true)
assert(not labels['Random Idle'] and not labels['Use Direct Motion'] and not labels['Bank ID'] and not labels['Animation'],
    'Player editor still exposes animation controls')
old.pawns[1].useDirectMotion=false
draw_seat_editor('Pawn',old.pawns[1])
assert(not labels['Freeze AI'] and not labels['Use Ox Anchor'])
assert(labels['Random Idle'] and labels['Use Direct Motion'] and labels['X (Left/Right)'])
assert(labels['Lock Height'] and labels['[?]'] and not labels['Pelvis height compensation'])
assert(tooltip==nil,'Help appeared without hover')
hovered=true;draw_seat_editor('Pawn',old.pawns[1])
assert(tooltip=='Disabled by default. Enable only if some seated animations cause vertical height jitter.')
print('PASS: grouped/flat legacy presets, removed flags, custom values, save, new preset copy and seat editor')
