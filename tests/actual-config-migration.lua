-- EXPECTATIONS --
local M=unified_presets
local imported={Normal=0,Rainy=0,Wealthy=0}
for _,p in ipairs(LMD_TEST_CONFIG.presets) do if not p.native_default then imported[p.family]=imported[p.family]+1 end end
for family,count in pairs(expected_counts) do
    local list=M.options.Presets[family]
    assert(#list==count+imported[family],'Actual migration count mismatch '..family)
    for i=1,count do
        local prior=original_presets[family][i]
        for n,s in ipairs(prior.pawns) do
            for _,axis in ipairs({'x','y','z','lookX','lookZ'}) do
                assert(list[i].pawns[n][axis]==s[axis],'OJR tuned seat changed during migration')
            end
        end
    end
end
for _,old in ipairs(LMD_TEST_CONFIG.presets) do
    if not old.native_default then
        local found
        for _,p in ipairs(M.options.Presets[old.family]) do if p.name==old.name..' (driver import)' then found=p;break end end
        assert(found,'Actual custom LMD layout missing '..old.name)
        for i,s in ipairs(old.slots) do
            local target=i==1 and found.driver or found.pawns[i-1]
            for _,axis in ipairs({'x','y','z'}) do assert(math.abs(target[axis]-s[axis])<1e-6,'LMD tuned seat changed') end
        end
    end
end
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: actual legacy configuration migration retained every OJR/LMD layout and tuned seat; no startup errors')
