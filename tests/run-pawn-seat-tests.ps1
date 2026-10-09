param([string]$LuaChecker = 'D:\_Project\Oxcart Mod\Let me drive oxcart\tests\lua_check.py')
$ErrorActionPreference = 'Stop'
$source = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'reframework/autorun/Oxcarts Journey Redux.lua') -Raw
$source | python -X utf8 $LuaChecker
if ($LASTEXITCODE -ne 0) { throw 'OJR syntax validation failed' }
$physicsStart = $source.IndexOf('local pawn_seat_physics = {}')
$physicsEnd = $source.IndexOf('-- Detach every bound character', $physicsStart)
$poseStart = $source.IndexOf('local function enforce_seat_transforms(')
$poseEnd = $source.IndexOf('local journey_handoff =', $poseStart)
if ($physicsStart -lt 0 -or $physicsEnd -lt 0 -or $poseStart -lt 0 -or $poseEnd -lt 0) { throw 'Test source boundaries not found' }
$implementation = $source.Substring($physicsStart,$physicsEnd-$physicsStart) + "`n" + $source.Substring($poseStart,$poseEnd-$poseStart)
$fixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pawn-seat-physics.lua') -Raw
$fixture.Replace('-- IMPLEMENTATION --',$implementation) | python -X utf8 $LuaChecker --execute
if ($LASTEXITCODE -ne 0) { throw 'OJR pawn seat physics tests failed' }
$animationStart = $source.IndexOf('local function start_seated_animation(')
$animationEnd = $source.IndexOf('-- Release variants', $animationStart)
$bindStart = $source.IndexOf('local function bind_pawns_to_seats(')
$bindEnd = $source.IndexOf('local action_bindings =', $bindStart)
$detachStart = $source.IndexOf('-- Detach every bound character', $physicsEnd)
$switchImplementation = $source.Substring($physicsStart,$physicsEnd-$physicsStart) + "`n" + $source.Substring($detachStart,$animationEnd-$detachStart) + "`n" + $source.Substring($bindStart,$bindEnd-$bindStart)
$switchFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'preset-switch.lua') -Raw
$actionHookStart = $source.IndexOf('sdk.hook(' + "`n" + '    sdk.find_type_definition("app.ActionManager")')
if ($actionHookStart -lt 0) { $actionHookStart = $source.IndexOf('sdk.hook(' + "`r`n" + '    sdk.find_type_definition("app.ActionManager")') }
$actionHookEnd = $source.IndexOf('sdk.hook(', $actionHookStart + 10)
if ($actionHookStart -lt 0 -or $actionHookEnd -lt 0) { throw 'Action hook boundaries not found' }
$switchFixture.Replace('-- IMPLEMENTATION --',$switchImplementation).Replace('-- ACTION HOOK --',$source.Substring($actionHookStart,$actionHookEnd-$actionHookStart)) | python -X utf8 $LuaChecker --execute
if ($LASTEXITCODE -ne 0) { throw 'OJR preset switching tests failed' }
$bodyStart = $source.IndexOf('local function player_cart_body_distance(')
$bodyEnd = $source.IndexOf('local function update_cart_normal_guard(', $bodyStart)
$releaseStart = $source.IndexOf('    -- Release followers beyond 8 units')
$releaseEnd = $source.IndexOf('    -- Damage/rollover', $releaseStart)
if ($bodyStart -lt 0 -or $bodyEnd -lt 0 -or $releaseStart -lt 0 -or $releaseEnd -lt 0) { throw 'Distance test boundaries not found' }
$distanceFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'pawn-release-distance.lua') -Raw
$distanceFixture.Replace('-- BODY DISTANCE --',$source.Substring($bodyStart,$bodyEnd-$bodyStart)).Replace('-- RELEASE CHECK --',$source.Substring($releaseStart,$releaseEnd-$releaseStart)) | python -X utf8 $LuaChecker --execute
if ($LASTEXITCODE -ne 0) { throw 'OJR pawn release distance tests failed' }

# Obsolete fields may only occur in the loader cleanup, never in runtime or UI.
if ($source -match 'set_fsm_enabled|get_character_fsm|pending_ai_lock|retry_release|Freeze AI|Use Ox Anchor|Pose lock \(FSM') { throw 'Obsolete FSM/anchor control remains' }
$presetStart = $source.IndexOf('local function get_default_normal_presets(')
$presetEnd = $source.IndexOf('local fixed_cart_parameters =', $presetStart)
$saveStart = $source.IndexOf('local function persist_options(')
$saveEnd = $source.IndexOf('local function restore_default_key_bindings(', $saveStart)
$copyStart = $source.IndexOf('                            local src = options.Presets[cat][1]')
$copyEnd = $source.IndexOf('                            persist_options()', $copyStart)
$editorStart = $source.IndexOf('local function draw_seat_editor(')
$editorEnd = $source.IndexOf('re.on_draw_ui(', $editorStart)
if (@($presetStart,$presetEnd,$saveStart,$saveEnd,$copyStart,$copyEnd,$editorStart,$editorEnd) -contains -1) { throw 'Preset compatibility test boundaries not found' }
$compatibilityFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'preset-compatibility.lua') -Raw
$compatibilityFixture.Replace('-- PRESET IMPLEMENTATION --',$source.Substring($presetStart,$presetEnd-$presetStart)).Replace('-- SAVE IMPLEMENTATION --',$source.Substring($saveStart,$saveEnd-$saveStart)).Replace('-- ADD PRESET IMPLEMENTATION --',$source.Substring($copyStart,$copyEnd-$copyStart)).Replace('-- EDITOR IMPLEMENTATION --',$source.Substring($editorStart,$editorEnd-$editorStart)) | python -X utf8 $LuaChecker --execute
if ($LASTEXITCODE -ne 0) { throw 'OJR legacy preset compatibility tests failed' }
$collectorStart = $source.IndexOf('local function collect_party_pawns(')
$collectorEnd = $source.IndexOf('-- Pawn root transforms', $collectorStart)
$releaseVariantStart = $source.IndexOf('-- Release variants')
$releaseVariantEnd = $source.IndexOf('-- Build the active bindings', $releaseVariantStart)
$intermediateStart = $source.IndexOf('local function release_pawns_at_intermediate_stop(')
$intermediateEnd = $source.IndexOf('local function check_intermediate_arrival(', $intermediateStart)
$companionFixture = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'companion-seats.lua') -Raw
$companionFixture.Replace('-- COLLECTOR --',$source.Substring($collectorStart,$collectorEnd-$collectorStart)).Replace('-- IMPLEMENTATION --',$switchImplementation).Replace('-- RELEASE VARIANTS --',$source.Substring($releaseVariantStart,$releaseVariantEnd-$releaseVariantStart)).Replace('-- INTERMEDIATE RELEASE --',$source.Substring($intermediateStart,$intermediateEnd-$intermediateStart)) | python -X utf8 $LuaChecker --execute
if ($LASTEXITCODE -ne 0) { throw 'OJR companion seats tests failed' }
