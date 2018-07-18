# Migrating to SDK based projects

Visual Studio 2017 introduced a new interesting format. As some people does, I call these project types **SDK based projects**

This format is very clean and it also uses the new PackageReference mechanism instead of the legacy `packages.config`

This repository will hold scripts that can help in this task of migrating an existing .NET project that uses the "old"-tooling to the new SDK-based tooling in Visual Studio 2017.

**WARNING**
Use these scripts at your own risk. 

They have not been thoroughly tested. Make sure you have a backup of your project or
use version control (Git, TFVC, etc.). 

Also note that after migrating these projects **can only be opened with Visual Studio 2017**

# Usage
.\MigrateToNewTooling.ps1 -TargetFolder <folder-containing-solution> [-Verbose]
