[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RepositoryRoot,
    [string]$MetaEditor = 'C:\Program Files\MetaTrader 5\metaeditor64.exe',
    [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if (-not (Test-Path -LiteralPath $MetaEditor -PathType Leaf)) { throw 'Existing native MetaEditor is required. This script does not install MT5.' }
$gitHead = $null; $gitTree = $null; $gitDirty = $null
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitHead = (git -C $root rev-parse HEAD).Trim()
    $gitTree = (git -C $root show -s --format=%T HEAD).Trim()
    $gitDirty = @((git -C $root status --porcelain)).Count -gt 0
}
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root ('build-t1724-' + [Guid]::NewGuid().ToString('N')) }
if (Test-Path -LiteralPath $OutputDirectory) { throw 'OutputDirectory must be new to prevent stale artifact reuse.' }
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$out = (Resolve-Path -LiteralPath $OutputDirectory).Path
$stage = Join-Path $out 'stage'
New-Item -ItemType Directory -Path $stage | Out-Null
$utf16 = New-Object System.Text.UnicodeEncoding($false,$true)
$sourceManifest = @()
foreach ($dir in @('Experts','Include','Scripts')) {
    $source = Join-Path $root ('BlackDragon_v14\' + $dir)
    foreach ($file in (Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object { $_.Extension -in '.mq5','.mqh' })) {
        $relative = $file.FullName.Substring($source.Length).TrimStart([char]'\',[char]'/')
        $destination = Join-Path (Join-Path $stage $dir) $relative
        New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
        $text = [IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($destination,$text,$utf16)
        $sourceManifest += [ordered]@{
            path = ('BlackDragon_v14/' + $dir + '/' + $relative.Replace('\','/'))
            original_sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            staged_sha256 = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
}
$sourceManifest | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $out 'SOURCE_MANIFEST.json') -Encoding UTF8
$probe = Join-Path $stage 'Experts\T1724CompileProbe.mq5'
[IO.File]::WriteAllText($probe,"#property strict`r`nvoid OnTick(){}`r`n",$utf16)
function Compile-ExactSource([string]$SourcePath,[string]$Name) {
    $ex5 = [IO.Path]::ChangeExtension($SourcePath,'.ex5')
    $log = Join-Path $out ($Name + '-compile.log')
    if ((Test-Path $ex5) -or (Test-Path $log)) { throw "Stale output at $Name" }
    $process = Start-Process -FilePath $MetaEditor -ArgumentList "/compile:`"$SourcePath`" /inc:`"$stage`" /log:`"$log`"" -PassThru
    if (-not $process.WaitForExit(300000)) { $process.Kill(); throw "MetaEditor timeout: $Name" }
    if (-not (Test-Path $log)) { throw "Missing compiler log: $Name" }
    $text = [IO.File]::ReadAllText($log,[Text.Encoding]::Unicode)
    if ($text -notmatch '0 errors?,\s*0 warnings?' -or $text -match ' : (error|warning) ' -or -not (Test-Path $ex5)) { throw "Compile gate failed: $Name; inspect $log" }
    if ((Get-Item $ex5).Length -le 0) { throw "Empty EX5: $Name" }
    Copy-Item -LiteralPath $ex5 -Destination (Join-Path $out ($Name+'.ex5'))
    return [ordered]@{name=$Name; sha256=(Get-FileHash $ex5 -Algorithm SHA256).Hash.ToLowerInvariant(); bytes=(Get-Item $ex5).Length; log=(Split-Path $log -Leaf)}
}
$artifacts = @()
$artifacts += Compile-ExactSource $probe 'T1724CompileProbe'
$tests = Get-ChildItem (Join-Path $stage 'Scripts\BlackDragon\Tests') -Filter 'Run*.mq5' | Sort-Object Name
if ($tests.Count -ne 33) { throw "Expected 33 native test sources; found $($tests.Count). Update the enrolled contract before building." }
foreach ($test in $tests) { $artifacts += Compile-ExactSource $test.FullName $test.BaseName }
$artifacts += Compile-ExactSource (Join-Path $stage 'Experts\BlackDragon\BlackDragon.mq5') 'BlackDragon'
foreach ($record in $sourceManifest) {
    $current = (Get-FileHash -LiteralPath (Join-Path $root $record.path) -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($current -ne $record.original_sha256) { throw "Source changed during compilation: $($record.path)" }
}
$manifest = [ordered]@{
    schema='bd-native-build-candidate/1.0'; created_utc=[DateTime]::UtcNow.ToString('o')
    repository='hoaithivo0511-eng/BD-ea-remake'; head=$gitHead; committed_tree=$gitTree; dirty=$gitDirty
    source_manifest_sha256=(Get-FileHash (Join-Path $out 'SOURCE_MANIFEST.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    backend='windows_native_metaeditor'; metaeditor_version=(Get-Item $MetaEditor).VersionInfo.FileVersion
    metaeditor_sha256=(Get-FileHash $MetaEditor -Algorithm SHA256).Hash.ToLowerInvariant()
    staging_transform='UTF8 source to UTF16LE BOM'; artifacts=$artifacts
    native_compile='PASS'; native_tests='NOT_RUN'; strategy_tester='NOT_RUN'; restart_recovery='NOT_RUN'
    release_eligible=$false; forward_eligible=$false; live_eligible=$false
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $out 'BUILD_MANIFEST.json') -Encoding UTF8
Write-Output "Native compile completed: $out\BlackDragon.ex5. Native test execution, Tester and restart gates remain NOT_RUN."
