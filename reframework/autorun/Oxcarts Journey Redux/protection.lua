-- Body and part arguments are GameObjects; ox/cow arguments are Characters.
local M={part_ids={sm80_074=true,sm80_051=true,sm80_052=true}}
function M.valid(o)
    local ok,value=pcall(function() return o and o:get_Valid() end)
    return ok and value==true
end
function M.same(a,b)
    return a~=nil and b~=nil and a:get_address()==b:get_address()
end
-- Match the current logical cart and its children, never a global NPC list.
function M.destroy_target(container,scope)
    if not container or not scope or scope.riding~=true or scope.loading~=false
        or scope.fast_travel~=0 then return false end
    local seen={}
    local function child_matches(root,depth)
        if not root or depth>3 then return false end
        local address=root:get_address()
        if seen[address] then return false end;seen[address]=true
        if M.same(container,root) then return true end
        local children=root._Children
        if children then
            for i=0,math.min(children:get_Count(),32)-1 do
                if child_matches(children[i],depth+1) then return true end
            end
        end
        return false
    end
    if child_matches(scope.container,0) then return true end
    local current=container
    for _=1,4 do
        if not current then break end
        if M.same(current,scope.container) then return true end
        local common=current._CommonInfo
        local id=common and common._ObjectID and common._ObjectID._SelectedCharacterID
        if id~=nil and (tostring(id)==tostring(scope.ox_id)
            or (scope.driver_id~=nil and tostring(id)==tostring(scope.driver_id))) then return true end
        current=current['<ParentContainer>k__BackingField']
    end
    return false
end
function M.install_destroy_guard(resolve,report)
    local definition=sdk.find_type_definition('app.GenerateManager')
    local signature='requestDestroy(app.GenerateInfo.GenerateInfoContainer, System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Boolean)'
    local method=definition and definition:get_method(signature)
    if not method then if report then report('destroy-hook','destroy guard unavailable') end;return false end
    sdk.hook(method,function(args)
        local storage=thread.get_hook_storage()
        storage.ojr_destroy_blocked=false
        local ok,blocked=pcall(function()
            return M.destroy_target(sdk.to_managed_object(args[3]),resolve())
        end)
        if ok and blocked then
            storage.ojr_destroy_blocked=true
            if report then report('destroy-blocked','blocked current occupied cart destruction') end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end,function(ret)
        if thread.get_hook_storage().ojr_destroy_blocked then return sdk.to_ptr(0) end
        return ret
    end)
    return true
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
        if writer then writer('[OJR Protection] '..message,key) end
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
