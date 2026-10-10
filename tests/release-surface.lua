-- A release must not expose the old mutation/recording bridge, even when
-- explicit runtime evidence is enabled for the independent diagnostics module.
assert(_G.OJR_EnableRuntimeDiagnostics==true,'Fixture must exercise diagnostics-enabled load')
assert(rawget(_G,'LMD_DriverDebug')==nil,'Legacy driver test bridge is still published')
assert(rawget(_G,'LMD_CartFrontProbe')==nil,'Obsolete cart-front probe is still published')
assert(rawget(_G,'LMD_PositionProbe')==nil,'Obsolete position probe is still published')
for _,name in ipairs({'forceSitDown','InterractSeatForce','onWarp','restoreCoord'}) do
    assert(not hooks[name],'Legacy observation-only hook remains: '..name)
end
for _,name in ipairs({'test_exit','test_native_exit','finish_native_exit',
    'test_interaction_cleanup','test_driver_passenger','combat_set','teleport_driver',
    'road_control','pawn_trace_control','seat_motion_command','start','stop','save'}) do
    assert(driver_runtime[name]==nil,'Legacy test/recorder remains reachable: '..name)
end
assert(type(driver_runtime.native_seat_command)=='function'
    and type(driver_runtime.native_pawns_exit)=='function'
    and type(driver_runtime.native_driver_relocate)=='function'
    and type(driver_runtime.native_visual_restore)=='function',
    'Release cleanup removed a production driver path')
assert(#errors==0,table.concat(errors,'\n'))
print('PASS: release has no legacy test bridges/recorders/observer hooks; production driver paths remain')
