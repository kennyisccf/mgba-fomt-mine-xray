$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$referenceRoot = Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8'

if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The .NET Framework C# compiler was not found.'
}

& $compiler /nologo /target:winexe /optimize+ /platform:anycpu `
    /out:"$projectRoot\OpenGbaWithLatestSave.exe" `
    "$projectRoot\OpenGbaWithLatestSave.cs"
if ($LASTEXITCODE -ne 0) { throw 'OpenGbaWithLatestSave build failed.' }

& $compiler /nologo /target:winexe /optimize+ /platform:anycpu `
    /out:"$projectRoot\MineXRayHDOverlay.exe" `
    /reference:"$referenceRoot\WindowsBase.dll" `
    /reference:"$referenceRoot\PresentationCore.dll" `
    /reference:"$referenceRoot\PresentationFramework.dll" `
    /reference:"$referenceRoot\System.Xaml.dll" `
    "$projectRoot\MineXRayHDOverlay.cs"
if ($LASTEXITCODE -ne 0) { throw 'MineXRayHDOverlay build failed.' }

Write-Host 'Built MineXRayHDOverlay.exe and OpenGbaWithLatestSave.exe.'

