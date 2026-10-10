-- Body and part arguments are GameObjects; ox/cow arguments are Characters.
local M={part_ids={sm80_074=true,sm80_051=true,sm80_052=true}}
function M.valid(o)
    local ok,value=pcall(function() return o and o:get_Valid() end)
    return ok and value==true
end
function M.same(a,b)
    return a~=nil and b~=nil and a:get_address()==b:get_address()
end
function M.cart_receiver(receiver,ox,body,cow,near,parts)
    if not near or not M.valid(receiver) then return false end
    if M.valid(body) and M.same(receiver,body) then return true end
    for _,target in pairs({ox=ox,cow=cow}) do
        if M.valid(target) and M.same(receiver,target:get_GameObject()) then return true end
    end
    for _,part in ipairs(parts or {}) do
        if M.valid(part.go) and M.same(receiver,part.go) then return true end
    end
    local name=receiver:get_Name() or ""
    local model=name:match("^([a-z][a-z]%d%d_%d%d%d)")
    if not M.part_ids[model] or not M.valid(body) then return false end
    return (receiver:get_Transform():get_Position()-body:get_Transform():get_Position()):length()<=12
end
function M.new(writer)
    local state={owned={},messages={}}
    function state:report(key,message,now)
        now=now or os.clock()
        if self.messages[key] and now-self.messages[key]<5 then return end
        self.messages[key]=now
        if writer then writer('[OJR Protection] '..message) end
    end
    function state:restore(id,item)
        local ok,err=pcall(function()
            if M.valid(item.controller) and item.controller:call('get_IsInvincible()')==true then
                item.controller:call('set_IsInvincible(System.Boolean)',item.previous)
            end
        end)
        self:report('restore:'..id,ok and ('restored '..item.label..' to '..tostring(item.previous))
            or ('restore failed '..item.label..': '..tostring(err)))
        if ok then self.owned[id]=nil end
    end
    function state:clear()
        for id,item in pairs(self.owned) do self:restore(id,item) end
        self.cart,self.next_at=nil,nil
    end
    function state:tick(targets,resolve,now)
        local seen={}
        for _,target in ipairs(targets or {}) do
            if M.valid(target.go) then
                local ok,err=pcall(function()
                    local controllers=resolve(target.go)
                    if #controllers==0 then self:report('missing:'..target.go:get_address(),
                        'no HitController: '..target.label,now) end
                    for _,controller in ipairs(controllers) do
                        if M.valid(controller) then
                            local id=controller:get_address()
                            seen[id]=true
                            local item=self.owned[id]
                            local current=controller:call('get_IsInvincible()')
                            assert(type(current)=='boolean','IsInvincible is not Boolean')
                            if not item then
                                item={controller=controller,previous=current,label=target.label}
                                self.owned[id]=item
                            end
                            if not current then
                                controller:call('set_IsInvincible(System.Boolean)',true)
                                if item.announced then self:report('renew:'..id,'native flag dropped; reapplied: '..target.label,now) end
                            end
                            assert(controller:call('get_IsInvincible()')==true,'IsInvincible readback failed')
                            if not item.announced then
                                local type_ok,typename=pcall(function() return controller:get_type_definition():get_full_name() end)
                                self:report('enable:'..id,'invincible readback=true: '..target.label..' controller='..tostring(id)
                                    ..' type='..tostring(type_ok and typename or 'unavailable')..' previous='..tostring(item.previous),now)
                                item.announced=true
                            end
                        end
                    end
                end)
                if not ok then self:report('error:'..target.go:get_address(),target.label..': '..tostring(err),now) end
            end
        end
        for id,item in pairs(self.owned) do if not seen[id] then self:restore(id,item) end end
    end
    return state
end
return M
