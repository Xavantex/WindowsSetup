<#
.SYNOPSIS
Install core tools

.DESCRIPTION
Inspired by config files and reinstallation.
#>

# Need to make sure you have winget first
# Check if windows 10

Begin
{
  Write-Output "Setup stuff"
  if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
  {
      Read-Host -Prompt "Not running elevated, quitting"
      exit
  }
  $ErrorActionPreference = "Stop"

	$win10 = (Get-ComputerInfo).OsName -match 10

  function isInstalled
  {
    param($tool)
    winget list --id $tool -e --source winget | Select-String -Pattern "No installed package found"
  }
	
	function winstall
	{
		param($tool)
		if (winget list --id $tool -e --source winget | Select-String -Pattern "No installed package found")
		{
			winget install --id $tool -e --source winget --accept-source-agreements --accept-package-agreements
		}
	}

  function chwinstall
	{
		param($tool)
		if ($ninstalled)
		{
			winget install --id $tool -e --source winget --accept-source-agreements --accept-package-agreements
		}
	}
	
	function ctwinstall
	{
		param($tool, $dlURL)
		if (winget list $tool | Select-String -Pattern "No installed package found")
		{
			Invoke-WebRequest $dlURL -OutFile "$tool.exe"
			& $PSScriptRoot\$tool.exe
		}
	}
	
	function forcewinstall
	{
		param($tool)
		winget install --id $tool -e --source winget --accept-source-agreements --accept-package-agreements
	}
}

Process
{
  # DOCS ARE NOT SAYING GCC is need SO WE, have to add it SNOOOOOOORE.
	# Install chocolatey because it is a pain to handle mingw, make and other stuff on winget atm
  Write-Output "Chocolately"
	if (!(Get-Command choco -errorAction SilentlyContinue))
	{
		[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
		Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
		& $PSScriptRoot\scripts\Update-Environment.ps1
	}
    choco feature enable -n allowGlobalConfirmation

  Write-Output "Powershell 7"
	# Check that Powershell is above version 5 and if not install.
	# Should add check if pwrshell 7 already is installed, not just this environment.
	#if ($PSVersionTable.PSVersion.Major -ge 7)
	#{
	#	winget install --id Microsoft.Powershell -e --source winget --accept-source-agreements --accept-package-agreements
	#}
	if ($PSVersionTable.PSVersion -lt [Version]"7.0")
	{
		#winget install --id Microsoft.PowerShell -e --source winget --accept-source-agreements --accept-package-agreements
    choco install powershell-core

    if (!(Get-Command pwsh -errorAction SilentlyContinue))
    {
      & $PSScriptRoot\scripts\Update-Environment.ps1
    }

    pwsh $PSCommandPath
    exit
	}

  # Get credentials from bitwarden
  Write-Output "Bitwarden"
  if (!(Get-Command gcc -errorAction SilentlyContinue))
	{
		choco install bitwarden-cli
    if (!(Get-Command gcc -errorAction SilentlyContinue))
    {
      & $PSScriptRoot\scripts\Update-Environment.ps1
    }
	}

  # Fetch GUID from secret file
  Get-Content $PSScriptRoot\bitwardGUID.txt | Foreach-Object{
    $var = $_.Split('=')
    New-Variable -Name $var[0] -Value $var[1]
  }
    
  $SESSION_ID=(bw login --raw)

  $steam=bw get item $steam --session $SESSION_ID | ConvertFrom-Json | Select-Object -ExpandProperty login
  $github=bw get item $github --session $SESSION_ID | ConvertFrom-Json | Select-Object -ExpandProperty login

  $steamuser=$steam.username
  $steampass=$steam.password

  # Since github otherwise rate limit download, snore
  $gituser=$github.username
  $gitpass=$github.password

  bw logout


  Write-Output "STEAM GAMES"
  Write-Output "Downloading now so no need to wait"
  Write-Output "And to authenticate with SteamGuarde immediately, no manual stuff later on."
	# Install SteamCMD to install games
	# This expects steam is in C:
	# No real good way to see where steam is installed at the moment
  # This Might not work, it is untested without steam installed,
  # But it should install game to steamapps/common probably!
	if (!(Test-Path -Path "C:\Program Files (x86)\Steam\steamcmd.exe" -PathType Leaf))
	{
		Invoke-WebRequest "https://steamcdn-a.akamaihd.net/client/installer/steamcmd.zip" -OutFile "steamcmd.zip"
		Expand-Archive "steamcmd.zip" "C:\Program Files (x86)\Steam"
    #	setx /M path "%path%;C:\Program Files (x86)\SteamCMD\"
		Remove-Item "steamcmd.zip"
    # Install steam games deemed necessary
		& 'C:\Program Files (x86)\Steam\steamcmd' +login $steamuser $steampass +runscript $PSScriptRoot\scripts\steamInstalls.txt
	}


  Write-Output "Winget"
	# Download winget if we do not have it
	if (!(Get-Command winget -errorAction SilentlyContinue))
	{
    choco install microsoft-ui-xaml

    $pair = "$($gituser):$($gitpass)"

    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))

    $basicAuthValue = "Basic $encodedCreds"

    $Headers = @{
        Authorization = $basicAuthValue
    }


		# get latest download url
		$URL = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
		$URL = (Invoke-WebRequest -Uri $URL -Headers $Headers -UseBasicParsing).Content | ConvertFrom-Json |
				Select-Object -ExpandProperty "assets" |
				Where-Object "browser_download_url" -Match '.msixbundle' |
				Select-Object -ExpandProperty "browser_download_url"

    # RELIES on VCL so download and install
    #Invoke-WebRequest -Uri "https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx" -OutFile "SetupVCL.appx" -UseBasicParsing
    #powershell Add-AppxPackage -Path "SetupVCL.appx"
    #Remove-Item "SetupVCL.appx"
    choco install microsoft-vclibs

		# download
		Invoke-WebRequest -Uri $URL -OutFile "Setup.msix" -UseBasicParsing

		# install
    # Snore not fixed in powershell 7
		powershell Add-AppxPackage -Path "Setup.msix"
    & $PSScriptRoot\scripts\Update-Environment.ps1

		# delete file
		Remove-Item "Setup.msix"
	}


  Write-Output "Set important configs"
	# Remove sticky keys, toggle keys, filter keys
	if ((Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags') -eq "506")
  {
    Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\StickyKeys' -Name 'Flags' -Value "506" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags') -eq "58")
  {
    Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\ToggleKeys' -Name 'Flags' -Value "58" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags') -eq "122")
  {
    Set-ItemProperty -Path 'HKCU:\Control Panel\Accessibility\Keyboard Response' -Name 'Flags' -Value "122" -Force
  }

	# Set Keyboard delay to low, and keyboard speed to high
  #
	if ((Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardDelay') -eq "0")
  {
    Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardDelay' -Value '0' -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardSpeed') -eq "31")
  {
    Set-ItemProperty -Path 'HKCU:\Control Panel\Keyboard' -Name 'KeyboardSpeed' -Value '31' -Force
  }

  # Set Dark Mode
	if ((Get-ItemPropertyValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme') -eq "0")
  {
    Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'AppsUseLightTheme' -Value "0" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme') -eq "0")
  {
    Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'SystemUsesLightTheme' -Value "0" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency') -eq "0")
  {
    Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name 'EnableTransparency' -Value "0" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -Name 'BackgroundType') -eq "1")
  {
    Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers' -Name 'BackgroundType' -Value "1" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WallPaper') -eq "")
  {
    Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name 'WallPaper' -Value "" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\Control Panel\Colors' -Name 'Background') -eq "0 0 0")
  {
    Set-ItemProperty 'HKCU:\Control Panel\Colors' -Name 'Background' -Value "0 0 0" -Force
  }

  # file extension stuff
	if ((Get-ItemPropertyValue 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden') -eq "1")
  {
    Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Value "1" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt') -eq "0")
  {
    Set-ItemProperty 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value "0" -Force
  }

  # Disable left alt + shift and left ctrl + shift to switch language and keyboard layout
	if ((Get-ItemPropertyValue -Path 'HKCU:\Keyboard Layout\Toggle' -Name 'Hotkey') -eq "3")
  {
    Set-ItemProperty 'HKCU:\Keyboard Layout\Toggle' -Name 'Hotkey' -Value "3" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\Keyboard Layout\Toggle' -Name 'Language Hotkey') -eq "3")
  {
    Set-ItemProperty 'HKCU:\Keyboard Layout\Toggle' -Name 'Language Hotkey' -Value "3" -Force
  }

	if ((Get-ItemPropertyValue -Path 'HKCU:\Keyboard Layout\Toggle' -Name 'Layout Hotkey') -eq "3")
  {
    Set-ItemProperty 'HKCU:\Keyboard Layout\Toggle' -Name 'Layout Hotkey' -Value "3" -Force
  }

  # TimeZone is botched when installing
	if ((Get-TimeZone).Id -eq "Central European Standard Time")
  {
    Set-TimeZone -Id "Central European Standard Time"
  }

  Write-Output "GIT"
	# Install GIT
	winstall Git.Git
	# Won't recognize that git is installed otherwise
	if (!(Get-Command git -errorAction SilentlyContinue))
	{
    & $PSScriptRoot\scripts\Update-Environment.ps1
  }

  Write-Output "MINGW"
  $checkInstall=False
	# DOCS ARE NOT SAYING GCC is need SO WE, have to add it SNOOOOOOORE.
	if (!(Get-Command gcc -errorAction SilentlyContinue))
	{
		choco install mingw
    if (!(Get-Command gcc -errorAction SilentlyContinue))
    {
      $checkInstall=True
    }
	}

  Write-Output "CLANG"
	# Good to have clang, but Lunarvim need it as well
	if (!(Get-Command clang -errorAction SilentlyContinue))
	{
		choco install llvm
    if (!(Get-Command clang -errorAction SilentlyContinue))
    {
      $checkInstall=True
    }
	}

  Write-Output "MAKE"
	# Specified just download
	if (!(Get-Command make -errorAction SilentlyContinue))
	{
		choco install make
    if (!(Get-Command make -errorAction SilentlyContinue))
    {
      $checkInstall=True
    }
	}

  if ($checkInstall)
  {
    & $PSScriptRoot\scripts\Update-Environment.ps1
    $checkInstall=False
  }

  Write-Output "7zip"
	# Install 7-zip
	winstall 7zip.7zip


	#Install LunarVim

  Write-Output "NEOVIM"
	# Install Neovim first
	# Neovim is 9.0 on winget
	winstall Neovim.Neovim


  Write-Output "PYTHON"
	# Install latest and "greatest" stable python
	#winstall Python.Python
	#if (python --version 2>&1 | Select-String -Pattern "Python was not found")
	#{
	#	forcewinstall Python.Python.3.9
	#}
  choco install python --version=3.9.0


	#!!!!!!!!!!!!!NOTE!!!!!!!!!!!!!!!
	#INSTALLING ON CHOCO, adds to $PATH as well
	#!!!!!!!!!!!!!NOTE!!!!!!!!!!!!!!!
	
	
	#$noLLVM = (winget list --id LLVM.LLVM -e --source winget | sls -Pattern "No installed package found")
	#winstall LLVM.LLVM
	#if ($noLLVM)
	#{
	#	[Environment]::SetEnvironmentVariable("Path",
	#	(gi -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" ).
	#	GetValue('Path', '', 'DoNotExpandEnvironmentNames') + ";C:\Program Files\LLVM\bin",
	#	[EnvironmentVariableTarget]::Machine)
	#}
	
	#$noMake = (winget list --id GnuWin32.Make -e --source winget | sls -Pattern "No installed package found")
	# Install Make
	#winstall GnuWin32.Make
	# Adding to path, this will NOT remove any symlink and dynamic items, such as %systemroot% or %NVM_HOME%
	#if ($noMake)
	#{
	#	[Environment]::SetEnvironmentVariable("Path",
	#	(gi -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" ).
	#	GetValue('Path', '', 'DoNotExpandEnvironmentNames') + ";C:\Program Files (x86)\GnuWin32\bin",
	#	[EnvironmentVariableTarget]::Machine)
	#}



  Write-Output "RUST"
	# Install Rustup, recommended Rust installation
	# Check what flags to use for most automation
	winstall Rustlang.Rustup

  Write-Output "NVM"
	# NVM node.js + npm version manager
	$ninstalled = isInstalled CoreyButler.NVMforWindows
	chwinstall CoreyButler.NVMforWindows
	if ($ninstalled)
	{
    if (!(Get-Command nvm -errorAction SilentlyContinue))
    {
      & $PSScriptRoot\scripts\Update-Environment.ps1
    }
		# Install latest lts at 64 bit
		nvm install lts 64
		# Use latest lts at 64 bit
		nvm use lts 64

		if (!(Get-Command npm -errorAction SilentlyContinue))
    {
      & $PSScriptRoot\scripts\Update-Environment.ps1
    }
		# Because lunarvim install is broken without this
		npm i tree-sitter-cli
	}


  Write-Output "LUNARVIM"
	# Install Lunarvim config
	if (!(Get-Command lvim -errorAction SilentlyContinue))
	{
		'y', 'y', 'y' | pwsh -c "`$LV_BRANCH='release-1.3/neovim-0.9'; Invoke-WebRequest https://raw.githubusercontent.com/LunarVim/LunarVim/release-1.3/neovim-0.9/utils/installer/install.ps1 -UseBasicParsing | Invoke-Expression"
		
		Invoke-WebRequest "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.1/JetBrainsMono.zip" -OutFile "jetbrains.zip"
		Invoke-WebRequest "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.1/Hack.zip" -OutFile "hack.zip"
		
		Expand-Archive "jetbrains.zip" $PSScriptRoot\patched-fonts\JetBrainsMono
		Expand-Archive "hack.zip" $PSScriptRoot\patched-fonts\Hack
		Remove-Item "jetbrains.zip"
		Remove-Item "hack.zip"
    # Install all the JetBrainsMono etc. fonts
		& $PSScriptRoot\scripts\NFInstall.ps1 JetBrainsMono, Hack

    # This directory could perhaps not exist before :Lazy sync, if so and this fails add it as echo command
    pwsh -WorkingDirectory $env:USERPROFILE\AppData\Roaming\lunarvim\site\pack\lazy\opt\telescope-fzf-native.nvim -c make
	}
	# END OF LUNARVIM INSTALL
	

  Write-Output "STEAM"
	# Install steam
  $ninstalled = isInstalled Valve.Steam
	chwinstall Valve.Steam

  # These checks are becoming many, to fix in future fix alternative checking
  # so only one if check is needed
  if ($ninstalled)
  {
    & 'C:\Program Files (x86)\Steam\steam.exe'
  }
	
  Write-Output "SMALLSTEP"
	# Install step CLI for certificates
	winstall Smallstep.step
	
  Write-Output "DISCORD"
	# Install discord for friends
	# Look at updating toward spacebarchat
	winstall Discord.Discord
	
  Write-Output "VLC"
	# <3 VLC for media
	winstall VideoLAN.VLC
	
  Write-Output "FIREFOX"
	# Install firefox
  $ninstalled = isInstalled Mozilla.Firefox
	chwinstall Mozilla.Firefox
  if ($ninstalled)
	{
    Write-Output "Firefox link in registry is botched, so check if set or not."
    $browser=(Get-ChildItem -Path Registry::HKCR\).PSChildName | Where-Object -FilterScript{ $_ -like "FirefoxURL*"}
    Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -Name ProgId -Value $browser
    Set-ItemProperty -Path 'HKCU:\SOFTWARE\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice' -Name ProgId -Value $browser
  }
    
    # This is supposedly working in windows 10 if above do not work
    #Add-Type -AssemblyName 'System.Windows.Forms'
    #Start-Process $env:windir\system32\control.exe -LoadUserProfile -Wait `
    #    -ArgumentList '/name Microsoft.DefaultPrograms /page pageDefaultProgram\pageAdvancedSettings?pszAppName=Firefox-308046B0AF4A39CB'
    #Sleep 2
    #[System.Windows.Forms.SendKeys]::SendWait("{TAB}{TAB}{DOWN}{DOWN} {DOWN} {DOWN}{DOWN}{DOWN}{DOWN}{DOWN}{DOWN} {DOWN} {TAB} ")
	
  Write-Output "THUNDERBIRD"
	# Install thunderbird
	# There is betterbird, a supposedly patched thunderbird : Betterbird.Betterbird
	winstall Mozilla.Thunderbird
	
  Write-Output "SOUND BLASTER"
	# Install sound blaster
	winstall CreativeTechnology.SoundBlasterCommand

  Write-Output "WOOTILITY"
	# Install wootility
	ctwinstall wootility-lekker "https://api.wooting.io/public/wootility/download?os=win&branch=lekker"
	
  Write-Output "DELL"
	# Dell display manager for my displays
	winstall Dell.DisplayManager
	
  Write-Output "ICUE"
	# Install latest iCUE, check if winstall have latest
	ctwinstall iCUE "https://downloads.corsair.com/Files/icue/Install-iCUE.exe"
	
  Write-Output "JELLYFIN"
	# Install jellyfin 
	winstall Jellyfin.JellyfinMediaPlayer
	
  Write-Output "Windows Terminal"
	# Install Windows Terminal
  $ninstalled = isInstalled Microsoft.WindowsTerminal
	chwinstall Microsoft.WindowsTerminal
	if ($ninstalled)
	{
		$wtPath = Join-Path (Get-ChildItem $env:LocalAppData\Packages -Directory -Filter "Microsoft.WindowsTerminal*")[0].FullName LocalState
		Copy-Item $PSScriptRoot\wtConf\settings.json $wtPath
		Copy-Item $PSScriptRoot\wtConf\state.json $wtPath
	}

  Write-Output "MSKLC"
	# Only download, no reliable way to know if installed already
  if (!(Test-Path -Path "$PSScriptRoot\winKeyLayout\MSKLC.exe" -PathType Leaf))
	{
    Invoke-WebRequest "https://download.microsoft.com/download/6/f/5/6f5ce43a-e892-4fd1-b9a6-1a0cbb64e6e2/MSKLC.exe" -OutFile "$PSScriptRoot\winKeyLayout\MSKLC.exe"
    & $PSScriptRoot\winKeyLayout\MSKLC.exe
  }

  Write-Output "FINISHED, update monitor settings manually, installers are located at: $PSScriptRoot, if you want to delete them."
  Write-Output "Can't autodelete since you need to first install everything"
  choco feature disable -n allowGlobalConfirmation
	Read-Host -Prompt "Scripts Completed Will Logoff: Press any key to exit"
  logoff
}
