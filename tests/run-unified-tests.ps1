param([string]$LuaChecker=(Join-Path $PSScriptRoot 'lua_check.py'))
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$modules=Join-Path $project 'reframework/autorun/Oxcarts Journey Redux'
Get-ChildItem -LiteralPath $modules -Filter *.lua | ForEach-Object {
    Get-Content -Raw -LiteralPath $_.FullName | python -X utf8 $LuaChecker
    if ($LASTEXITCODE -ne 0) { throw "Syntax validation failed: $($_.Name)" }
}
& (Join-Path $PSScriptRoot 'run-pawn-seat-tests.ps1') -LuaChecker $LuaChecker
if ($LASTEXITCODE -ne 0) { throw 'Shared companion regressions failed' }
$mock=Get-Content -Raw (Join-Path $PSScriptRoot 'unified-runtime-mock.lua')
$setup=Get-Content -Raw (Join-Path $PSScriptRoot 'unified-runtime-setup.lua')
$driver=Get-Content -Raw (Join-Path $modules 'driver.lua')
$assertions=Get-Content -Raw (Join-Path $PSScriptRoot 'unified-native-seats.lua')
Push-Location $project
try {
    Get-Content -Raw (Join-Path $PSScriptRoot 'runtime-evidence.lua') | python -X utf8 $LuaChecker --execute
    if ($LASTEXITCODE -ne 0) { throw 'Dedicated runtime evidence tests failed' }
    Get-Content -Raw (Join-Path $PSScriptRoot 'protection-recovery.lua') | python -X utf8 $LuaChecker --execute
    if ($LASTEXITCODE -ne 0) { throw 'Protection lifecycle / delayed pelvis regression failed' }
    Get-Content -Raw (Join-Path $PSScriptRoot 'runtime-policies.lua') | python -X utf8 $LuaChecker --execute
    if ($LASTEXITCODE -ne 0) { throw 'Independent movement/HUD/protection tests failed' }
    Get-Content -Raw (Join-Path $PSScriptRoot 'unified-presets.lua') | python -X utf8 $LuaChecker --execute
    if ($LASTEXITCODE -ne 0) { throw 'Unified preset tests failed' }
    ($mock+"`n"+$setup+"`n"+$driver+"`n"+$assertions) | python -X utf8 $LuaChecker --execute
    if ($LASTEXITCODE -ne 0) { throw 'Unified native integration tests failed' }
    $policyAssertions=Get-Content -Raw (Join-Path $PSScriptRoot 'unified-policy-integration.lua')
    ($mock+"`n"+$setup+"`n"+$driver+"`n"+$policyAssertions) | python -X utf8 $LuaChecker --execute
    if ($LASTEXITCODE -ne 0) { throw 'Unified policy integration tests failed' }
    $protectionAssertions=Get-Content -Raw (Join-Path $PSScriptRoot 'protection-runtime.lua')
    ($mock+"`n"+$setup+"`n"+$driver+"`n"+$protectionAssertions) | python -X utf8 $LuaChecker --execute
    if ($LASTEXITCODE -ne 0) { throw 'Native invincibility / actual cart parts integration failed' }
    $bootSetup=$setup.Substring(0,$setup.IndexOf('_G.OJR_UnifiedPresets='))
    $boot=$mock+"`n"+$bootSetup+"`n"+@'
dofile('reframework/autorun/Oxcarts Journey Redux.lua')
assert(_G.DD2_OxcartControl.driver and _G.DD2_OxcartControl.journey,'Root entry failed to load both modes')
assert(#registrations.LateUpdateBehavior==2,'Unexpected number of gameplay controllers')
dofile('reframework/autorun/Oxcarts Journey Redux.lua')
assert(#registrations.LateUpdateBehavior==2,'Duplicate root entry registered twice')
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: actual autorun entry loads sibling modules once, one menu and both callback owners')
'@
    $boot | python -X utf8 $LuaChecker --execute
    if ($LASTEXITCODE -ne 0) { throw 'Unified autorun startup failed' }
} finally { Pop-Location }
