-- Passenger-only labels. Keep native colors and restore only our own writes.
local M={}
local paths={
    ["Y (Triangle)"]="PNL_top/PNL_L02/PNL_txt",["A (X)"]="PNL_top/PNL_R03/PNL_txt",
    ["X (Square)"]="PNL_top/PNL_L03/PNL_txt",["B (Circle)"]="PNL_top/PNL_R02/PNL_txt",
    LT="PNL_top/PNL_L00/PNL_txt",RT="PNL_top/PNL_R00/PNL_txt",
    LB="PNL_top/PNL_L01/PNL_txt",RB="PNL_top/PNL_R01/PNL_txt",
}
function M.new()
    local self={slots={}}
    function self:restore_slot(slot)
        pcall(function()
            if slot.text:get_Message()==slot.written then slot.text:set_Message(slot.original) end
        end)
        if slot.play~=nil then pcall(function()
            if slot.panel:get_PlayState()=="DEFAULT" then slot.panel:set_PlayState(slot.play) end
        end) end
    end
    function self:restore()
        for _,slot in pairs(self.slots) do self:restore_slot(slot) end
        self.slots={};self.root=nil
    end
    function self:update(root,labels,resolve)
        if not root then self:restore();return end
        local identity=root:get_address()
        if self.root and self.root~=identity then self:restore() end
        self.root=identity
        for key,slot in pairs(self.slots) do
            if not labels[key] then self:restore_slot(slot);self.slots[key]=nil end
        end
        for key,label in pairs(labels) do
            local path=paths[key]
            if path then pcall(function()
                local panel=resolve(root,path)
                local text=panel and panel:get_Child()
                if not text then return end
                local slot=self.slots[key]
                if slot and slot.text:get_address()~=text:get_address() then
                    self:restore_slot(slot);self.slots[key]=nil;slot=nil
                end
                local current=text:get_Message()
                if not slot then
                    local ok,play=pcall(function() return panel:get_PlayState() end)
                    slot={panel=panel,text=text,original=current,play=ok and play or nil}
                    self.slots[key]=slot
                end
                if current~=label then text:set_Message(label) end
                slot.written=label
                if slot.play~=nil and panel:get_PlayState()~="DEFAULT" then panel:set_PlayState("DEFAULT") end
            end) end
        end
    end
    return self
end
return M
