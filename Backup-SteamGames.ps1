<#
.SYNOPSIS
	Performs a backup on all installed and updated Steam games present on the PC.

.DESCRIPTION
	Checks all Steam libraries and their appmanifest files to detect fully
	updated applications and copies these over to a specified location.

	Note that this script separates builds into different subfolders,
	meaning it isn't a simple 1:1 mirroring between the source and
	destination. The main purpose of this script is to enable automatic
	build backups of each version released for a game on Steam.

	As the script does not clean previous builds, THIS WILL result in
	massive storage requirements down the line.
  
.NOTES
	Updated on:     2018-09-22     Converted over to standalone template, added parameter support, added appmanifest validation.
	Created on:   	2018-09-01
   
	Author: Aemony

.EXAMPLE
  Run the Backup-SteamGames script to backup all installed games to C:\DestinationFolder:
  Backup-SteamGames -Destination C:\DestinationFolder

.EXAMPLE
  Run the Backup-SteamGames script to backup all installed games to C:\DestinationFolder,
  but do not actually perform the copy action:
  Backup-SteamGames -Destination C:\DestinationFolder -SkipCopyToDestination

.EXAMPLE 
  Run the Backup-SteamGames script to backup all installed games to C:\DestinationFolder
  and exclude all games installed under the C:\, D:\, E:\, and G:\ drives:
  Backup-SteamGames -Destination C:\DestinationFolder -ExcludeDrives C,G,H,E

.EXAMPLE 
  Run the Backup-SteamGames script to backup all installed games to C:\DestinationFolder
  and exclude app 230230 (Divinity: Original Sin (Classic)) and 750920 (Shadow of the Tomb Raider)
  Backup-SteamGames -Destination C:\DestinationFolder -ExcludeAppIDs 230230,750920

.LINK
	https://github.com/Idearum/Backup-SteamGames
	https://github.com/ChiefIntegrator/Steam-GetOnTop

#>

[CmdletBinding()]

Param ( 
	# Destination folder where folders are backed up to, ex. $Destination = "D:\testDestination"
	[string]$Destination = "D:\testDestination",

	# Enable debug mode (does not actually perform any copying)
	[switch]$SkipCopyToDestination = $false,

	 # Exclude specific drives (Steam only supports one library per drive, so no need to be more specific), ex. $ExcludeDrives = @('Z', 'E', 'H', 'G')
	[array]$ExcludeDrives = @('Z'),
	# Exclude specific app IDs, ex. $ExcludeAppIDs = @('26495', '7655', '4568')
	[array]$ExcludeAppIDs = @(),

	# Log file / console output level. Accepts "None", "Standard", "Verbose", "Debug" (Verbose & Debug not currently being used)
	[string]$LogLevel = "Standard",
	
	# Log file to use, ex. $LogFile = ".\Log.log"
	[string]$LogDirectory = ".\Logs",
	[string]$LogFile = "$LogDirectory\" + (Get-Date -f 'MM-dd-yyyy HH.mm.ss') + ".log",
	
	# Pause after execution (good for testing, bad for production)
	[switch]$PausePostExecution = $false,
	
	# Clean up logs older than one week?
	[switch]$LogCleanup,
	
	# Threshold for logs (in days, so '7' will remove all logs older than 7 days)
	[int]$LogCleanupThreshold = 7
)
#----------------[ Declarations ]------------------------------------------------------

# Set Error Action
# $ErrorActionPreference = "Continue"

# Import required modules. These two were obtained from https://github.com/ChiefIntegrator/Steam-GetOnTop
Import-Module -Name ".\Modules\SteamTools\SteamTools.psm1"
Import-Module -Name ".\Modules\LogTools\LogTools.psm1"

#----------------[ Functions ]---------------------------------------------------------

# Quick function to easily verify whether a path is excluded or not
function Confirm-PathNotExcluded ([string]$Path, [array]$ExclusionArray)
{
	foreach ($Exclusion in $ExclusionArray)
	{
		if ($Path -like "$Exclusion*")
		{
			return $false
		}
	}
	
	return $true
}

# After testing a ton of alternatives as well as trying my own, this is what I ended up using based on https://stackoverflow.com/a/25334958
# This shows a simplistic per-file progress without affecting time to completion all that much.
# Another alternative I tried had a fancier progress window but took 45% longer to complete, which is unacceptable when dealing with >1 TB libraries
function Copy-WithProgressBars
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[string]$Source,
		[Parameter(Mandatory = $true)]
		[string]$Destination,
		[Parameter(Mandatory = $true)]
		[string]$Name
	)
	
	# Dummy progress report as robocopy won't return anything until after it have compared source with dest
	Write-Progress "Comparing source and destination folders..." -Activity "Processing '$Name'" -CurrentOperation "" -ErrorAction SilentlyContinue;
	
	# Copy the files over!
	robocopy $Source $Destination /E /NDL /NJH /NJS /XJD | %{ $data = $_.Split([char]9); if ("$($data[4])" -ne "") { $file = "$($data[4])" }; Write-Progress "File percentage $($data[0])" -Activity "Processing '$Name'" -CurrentOperation "$($file)" ; }
}

#----------------[ Main Execution ]----------------------------------------------------

#region Start logging

Set-LogPath $LogFile
Set-LogLevel $LogLevel

if ($LogLevel -ne "None")
{
	New-Item -Path $LogFile -ItemType File -Force | Out-Null
	Write-LogHeader -InputObject "Backup-SteamGames.ps1"
}

Write-Log -InputObject "Destination: $Destination"
Write-Log -InputObject "Excluded drives: $($ExcludeDrives -join ", ")"
Write-Log -InputObject "Excluded apps: $($ExcludeAppIDs -join ", ")"
Write-Log -InputObject "Pause after execution: $PausePostExecution"
Write-Log -InputObject " "

#endregion Start logging


#region Add Steam libraries

$SteamLibraries = New-Object System.Collections.ArrayList
$SteamPath = Get-SteamPath
Write-Log -InputObject "Steam is installed in '$SteamPath'"
$SteamLibraryFolders = ConvertFrom-VDF -InputObject (Get-Content "$SteamPath\steamapps\libraryfolders.vdf" -Encoding UTF8)

# Add main Steam library?
if (Confirm-PathNotExcluded -Path $SteamPath -ExclusionArray $ExcludeDrives)
{
	Write-Log -InputObject "Added library: '$SteamPath'"
	$SteamLibraries.Add($SteamPath) | Out-Null
}
else
{
	Write-Log -InputObject "Excluded library: '$SteamPath'"
}

# Add secondary Steam libraries?
for ($i = 1; $true; $i++)
{
	if ($null -eq $SteamLibraryFolders.LibraryFolders."$i")
	{
		break
	}
	
	$path = $SteamLibraryFolders.LibraryFolders."$i".Replace("\\", "\")
	
	if (Confirm-PathNotExcluded -Path $path -ExclusionArray $ExcludeDrives)
	{
		Write-Log -InputObject "Added library: '$path'"
		$SteamLibraries.Add($path) | Out-Null
	}
	else
	{
		Write-Log -InputObject "Excluded library: '$path'"
	}
}

#endregion Add Steam libraries


#region Main loop and execution (where the magic happens)

# Loop through each library

$issues = $false
:libraryLoop foreach ($Library in $SteamLibraries)
{
	$Apps = New-Object System.Collections.ArrayList
	$SkippedApps = New-Object System.Collections.ArrayList
	Write-Log -InputObject " "
	Write-Log -InputObject " "
	Write-Log -InputObject "Processing library '$Library'..."
	
	# Read all appmanifests for the current library and throw them in a fitting array
	$AppManifests = Get-ChildItem -Path "$Library\steamapps\appmanifest_*.acf" | Select-Object -ExpandProperty FullName
	foreach ($AppManifest in $AppManifests)
	{
		$importedApp = ConvertFrom-VDF -InputObject (Get-Content -Path $AppManifest -Encoding UTF8) | Select-Object -ExpandProperty AppState
		
		# Check if its excluded
		if ($importedApp.StateFlags -ne 4 -or $ExcludeAppIDs -contains $importedApp.appid)
		{
			# Check if the file is corrupt
			if($null -eq $importedApp.StateFlags -and $null -eq  $importedApp.appid -and $null -eq $importedApp.Name)
			{
				Write-Warning -Message "Corrupt appmanifest detected."
				# Corrupt AppManifest found!
				$importedApp = [PSCustomObject]@{
					appid    = (Get-Item -Path $AppManifest).BaseName -replace "appmanifest_", ""
					Name     = (Get-Item -Path $AppManifest).Name
				}
			}

			$SkippedApps.Add($importedApp) | Out-Null
		}
		else
		{
			$Apps.Add($importedApp) | Out-Null
		}
	}
	
	Write-Log -InputObject "Found $($Apps.Count) item(s) ready to be backed up, and $($SkippedApps.Count) item(s) to skip."
	
	# List skipped apps, if any exist
	if ($SkippedApps.Count -gt 0)
	{
		Write-Log -InputObject "Skipped items: "
		$SkippedApps | foreach { Write-Log -InputObject "	$($_.appid), '$($_.name)'" }
	}
	
	
	# Loop through each manifest of the current library
	
	Write-Log -InputObject " "
	:manifestLoop foreach ($App in $Apps)
	{
		Write-Log -InputObject "Processing app $($App.appid), '$($App.name)'..."
		$LiteralPathApp = ($Library + "\steamapps\common\" + $App.installdir)
		$DestinationApp = ($Destination + "\" + $App.appid + "\" + $App.buildid)
		$command = 0
		
		if (Test-Path -Path $Destination)
		{
			$command = Measure-Command {
				# Convert the app name into a safe file name to use
				$safeFileName = [String]::Join("", $App.name.Split([System.IO.Path]::GetInvalidFileNameChars()))
				
				Write-Log -InputObject "	Source: $LiteralPathApp"
				
				if($SkipCopyToDestination -eq $false)
				{
					Write-Log -InputObject "	Destination: $DestinationApp"

					# Copy appmanifest_#.acf file (this action also creates the target directory if it is missing)
					robocopy "$Library\steamapps" $DestinationApp "appmanifest_$($App.appid).acf" /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
					
					# Create dummy text with safe game title (this fails if the target directory haven't been created yet)
					New-Item -Path ($Destination + "\" + $App.appid + "\" + $safeFileName + ".txt") -ItemType file -ErrorAction SilentlyContinue | Out-Null
					
					# Copy the install folder
					Copy-WithProgressBars -Source $LiteralPathApp -Destination ($DestinationApp + "\" + $App.installdir) -Name $App.name
					
					# Simple steam_appid.txt creation to allow the game to be launched ouside of the regular install folder.
					# Note that since this doesn't check executable location, this file might be misplaced in some instances.
					# Oh, and don't overwrite it if it already exists (can otherwise cause issues with non-standard applications)
					$FileSteamAppID = ($DestinationApp + "\" + $App.installdir + "\steam_appid.txt")
					if ((Test-Path -Path $FileSteamAppID) -eq $false)
					{
						Out-File -FilePath $FileSteamAppID -InputObject $App.appid -Encoding ASCII -NoNewline
					}
				} else {
					Write-Log -InputObject "	Skipped destination: $DestinationApp"
				}
			}
			
			Write-Log -InputObject "Task finished in $("{0:D2}:{1:D2}:{2:D2}.{3:D3}" -f $command.Hours, $command.Minutes, $command.Seconds, $command.Milliseconds)."
			Write-Log -InputObject " "
		}
		else
		{
			$issues = $true
			Write-Log -InputObject "'$Destination' is not reachable or does not exist!" -MessageLevel Error
			Write-LogFooter -InputObject "'$Destination' is not reachable or does not exist!"
			break libraryLoop
		}
		
		<#
		$object = New-Object –TypeName PSObject
		$object | Add-Member –MemberType NoteProperty –Name App –Value $App.appid
		$object | Add-Member –MemberType NoteProperty –Name Build –Value $App.buildid
		$object | Add-Member –MemberType NoteProperty –Name Duration –Value $command
		$object | Add-Member –MemberType NoteProperty –Name Name –Value $App.name
		$object | Add-Member –MemberType NoteProperty –Name Source –Value $LiteralPathApp
		$object | Add-Member –MemberType NoteProperty –Name Destination –Value $DestinationApp
		Write-Output $object
		#>
	}
	
	Write-Log -InputObject "Library complete."
}

#endregion Main loop and execution (where the magic happens)


#----------------[ Post Execution ]----------------------------------------------------

if ($LogLevel -ne "None" -and $issues -eq $false)
{
	Write-LogFooter -InputObject "All libraries have been processed."
}

# Delete logs older than the threshold in days
if ($LogCleanup)
{
	Get-ChildItem -Path "$LogDirectory\*.log" | Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt (Get-Date).AddDays(-$LogCleanupThreshold) } | Remove-Item -Force
}

if ($PausePostExecution)
{
	pause
}
