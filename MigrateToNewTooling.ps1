param(
    [Parameter(Mandatory=$true)]
    [string]$TargetFolder
)

function CopyPackageReferences($project, $packagesConfigPath) {
    $packagesConfig = [xml](Get-Content $packagesConfigPath -Encoding UTF8)
    $itemGroup = $project.CreateElement("ItemGroup")
    $project.Project.AppendChild($itemGroup) | Out-Null
    Write-Verbose "Found $($packagesConfig.packages.package.Length) packages to copy"
    foreach ($packageReference in $packagesConfig.packages.package) {
        $packageReferenceElement = $project.CreateElement("PackageReference")
        $packageReferenceElement.SetAttribute("Include", $packageReference.id) | Out-Null
        $packageReferenceElement.SetAttribute("Version", $packageReference.version) | Out-Null
        $itemGroup.AppendChild($packageReferenceElement) | Out-Null
    }
}

function CopyProjectReferences($project, $originalProject) {
    $projectReferences = $originalProject.Project.ItemGroup.ProjectReference | Where-Object { $_.Include -ne $null}
    $itemGroup = $project.CreateElement("ItemGroup")
    $project.Project.AppendChild($itemGroup) | Out-Null
    Write-Verbose "Found $($projectReferences.Count) project references to copy"
    foreach ($projectReference in $projectReferences){
        $projectReferenceElement = $project.CreateElement("ProjectReference")
        $projectReferenceElement.SetAttribute("Include", $projectReference.Include)
        $itemGroup.AppendChild($projectReferenceElement) | Out-Null
    }
}

function CopyAssemblyReferences($project, $originalProject) {
    $assemblyReferences = $originalProject.Project.ItemGroup.Reference | Where-Object {
        ($_.HintPath -ne $null -and
         $_.HintPath -notlike "..\packages*") -or
        ($_.HintPath -eq $null)
    }
    $itemGroup = $project.CreateElement("ItemGroup")
    $project.Project.AppendChild($itemGroup) | Out-Null
    Write-Verbose "Found $($assemblyReferences.Count) assembly references to copy"
    foreach ($assemblyReference in $assemblyReferences) {
        if ($assemblyReference.Include -eq $null) {
            continue
        }
        
        $assemblyReferenceElement = $project.CreateElement("Reference")
        $assemblyReferenceElement.SetAttribute("Include", $assemblyReference.Include)
        if ($assemblyReference.HintPath -ne $null) {
            $hintPathElement = $project.CreateElement("HintPath")
            $hintPathElement.InnerText = $assemblyReference.HintPath
            $assemblyReferenceElement.AppendChild($hintPathElement) | Out-Null
        }

        $itemGroup.AppendChild($assemblyReferenceElement) | Out-Null
    }
}

function SetTargetFramework($project, $originalProject) {
    $targetFrameworkVersion = $originalProject.Project.PropertyGroup.TargetFrameworkVersion | Select-Object -First 1
    $targetFrameworkIdentifier = $originalProject.Project.PropertyGroup.TargetFrameworkIdentifier
    Write-Verbose "Found target framework version $targetFrameworkVersion"
    if ($targetFrameworkVersion -eq "v4.5.2" -and $targetFrameworkIdentifier -eq $null) {
        $project.Project.PropertyGroup.TargetFramework = "net452"
        return
    } elseif ($targetFrameworkVersion -eq "v5.0" -and $targetFrameworkIdentifier -eq "Silverlight") {
        $project.Project.PropertyGroup.TargetFramework = "sl50"
        $propertyGroup = $project.CreateElement("PropertyGroup");
        $propertyGroup.SetAttribute("Condition", '''$(TargetFramework)'' == ''sl50''')
        $targetFrameworkIdentifierElement = $project.CreateElement("TargetFrameworkIdentifier")
        $targetFrameworkIdentifierElement.InnerText = $targetFrameworkIdentifier
        $targetFrameworkVersionElement = $project.CreateElement("TargetFrameworkVersion")
        $targetFrameworkVersionElement.InnerText = $targetFrameworkVersion
        $propertyGroup.AppendChild($targetFrameworkIdentifierElement) | Out-Null
        $propertyGroup.AppendChild($targetFrameworkVersionElement) | Out-Null
        $project.Project.AppendChild($propertyGroup) | Out-Null
        return
    }

    Write-Warning "Unknown target framework version $targetFrameworkVersion"
}

# Make sure the target folder exists
Write-Verbose "Checking if target folder $TargetFolder exists..."
if (!(Test-Path $TargetFolder)) {
    Write-Error "Target folder $TargetFolder does not exist."
    exit 1
}

# Find csproj files in the target folder
Write-Verbose "Searching for projects to migrate in folder $TargetFolder"
$projectsToMigrate = Get-ChildItem -Recurse -Filter *.csproj -Path $TargetFolder
if ($projectsToMigrate.Length -eq 0) {
    Write-Error "No projects found to migrate in target folder $TargetFolder"
    exit 1
}

# Go through each of the projects
Write-Verbose "Found $($projectsToMigrate.Length) projects to migrate"
foreach ($projectToMigrate in $projectsToMigrate) {
    # Load the original project
    $originalProject = [xml](Get-Content $projectToMigrate.FullName -Encoding UTF8)

    # Remove the existing project
    Write-Verbose "Removing existing project at $($projectToMigrate.FullName)"
    Remove-Item $projectToMigrate.FullName

    # Go to the folder containing the project
    $projectFolder = [System.IO.Path]::GetDirectoryName($projectToMigrate.FullName)
    Push-Location $projectFolder

    # Create a new project
    Write-Verbose "Creating new project at $projectFolder"
    & dotnet new  classlib
    # Remove dummy Class1.cs file from template
    Remove-Item (Join-Path $projectFolder "Class1.cs")
    $projectPath = (Join-Path $projectFolder (Split-Path $projectFolder -Leaf)) + ".csproj"
    Write-Verbose "Created new project at $projectPath"

    # Load the project file for further manipulation
    $project = [xml](Get-Content $projectPath -Encoding UTF8)
    SetTargetframework $project $originalProject

    # Copy over package references from packages.config
    $packagesConfigPath = Join-Path $projectFolder "packages.config"
    Write-Verbose "Copying package references from $packagesConfigPath"
    if (Test-Path $packagesConfigPath) {
        CopyPackageReferences $project $packagesConfigPath
        Remove-Item $packagesConfigPath
    }

    # Copy over project references
    Write-Verbose "Copying project references from $($projectToMigrate.FullName)"
    CopyProjectReferences $project $originalProject

    # Copy over assembly references
    Write-Verbose "Copying assembly references from $($projectToMigrate.FullName)"
    CopyAssemblyReferences $project $originalProject

    # Remove AssemblyInfo.cs files (now handled by the project file)
    $assemblyInfoPath = Join-Path (Join-Path $projectFolder "Properties") "AssemblyInfo.cs"
    if (Test-Path $assemblyInfoPath) {
        Write-Verbose "Removing $assemblyInfoPath"
        Remove-Item $assemblyInfoPath
    }

    # Save the project file
    $project.Save($projectPath)
    Pop-Location
}
