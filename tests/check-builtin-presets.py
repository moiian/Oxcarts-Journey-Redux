"""Check embedded defaults against the imported preset-only source fixture."""
import json
from pathlib import Path
import subprocess
import sys

project = Path(__file__).resolve().parent.parent
expected = json.loads((project / 'tests/fixtures/aelinore-builtins.json').read_text(encoding='utf-8-sig'))

def literal(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return json.dumps(value, allow_nan=False)
    if isinstance(value, list):
        return '{' + ','.join(literal(item) for item in value) + '}'
    if isinstance(value, dict):
        return '{' + ','.join('[' + literal(key) + ']=' + literal(item) for key, item in value.items()) + '}'
    raise TypeError(type(value))

parts = [(project / 'tests' / name).read_text(encoding='utf-8') for name in
         ('unified-runtime-mock.lua', 'unified-runtime-setup.lua')]
parts.append((project / 'reframework/autorun/Oxcarts Journey Redux/driver.lua').read_text(encoding='utf-8'))
parts.append('local expected=' + literal(expected))
parts.append(r'''
local M=_G.OJR_UnifiedPresets
local function equal(actual,want,path)
    assert(type(actual)==type(want),'Builtin type mismatch: '..path)
    if type(want)~='table' then
        assert(actual==want,'Builtin value mismatch: '..path)
        return
    end
    for k,v in pairs(want) do equal(actual[k],v,path..'.'..tostring(k)) end
    for k in pairs(actual) do assert(want[k]~=nil,'Unexpected builtin field: '..path..'.'..tostring(k)) end
end
for _,family in ipairs({'Normal','Rainy','Wealthy'}) do
    equal(M.factories[family],expected[family],family..'.factory')
    equal(M.options.Presets[family],expected[family],family..'.fresh-install')
end
local edited=M.options.Presets.Normal[1]
edited.pawns[1].x=123;edited.driver.x=5;edited.passenger_camera.fov=100
local custom={name='User-added layout',enabled=true,player={},pawns={},driver={x=2}}
M.options.Presets.Normal[#M.options.Presets.Normal+1]=custom
table.remove(M.options.Presets.Normal,2)
M.attach(M.settings,{})
assert(edited.pawns[1].x==123 and edited.driver.x==5 and edited.passenger_camera.fov==100,
    'Updating builtins overwrote existing tuned values')
assert(#M.options.Presets.Normal==4 and M.options.Presets.Normal[4]==custom,
    'Updating builtins recreated a deleted layout or lost a user layout')
M.restore_builtins()
for _,family in ipairs({'Normal','Rainy','Wealthy'}) do
    for i,preset in ipairs(expected[family]) do
        equal(M.options.Presets[family][i],preset,family..'.restored.'..i)
    end
end
assert(#M.options.Presets.Normal==5 and M.options.Presets.Normal[5]==custom and custom.driver.x==2,
    'Restoring builtins modified or discarded a user-created layout')
assert(M.options.Presets.Normal[1]==edited,'Restore discarded an existing builtin object identity')
print('PASS: all imported builtin fields, fresh install, existing tuning, deleted builtin restore and custom layout preservation')
''')
result = subprocess.run([sys.executable, '-X', 'utf8', str(project / 'tests/lua_check.py'), '--execute'],
                        input='\n'.join(parts), text=True, cwd=project)
raise SystemExit(result.returncode)
