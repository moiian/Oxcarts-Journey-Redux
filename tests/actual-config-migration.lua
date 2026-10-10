local M=unified_presets
local removed=0
for family,prior_list in pairs(original_presets) do
    local list=M.options.Presets[family]
    local kept=0
    for _,prior in ipairs(prior_list) do
        if prior.driver_builtin_id~=nil or (prior.name or ''):find('(driver import',1,true) then
            removed=removed+1
        else
            kept=kept+1
            local p=assert(list[kept],'Lost retained preset')
            assert(p.enabled and p.name:match('^%['..kept..'%] '),'Indexed enabled name missing')
            assert(p.teleportPlayer==prior.teleportPlayer and p.skipPassenger==(prior.skipPassenger==true),'Changed player switches')
            for _,key in ipairs({'player','driver'}) do
                if prior[key] then
                    for _,axis in ipairs({'x','y','z'}) do
                        assert(p[key][axis]==prior[key][axis],'Retained player coordinates changed')
                    end
                end
            end
            for n,s in ipairs(prior.pawns) do
                for _,axis in ipairs({'x','y','z','lookX','lookZ'}) do
                    assert(p.pawns[n][axis]==s[axis],'Retained companion coordinates changed')
                end
            end
        end
    end
    assert(#list==kept,'Wrong preset removal count')
    for _,p in ipairs(list) do assert(not p.driver_builtin_id and not p.name:find('(driver import',1,true)) end
end
assert(M.options.UnifiedVersion==2 and M.removed_imports==removed)
local factory_count=0
for _,list in pairs(M.factories) do factory_count=factory_count+#list end
assert(factory_count==7,'Expected original 4 Normal / 2 Rainy / 1 Luxury built-ins')
M.restore_builtins()
for family,sources in pairs(M.factories) do
    for i,source in ipairs(sources) do
        local p=M.options.Presets[family][i]
        assert(p.builtin_id==source.builtin_id and p.player.x==source.player.x and p.driver.x==source.driver.x
            and p.driver_camera.fov==source.driver_camera.fov and p.pawns[1].x==source.pawns[1].x,
            'Full builtin restore failed')
    end
end
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: actual config removes '..removed..' driver imports; preserves retained coordinates; seven original built-ins restore both player modes and companions')
