#Requires -Version 5.1
<#
.SYNOPSIS
    Builds a self-contained Windows x64 Bunshin portable release.
.DESCRIPTION
    Requires the .NET 10 SDK on the build machine. The packaged app does not
    require a separately installed .NET runtime. Nothing is installed or published.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$')]
    [string] $Version = '0.1.0',
    [string] $OutputDirectory
)

$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'dist' }
$output = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$name = "bunshin-$Version-win-x64"
$archive = Join-Path $output "$name.zip"
$checksum = "$archive.sha256"
if ((Test-Path -LiteralPath $archive) -or (Test-Path -LiteralPath $checksum)) {
    throw "Release already exists: $archive. Choose a new version or output directory."
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('bunshin-publish-' + [guid]::NewGuid().ToString('N'))
$stage = Join-Path $work $name
try {
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    & dotnet publish (Join-Path $PSScriptRoot 'gui\Bunshin.Gui.csproj') `
        --configuration Release --runtime win-x64 --self-contained true `
        --output $stage --nologo "-p:Version=$Version" `
        -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true `
        -p:DebugType=None -p:DebugSymbols=false
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)." }
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'Bunshin.exe'))) {
        throw 'Publish did not produce Bunshin.exe.'
    }

    foreach ($file in @('bunshin.ps1', 'SendTo-Bunshin.ps1', 'Install-SendTo.ps1', 'README.md', 'CHANGELOG.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CONTRIBUTING.md', 'SECURITY.md')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $stage
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'docs') -Destination (Join-Path $stage 'docs') -Recurse
    $demo = Join-Path $stage 'demo\brag-output'
    New-Item -ItemType Directory -Path $demo -Force | Out-Null
    foreach ($file in @('brag.mp4', 'brag.jpg', 'README.md')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "demo\brag-output\$file") -Destination $demo
    }
    $qa = Join-Path $stage 'qa'
    New-Item -ItemType Directory -Path $qa -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'qa\GUI-RESULTS.md') -Destination $qa
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'gui\Branding') -Destination (Join-Path $stage 'Branding') -Recurse
    $fontNotices = Join-Path $stage 'ThirdPartyNotices\Fonts'
    New-Item -ItemType Directory -Path $fontNotices -Force | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'gui\Fonts') -File |
        Where-Object { $_.Extension -in '.txt', '.md' } |
        Copy-Item -Destination $fontNotices

    # Single-file publishing embeds the runtime, but its redistribution notices
    # still need to accompany the executable. Use the exact restored versions.
    $assets = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'gui\obj\project.assets.json') -Raw | ConvertFrom-Json
    $runtimePackages = $assets.project.frameworks.PSObject.Properties.Value.downloadDependencies |
        Where-Object { $_.name -in @('Microsoft.NETCore.App.Runtime.win-x64', 'Microsoft.WindowsDesktop.App.Runtime.win-x64') }
    foreach ($package in $runtimePackages) {
        $runtimeVersion = $package.version.Trim('[', ']').Split(',')[0].Trim()
        $relativePath = Join-Path $package.name.ToLowerInvariant() $runtimeVersion
        $packagePath = $assets.packageFolders.PSObject.Properties.Name |
            ForEach-Object { Join-Path $_ $relativePath } |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (!$packagePath) { throw "Runtime notices not found for $($package.name) $runtimeVersion" }
        $noticeDirectory = Join-Path $stage "ThirdPartyNotices\$($package.name)"
        New-Item -ItemType Directory -Path $noticeDirectory -Force | Out-Null
        Get-ChildItem -LiteralPath $packagePath -File |
            Where-Object { $_.Name -in @('LICENSE', 'LICENSE.TXT', 'THIRD-PARTY-NOTICES.TXT') } |
            Copy-Item -Destination $noticeDirectory
    }
    @{
        product = 'Bunshin'
        version = $Version
        platform = 'win-x64'
        builtUtc = [DateTime]::UtcNow.ToString('o')
        selfContained = $true
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stage 'release.json') -Encoding UTF8

    New-Item -ItemType Directory -Path $output -Force | Out-Null
    $temporaryArchive = Join-Path $work "$name.zip"
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $temporaryArchive -CompressionLevel Optimal
    $hash = (Get-FileHash -LiteralPath $temporaryArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    Copy-Item -LiteralPath $temporaryArchive -Destination $archive
    "$hash  $name.zip" | Set-Content -LiteralPath $checksum -Encoding ASCII
    Write-Host "Portable release: $archive"
    Write-Host "SHA-256: $hash"
} finally {
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
