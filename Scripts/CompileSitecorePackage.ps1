param([String]$inpath,[String]$outpath,[switch]$patch,[String]$patchpath,[switch]$patchexisting,[String[]]$exclude,[switch]$debug,[String]$compilerpath)

#Do not remove this:
Write-Host "
==============================================================================
| You are running Sitecore Precompilation script                             |
| Author: Alexandr Yeskov                                                    |
|                                                                            |
| Parameters:                                                                |
|  -inpath <path>       - path to Sitecore IIS Website root folder           |
|  -outpath <path>      - path for resulting files                           |
|  -patch               - create patch (new files only)                      |
|  -patchpath <path>    - path for resulting patch                           |
|  -patchexisting       - copy to the patch folder assemblies which already  |
|                         exist in not compiled app folder                   |
|  -exclude <paths>     - comma separated list of virtual paths to exclude   |
|                         from compilation                                   |
|  -debug               - create debug information files                     |
|  -compilerpath <path> - use to override path to aspnet_compiler            |
|                                                                            |
==============================================================================" -ForegroundColor Green

if ([String]::IsNullOrWhiteSpace($inpath)) {
    Write-Host "inpath parameter is required!"
    return
}

$inpath = $inpath.TrimEnd("\")

if ([String]::IsNullOrWhiteSpace($outpath)) {
    $outpath = $inpath + ".output"
    Write-Host "Using default output path: $outpath"
}

$outpath = $outpath.TrimEnd("\")

if ($patch -and [String]::IsNullOrWhiteSpace($patchpath)) {
    $patchpath = $outpath + ".patch"
    Write-Host "Using default patch path: $patchpath"
}

$patchpath = $patchpath.TrimEnd("\")

if ([String]::IsNullOrWhiteSpace($compilerpath)) {
    try {
        $aspver = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ASP.NET" -Name RootVer).RootVer
        $asppath = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ASP.NET\$aspver" -Name Path).Path
        $compilerpath=$asppath.TrimEnd("\") + "\aspnet_compiler.exe"
        [void](Get-Item $compilerpath)
        Write-Host "Using default compiler: $compilerpath"
    } catch {
        Write-Host "Can't find aspnet_compiler.exe, please specify path with -compilerpath parameter!" -ForegroundColor Red
        return
    }
}

$outDirInfo = Get-ChildItem $outpath | Measure-Object

if ($outDirInfo.count -ne 0) {
    Write-Host "Output directory is not empty, would you like to clean it up? (Default is No) (Y/N)" -ForegroundColor Red
    $Readhost = Read-Host "Remove files"
    Switch ($ReadHost)
    { 
        Y {Write-host "Removing files..."; Remove-Item "$outpath\*" -Recurse -Force}
        Default {Write-Host "Please remove files manually or use another output folder"; return}
    }
}

$patchDirInfo = Get-ChildItem $patchpath | Measure-Object

if ($patch -and $patchDirInfo.count -ne 0) {
    Write-Host "Patch directory is not empty, would you like to clean it up? (Default is No) (Y/N)" -ForegroundColor Red
    $Readhost = Read-Host "Remove files"
    Switch ($ReadHost)
    { 
        Y {Write-host "Removing files..."; Remove-Item "$patchpath\*" -Recurse -Force}
        Default {Write-Host "Please remove files manually or use another patch folder"; return}
    }
}

$cmdLine = @("-p", " $inpath", "-v", "/", "$outpath", "-errorstack");

if ($debug) {
    $cmdLine += "-d"
}

$cmdLine += "-x"
#can't precompile due to dependencies
$cmdLine += "/sitecore/shell/client/Speak/Layouts/Renderings/Data/WebServiceDataSources/"

if ($exclude -ne $null -and $exclude.Count -gt 0) {
    $exclude | %{ $cmdLine += "-x"; $cmdLine += $_}
}

Write-Host "Running compiler with parameters: " -ForegroundColor Yellow
Write-Host $cmdLine -ForegroundColor Yellow

& $compilerpath $cmdLine

"<precompiledApp version=""2"" updatable=""true""/>" | Out-File -NoNewline -filepath ($outpath + "\PrecompiledApp.config")

if ($patch) {
    $compiledFiles = get-childitem $outpath -include *.compiled -recurse
    $files = $compiledFiles | % { 
                @{
                    path=$_.Directory.FullName; 
                    compiled=$_.FullName.Replace($outpath, ""); 
                    assembly=(Select-Xml -Path $_.FullName -XPath "/preserve").Node.assembly;
                    source=(Select-Xml -Path $_.FullName -XPath "/preserve").Node.virtualPath
                 }
             }
    $files | ? {$_.assembly -ne $null} | %{$_.assembly = $_.path.Replace($outpath, "") + "\" + $_.assembly.Replace("/", "\") + ".dll"}
    $files | ? {$_.source -ne $null} | %{$_.source = $_.source.Replace("/", "\")}

    Write-Host "Creating folders structure for patch..." -ForegroundColor Yellow
    [void][System.IO.Directory]::CreateDirectory($patchpath + "\bin\")
    $files | ? {$_.assembly -ne $null} | % { [System.IO.Path]::GetDirectoryName($patchpath + $_.assembly)} | sort-object -Unique | %{[void][System.IO.Directory]::CreateDirectory($_)}
    $files | ? {$_.source -ne $null} | % { [System.IO.Path]::GetDirectoryName($patchpath + $_.source)} | sort-object -Unique | %{[void][System.IO.Directory]::CreateDirectory($_)}

    Write-Host "Copying files for patch..." -ForegroundColor Yellow
    $files | ? {$_.assembly -ne $null -and ($patchexisting -or -not (Test-Path ($inpath + $_.assembly) -PathType Leaf))} | %{Copy-Item ($outpath + $_.assembly) ($patchpath + $_.assembly) -Force}
    $files | ? {$_.source -ne $null -and (Test-Path ($outpath + $_.source) -PathType Leaf)} | %{Copy-Item ($outpath + $_.source) ($patchpath + $_.source) -Force}
    $files | ? {$_.compiled -ne $null} | %{Copy-Item ($outpath + $_.compiled) ($patchpath + $_.compiled) -Force}
    Copy-Item ($outpath + "\PrecompiledApp.config") ($patchpath + "\PrecompiledApp.config") -Force

    Write-Host "Removing empty folders..." -ForegroundColor Yellow
    Get-ChildItem $patchpath -recurse | ? {$_.PSIsContainer -and @(Get-ChildItem -LiteralPath:$_.fullname).Count -eq 0} | remove-item

    [void](Add-Type -Assembly "System.IO.Compression.FileSystem")
    [System.IO.Compression.ZipFile]::CreateFromDirectory($patchpath, $patchpath + ".zip") ;
}

Write-Host "Done! Thank you for your time!" -ForegroundColor Yellow