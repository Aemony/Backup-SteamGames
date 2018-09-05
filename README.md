# Backup-SteamGames
Powershell script automating backup up all existing Steam games on the system, according to app ID and build ID. It also creates a dummy **steamapp_id.txt** file with the app ID in the resulting target directory, to enable running games directly from those backups if they support it. Note that some games might require that file to be moved if their executable is located in a subfolder.

It uses robocopy, and is optimized for the maximum available throughput, so expect to see 100+ MiB/s speeds if the destination and infrastructure allows it. Do note however that weaker machines (less than 6 cores, I imagine) will most likely see foreground applications be affected while the script is running.

Rescans of libraries are quite quick despite pretty much checking all source folders for new files. It takes ~2m40s on my system to perform a full rescan of my 1.2 TB of installed games.

#### Disclaimer: Use at your own risk!
This works great for me, but I am only one user with one use-case. I can't guarantee it works on all systems.

## This is not intended for users with storage concerns!
The script makes a full new copy of the install folder whenever a new build of the game is detected, meaning the storage requirement will run away quite quickly as running the script frequently will mean that X amount of copies of the game will be stored.

## Automatic backup
Should be quite compatible with being run as a scheduled background task in Windows, if desired, although I haven't verified it myself.

## Installation
Simply download the script to a location of your choice, open [Backup-SteamGames.ps1](Backup-SteamGames.ps1) and configure it appropriately under the **CONFIGURATION** section.

I recommend excluding all drives/Steam Libraries except one with a small number of games to properly test the script out first.

## Credits
Modules comes from https://github.com/ChiefIntegrator/Steam-GetOnTop
