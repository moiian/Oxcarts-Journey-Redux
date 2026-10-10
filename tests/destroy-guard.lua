local m=assert(loadfile('reframework/autorun/Oxcarts Journey Redux/protection.lua'))()
local next_id=0
local function container(id)
    next_id=next_id+1
    local c={address=next_id,_CommonInfo={_ObjectID={_SelectedCharacterID=id}}}
    function c:get_address() return self.address end
    return c
end
local root,child,driver,other=container(10),container(11),container(20),container(30)
root._Children={[0]=child,get_Count=function() return 1 end}
local scope={riding=true,loading=false,fast_travel=0,container=root,ox_id=10,driver_id=20}
for _,c in ipairs({root,child,driver}) do assert(m.destroy_target(c,scope)) end
assert(not m.destroy_target(other,scope))
scope.driver_id=nil;assert(not m.destroy_target(driver,scope),'Expelled driver protected')
for _,case in ipairs({{'riding',false},{'loading',true},{'fast_travel',2}}) do
    local old=scope[case[1]];scope[case[1]]=case[2]
    assert(not m.destroy_target(root,scope));scope[case[1]]=old
end
scope.loading=nil;assert(not m.destroy_target(root,scope));scope.loading=false
assert(not m.destroy_target(nil,scope) and not m.destroy_target(root,nil))
local pre,post,store,fail
thread={get_hook_storage=function() return store end}
sdk={PreHookResult={SKIP_ORIGINAL='skip'},to_ptr=function(x) return x end,to_managed_object=function(x) return x end,
    find_type_definition=function() return {get_method=function(_,s) assert(s:find('requestDestroy',1,true));return s end} end,
    hook=function(_,a,b) pre,post=a,b end}
assert(m.install_destroy_guard(function() if fail then error('stale native object') end;return scope end))
store={};assert(pre({nil,nil,root})=='skip' and post(999)==0,'Blocked Boolean return is not false')
store={};assert(pre({nil,nil,other})==nil and post(999)==999)
fail=true;store={};assert(pre({nil,nil,root})==nil and post(999)==999,'Read failure blocked cleanup')
fail=false
store={};assert(pre({nil,nil,root})=='skip');local outer=store
store={};assert(pre({nil,nil,other})==nil and post(7)==7)
store=outer;assert(post(999)==0,'Nested invocation overwrote block state')
print('PASS: destruction scope, standing/loading/travel, expelled NPC, false return, failure-open and invocation isolation')
