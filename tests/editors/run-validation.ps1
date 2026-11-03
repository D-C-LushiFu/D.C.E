$ErrorActionPreference = 'Stop'
# Isolate the pure validator from source/import.hx and its native game dependencies.
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$testRoot = Join-Path $env:TEMP ('dce-editor-validation-' + [Guid]::NewGuid().ToString('N'))
$packageDir = Join-Path $testRoot 'developer/editors'
New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'source/developer/editors/EditorInputValidation.hx') -Destination $packageDir
& haxe -cp $testRoot -cp $PSScriptRoot -main EditorInputValidationTest --interp
if ($LASTEXITCODE -ne 0) { throw 'Editor validation failed' }
