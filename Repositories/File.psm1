﻿$PoshCodeModuleRoot = Get-Variable PSScriptRoot -ErrorAction SilentlyContinue | ForEach-Object { Split-Path $_.Value -Parent }
if(!$PoshCodeModuleRoot) {
  $PoshCodeModuleRoot = Split-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) -Parent
}

Import-Module $PoshCodeModuleRoot\Configuration.psm1
Import-Module $PoshCodeModuleRoot\Atom.psm1
if(!(Get-Command Invoke-WebReques[t] -ErrorAction SilentlyContinue)){
  Import-Module $PoshCodeModuleRoot\InvokeWeb
}

function FindModule {
    [CmdletBinding()]
    param(
        # Term to Search for (defaults to find "all" modules)
        [string]$SearchTerm,

        # Search for modules published by a particular author.
        [string]$Author,

        # Search for a specific module.
        [string]$ModuleName,

        # Search for an exact version
        [string]$Version = '*',

        # How long to trust a local cached copy of the file
        [int]$CacheTimeSeconds = 300,

        # A unique name for this root
        [Parameter(Mandatory=$true)]
        [String]$Name,

        [Parameter(Mandatory=$true)]
        $Root
    )
    begin {
        $uri = [uri]$Root

        $CachePath = Join-Path (Get-LocalStoragePath "FileRepoCache") "$Name.xml"

        $Cache = Get-Item $CachePath -ErrorAction SilentlyContinue
        if(!$Cache -or ([DateTime]::Now - $Cache.LastWriteTime).TotalSeconds -gt $CacheTimeSeconds) {
            if($uri.Scheme -match "https?")
            {
                Write-Verbose "Fetching feed from $root"
                Invoke-WebRequest $root -OutFile $CachePath
            }
            else
            {   # File based: we don't really need to cache it, so just ...
                $CachePath = $root 
            }
        } else {
            Write-Verbose "Using cached feed of $root"
        }
        Write-Verbose "Read Feed from $CachePath"
        $content = Import-AtomFeed $CachePath -AdditionalData @{ Repository = @{ File = $Root } }
    }
    
    process {
        # PSGet handles a lot of extra "types" but calls packages and zip files all "application/zip"
        $content = $content | Where-Object { $_.PackageType -eq "application/zip" }

        if($ModuleName)
        {
            #using match to make it a little more flexible
            $content = $content | Where-Object { $_.name -match $ModuleName}
            Write-Verbose "Filtering by ModuleName: $ModuleName"
        }
        elseif($SearchTerm)
        {
            Write-Verbose "Filtering by SearchTerm: $SearchTerm"
            # Where does nuget search? Name, Tags, Description?
            $content = $content | Where-Object { $_.name -match $ModuleName}
        }
        if($Author)
        {
            #using match to be more flexible
            $content = $content | Where-Object {$_.Author -match $Author}
            Write-Verbose "Filtering by Author: $Author"
        }

        if($Version -and $Version -ne '*')
        {    
            $content = $content | Where-Object {$Version -eq $_.version}
            Write-Verbose "Filtering by Version: $version"
        }
        else
        {
            Write-Verbose "Version Wildcard, returning all versions"
        }
        
        if(!$IncludePrerelease)
        {
            $content = $content | Where-Object {-not $_.IsPrerelease}
            Write-Verbose "Excluding Prerelease modules"  
        }
        else
        {
            Write-Verbose "Including prerelease modules"
        }

        #add type name and output

        $content
        
    }
}