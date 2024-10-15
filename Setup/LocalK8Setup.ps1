# This script will install wsl, latest ubuntu, docker, minikube, and set up the necessary certificates in order to run a local k8 cluster on a windows machine

# Check if the script is running with administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Warning "This script is not running as Administrator. Please run it as Administrator."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); #waits for any key entry before exiting
    exit
}

#region wsl install
$restartNeeded = $false

# Check if the Virtual Machine Platform optional component is enabled
$vmPlatformFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform
if ($vmPlatformFeature.State -ne "Enabled") {
    Write-Host "The Virtual Machine Platform is not enabled. Enabling it now..."
    Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart
    $restartNeeded = $true
    Write-Host "Virtual Machine Platform has been enabled."
} else {
    Write-Host "The Virtual Machine Platform is already enabled."
}

# Check if WSL is installed
$wslFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux
if ($wslFeature.State -ne "Enabled") {
    Write-Host "WSL is not installed. Installing WSL..."
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart
    $restartNeeded = $true
    Write-Host "WSL has been installed."
} else {
    Write-Host "WSL is already installed."
}

# If any changes were made, prompt for a restart
if ($restartNeeded) {
    Write-Warning "Please restart your computer to complete wsl installation. Then re-run this script to continue."
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    exit
}


# Get the list of installed WSL distributions
$installedDistros = wsl -l | ForEach-Object { ($_.Trim() -replace "\s.*", "")}

# Check if the specified distribution is in the list
if ($installedDistros -contains "Ubuntu") {
    Write-Host "Ubuntu is installed."
} else {
    wsl --update --web-download
    $ProgressPreference = 'SilentlyContinue' #for a faster download
    Write-Host "Downloading Ubuntu..."
    Invoke-WebRequest -Uri https://aka.ms/wslubuntu -OutFile Ubuntu.appx -UseBasicParsing
    $ProgressPreference = 'Continue'           

    # Actually install the wsl ubuntu  app
    Add-AppxPackage .\Ubuntu.appx

    # backup installation command if the first command did not function properly
    invoke-expression -Command "Add-AppxPackage .\Ubuntu.appx"
    Write-Output "Installed ubuntu"

    # path to the installed ubuntu.exe
    $ubuntu_path="$env:LOCALAPPDATA\Microsoft\WindowsApps\ubuntu"

    # let root be default username
    invoke-expression -Command "$ubuntu_path install --root"

    wsl --set-default-version 2 ## set wsl 2 as default
    wsl --setdefault "Ubuntu"
    Write-Host "Done with Ubuntu setup."
}
#endregion 

#region certificates
# copy windows certs into ubuntu 
# assumption is that any zscaler/company certes are already on ur machine

# Define the WSL destination directory where .pem files will be copied
$wslDestDir = "~/usr/local/share/ca-certificates"  # Example directory; adjust as needed

# Ensure the WSL destination directory exists
wsl -e bash -c "mkdir -p $wslDestDir"

# Access local certificate store for the Current User or Local Machine
$certs = Get-ChildItem -Path Cert:\LocalMachine\My

#pem certs (for minikube)
if ($certs.Count -eq 0) {
    Write-Host "No certificates found in the local certificate store."
} else {
    foreach ($cert in $certs) {
        # Export each certificate as a .pem file
        $pemFile = "$env:TEMP\$($cert.Thumbprint).pem"
        
        # Export the certificate as Base64 (PEM) format
        $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert) |
            Out-File -FilePath $pemFile

        Write-Host "Exported certificate: $pemFile"
        
        # Translate the Windows path to WSL path
        $certWslPath = $pemFile -replace ":", "" -replace "\\", "/"  -replace 'C', 'c'

        # Command to copy the certificate from Windows to WSL
        $copyCommand = "cp /mnt/$certWslPath $wslDestDir"

        # Execute the copy command in WSL
        wsl -e bash -c $copyCommand

    }
}
 #crt certs (for docker)
$certificateType = [System.Security.Cryptography.X509Certificates.X509Certificate2]
$includedStores = @("TrustedPublisher", "Root", "CA", "AuthRoot")

$certificates = $includedStores.ForEach({
    Get-ChildItem Cert:\CurrentUser\$_ | Where-Object { $_ -is $certificateType}
})

$pemCertificates = $certificates.ForEach({
    $pemCertificateContent = [System.Convert]::ToBase64String($_.RawData,1)
    "-----BEGIN CERTIFICATE-----`n${pemCertificateContent}`n-----END CERTIFICATE-----"
})

$uniquePemCertificates = $pemCertificates | Select-Object -Unique

($uniquePemCertificates | Out-String).Replace("`r", "") | Out-File -Encoding UTF8 $HOME\ca-certificates.crt

$localFolder =$HOME -replace ':', '' -replace '\\', '/'  -replace 'C', 'c'
wsl -u root cp -r /mnt/$localFolder/ca-certificates.crt /usr/local/share/ca-certificates
wsl -u root update-ca-certificates
#endregion

#region docker install
#uninstall conflicting packages
wsl -u root bash -c 'for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y \$pkg; done'

#install docker engine in ubuntu
$docker_script = Get-Content -Raw ./docker_install.sh
wsl -u root bash -c ($docker_script -replace '"', '\"')
#endregion

#region minikube
#install minikube, kubectl, and helm
$minikube_script = Get-Content -Raw ./minikube_install.sh
wsl -u root bash -c ($minikube_script -replace '"', '\"')
#endregion minikube

#region userconfig
#minikube will complain about running in root so we need to create a user and login as it. 
$user = 'linuxuser'
# Set the password for the user
$wslPassword = 'password'
# Create the WSL 
wsl -u root useradd -m -s /bin/bash $user
wsl -u root bash -c "echo `"$user`:$wslPassword`" | chpasswd"

#change default user in wsl for ubuntu
ubuntu config --default-user $user
#start services
wsl -u root service docker restart
wsl -u $user minikube start --driver=docker
wsl -u $user kubectl config use-context minikube

Write-Host "You should now be able to run a \" Docker run hello-world\" command without any cert issues. You may need to login "
Write-Host("Your linux user is `"$user`" and your password is `"$wslPassword`". You may change your password to something more secure")
Write-Host("You can no run minikube and docker on wsl. Remember that the windows cmd wsl window must be kept open to keep minikube alive")
Write-Host("To run minikube, open a cmd window, type wsl, then type minikube start")
Write-Host("Typing wsl will mount the current windows folder you are in on cmd into linux. This can let you do stuff like building local dockerfiles or running deployment files on your windows folder.")
Write-Host "Press any key to continue..."
[void][System.Console]::ReadKey($true)  # Waits for any key press before closing
