param([Parameter(Mandatory=$true)][string]$ConfigDirectory)
$ErrorActionPreference='Stop'
function ConvertTo-Lua($value) {
    if ($null -eq $value) { return 'nil' }
    if ($value -is [bool]) { return $value.ToString().ToLowerInvariant() }
    if ($value -is [string]) { return (ConvertTo-Json -InputObject $value -Compress) }
    if ($value -is [System.Collections.IDictionary]) {
        $fields=foreach($key in $value.Keys) { '['+(ConvertTo-Lua ([string]$key))+']='+(ConvertTo-Lua $value[$key]) }
        return '{'+($fields -join ',')+'}'
    }
    if ($value -is [System.Collections.IEnumerable]) {
        $fields=foreach($item in $value) { ConvertTo-Lua $item }
        return '{'+($fields -join ',')+'}'
    }
    return ([Convert]::ToString($value,[Globalization.CultureInfo]::InvariantCulture))
}
$ojr=Get-Content -Raw -LiteralPath (Join-Path $ConfigDirectory 'OxcartsJourneyRedux.json') | ConvertFrom-Json -AsHashtable
$lmd=Get-Content -Raw -LiteralPath (Join-Path $ConfigDirectory 'LetMeDriveOxcart.json') | ConvertFrom-Json -AsHashtable
$prefix='OJR_TEST_CONFIG='+(ConvertTo-Lua $ojr)+"`nLMD_TEST_CONFIG="+(ConvertTo-Lua $lmd)+"`n"
$prefix+='local original_unified='+(ConvertTo-Lua ($ojr.UnifiedVersion -ge 1))+"`n"
$prefix+='local expected_counts={};for k,v in pairs(OJR_TEST_CONFIG.Presets) do expected_counts[k]=#v end' + "`n"
$prefix+='local original_presets='+(ConvertTo-Lua $ojr.Presets)+"`n"
$project=Split-Path -Parent $PSScriptRoot
$source=$prefix+(Get-Content -Raw (Join-Path $PSScriptRoot 'unified-runtime-mock.lua'))+"`n"
$source+=(Get-Content -Raw (Join-Path $PSScriptRoot 'unified-runtime-setup.lua'))+"`n"
$source+=(Get-Content -Raw (Join-Path $project 'reframework/autorun/Oxcarts Journey Redux/driver.lua'))+"`n"
$source+=(Get-Content -Raw (Join-Path $PSScriptRoot 'actual-config-migration.lua'))
Push-Location $project
try {
    $source | python -X utf8 (Join-Path $PSScriptRoot 'lua_check.py') --execute
    if ($LASTEXITCODE -ne 0) { throw 'Actual configuration migration failed' }
} finally { Pop-Location }
