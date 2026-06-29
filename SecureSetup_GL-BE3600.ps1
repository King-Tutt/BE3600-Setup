Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing



# Check for ~\.ssh\ and public key(s)
function Get-SshSetup {
	if(-not(Test-Path ~\.ssh\ -PathType Container)) {
		Write-Host "~\.ssh\ not found, setting up SSH..."
		New-Item -Path ~\ -Name .ssh -ItemType Directory
	}
	else {
		Write-Host "~\.ssh\ found"
	}
	if(-not(Test-Path "~\.ssh\id_ed25519.pub" -Type Leaf)) {
		Write-Host "Public key not found, generating keys..."
		ssh-keygen -t ed25519 -f ~\.ssh\id_ed25519
	}
	else {
		Write-Host "Public keys found"
		
	}
}

# Test for SSH banner grab
function Get-SshBanner {
	[CmdletBinding()]
	param (
	[string]$Target="192.168.8.1",
	[int]$Port=22,
	[int]$TimeoutMs=3000,
	[switch]$Silent=$true
	)
	
	$Buffer = [System.Text.StringBuilder]::new()
	try {
		$Socket = New-Object System.Net.Sockets.TcpClient($Target, $Port)
		$Stream = $Socket.GetStream()
		$Reader = New-Object System.IO.StreamReader($Stream)

		$Timeout = $false
		$StartTime = Get-Date

		while($Reader.Peek() -ne -1 -and -not $Timeout) {
			$Buffer.Append($Reader.Read()) | Out-Null
			if(((Get-Date) - $StartTime).TotalMilliseconds -gt $TimeoutMs) {
				$Timeout = $true
			}
		}
		$Buffer.ToString()
	}
	catch {
		if(-not $Silent) {
			Write-Host "Error connecting to $Target on port $Port`: $_" -ForegroundColor Yellow
		}
		$Buffer = $false
	}
	finally {
		if($Socket) {
			$Socket.Close()
		}
	}
	return $Buffer
}

# Wait for connection to device
function Wait-Connection {
	[CmdletBinding()]
    param (
		[string]$ComputerName="192.168.8.1"
    )
	Write-Host "Waiting for connection to $ComputerName"
	while(-not(Test-Connection $ComputerName -ErrorAction SilentlyContinue -Count 1)) {
	}
	while(-not (Get-SshBanner)) {
	}
}

# Get the device's public key
function Get-PublicKey {
	[CmdletBinding()]
	param (
		[string]$Path="~\.ssh\known_hosts",
		[string]$ComputerName="192.168.8.1"
	)
	$Keys = ssh-keyscan $ComputerName
	$KHosts = Get-Content (Resolve-Path $Path)
	foreach($item in $Keys) {
		if ($KHosts -notcontains $item) {
			$item | Out-File -FilePath (Resolve-Path $Path) -Encoding ascii -Append
		}
	}
	$KHosts = $null
}

# Disable password authentication over SSH, assuming public key authentication is enabled
function Disable-PasswordAuthentication {
	[CmdletBinding()]
	param(
		[string]$ComputerName="192.168.8.1"
	)
	ssh root@$($ComputerName) "sed -i 's/'\''on/'\''off/' /etc/config/dropbear && cat /etc/config/dropbear"
}

# Send the current user's public key to the device
function Send-PublicKey {
	[CmdletBinding()]
	param (
		[string]$Path="~\.ssh\id_ed25519.pub",
		[string]$ComputerName="192.168.8.1"
	)
	$Target = ssh root@$($ComputerName) "cat /etc/dropbear/authorized_keys"
	if((Get-Content (Resolve-Path $Path)) -in $Target) {
		Write-Host "Key already authorized"
		# If successful, only current user should have SSH access to the device
		Disable-PasswordAuthentication
	}
	else {
		Write-Host "Sending public key for passwordless authentication"
		scp -O (Resolve-Path $Path).Path root@$($ComputerName):/etc/dropbear/authorized_keys
		if($?) {
			Write-Host "Key sent"
			# If successful, only current user should have SSH access to the device
			Disable-PasswordAuthentication
		}
		else {
			Write-Host "Key unable to be sent"
		}
	}
}

# Get the current firmware version from device
function Get-FirmwareVersion {
	[CmdletBinding()]
	param (
		[string]$ComputerName="192.168.8.1"
	)
	return ssh root@$($ComputerName) "cat /etc/glversion"
}

# Push a firmware update binary to the device
function Push-FirmwareUpdate {
	[CmdletBinding()]
	param (
		[string]$Path="~\Secure Setup for GL.iNet BE3600\be3600-4.8.3_release2-965-0131-1769860330.bin",
		[string]$ComputerName="192.168.8.1",
		[System.Windows.Forms.Label]$Label
	)
	$Label.Text = "Copying firmware to $ComputerName..."
	scp -O (Resolve-Path $Path).Path root@$($ComputerName):/tmp/be3600-firmware.bin
	if($?) {
		$Label.Text = "Performing upgrade..."
		ssh root@$($ComputerName) "sysupgrade -v /tmp/be3600-firmware.bin"
		if($?) {
			$Label.Text = "Waiting for connection to $ComputerName"
			Wait-Connection
		}
		else {
			$Label.Text = "SSH failed to connect and initiate upgrade"
		}
	}
	else {
		$Label.Text = "SCP unable to perform transfer"
	}
}

# Create a Panel object
function Create-Panel {
	[CmdletBinding()]
	param(
		[int]$PositionX,
		[int]$PositionY,
		[int]$Width,
		[int]$Height,
		[switch]$AutoSize=$false
	)

	if($AutoSize) {
		$Panel = New-Object System.Windows.Forms.Panel -Property @{Location = "$PositionX,$PositionY"; Size = "$Width,$Height"; BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D; AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink; AutoScroll = $true}
	}
	else {
		$Panel = New-Object System.Windows.Forms.Panel -Property @{Location = "$PositionX,$PositionY"; Size = "$Width,$Height"; BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D}
	}
	return $Panel
}

# Create a Button object
function Create-Button {
	[CmdletBinding()]
	param(
		[int]$PositionX,
		[int]$PositionY,
		[int]$Width,
		[int]$Height,
		[string]$Text
	)
	
	$Button = New-Object System.Windows.Forms.Button -Property @{Location = "$PositionX,$PositionY"; Size = "$Width,$Height"; Text = $Text}
	return $Button
}

# Create a CheckBox object
function Create-CheckBox {
	[CmdletBinding()]
	param(
		[int]$PositionX,
		[int]$PositionY,
		[switch]$Selected=$false
	)

	$CheckBox = New-Object System.Windows.Forms.CheckBox -Property @{Location = "$PositionX,$PositionY"}
	if($Selected) {
		$CheckBox.CheckState = [System.Windows.Forms.CheckState]::Checked
	}
	return $CheckBox
}

# Create a ComboBox object
function Create-ComboBox {
	[CmdletBinding()]
	param(
		[int]$PositionX,
		[int]$PositionY,
		[int]$Width,
		[int]$Height,
		[array]$Items=@("Max","High","Medium","Low"),
		[string]$Selection="Low"
	)

	$ComboBox = New-Object System.Windows.Forms.ComboBox -Property @{Location = "$PositionX,$PositionY"; Size = "$Width,$Height"}
	$ComboBox.Items.AddRange($Items)

	if($ComboBox.Items.Contains($Selection)) {
		#$ComboBox.SelectedIndex = $ComboBox.Items.IndexOf($Selection)
		$ComboBox.SelectedItem = $Selection
		$ComboBox.Text = $Selection
	}

	return $ComboBox
}

# Create a FileDialog object
function Create-FileDialog {
	[CmdletBinding()]
	$Dialog = New-Object System.Windows.Forms.OpenFileDialog
	$Dialog.Filter = "All types (*.*)|*.*"
	$DialogForm = New-Object System.Windows.Forms.Form
	$DialogForm.TopMost = $true
	if($Dialog.ShowDialog($DialogForm) -eq [System.Windows.Forms.DialogResult]::OK) {
		return $Dialog.Filename
	}
}

# Create a Label object
function Create-Label {
	[CmdletBinding()]
	param(
		[int]$PositionX,
		[int]$PositionY,
		[int]$Width,
		[int]$Height,
		[string]$Text
	)

	$Label = New-Object System.Windows.Forms.Label -Property @{Location = "$PositionX,$PositionY"; Size = "$Width,$Height"; Text = $Text}
	return $Label
}

# Create a TextBox object
function Create-TextBox {
	[CmdletBinding()]
	param(
		[int]$PositionX,
		[int]$PositionY,
		[int]$Width,
		[int]$Height,
		[string]$Text
	)

	$TextBox = New-Object System.Windows.Forms.TextBox -Property @{Location = "$PositionX,$PositionY"; Size = "$Width,$Height"; Text = $Text}
	return $TextBox
}

# Get a particular value from the config file
function Get-ConfigValue {
	[CmdletBinding()]
	param(
		[string]$Path,
		[string]$Pattern
	)

	if(Test-Path $Path -PathType Leaf) {
		return [regex]::Match((Get-Content $Path),$Pattern).Groups[1].Value
	}
	else {
		return "Irretrievable Value: Path corrupted or does not exist"
	}
}

# Generate a 16 character WiFi key
function Get-WiFiKey {
    [CmdletBinding()]
    param(
        [switch]$Alnum=$true,
        [switch]$Numeric,
        [switch]$Alpha,
        [int]$Length=16
    )
    
    if($Numeric) {
        return -join (1..$Length | %{(0..9 | %{[string]$_} | Get-Random)})
    }
    if($Alpha) {
        return -join (1..$Length | %{(([int][char]'A'..[int][char]'Z' | %{[char]$_}) + ([int][char]'a'..[int][char]'z' | %{[char]$_})) | Get-Random})
    }
    return -join (1..$Length | %{(0..9 + ([int][char]'A'..[int][char]'Z' | %{[char]$_}) + ([int][char]'a'..[int][char]'z' | %{[char]$_})) | Get-Random})
}

# Generate a MAC Address
function Get-MacAddress {
	[CmdletBinding()]

	$addrBytes = 1..6 | %{-join (1..2 | %{(0..9 + ([int][char]'A'..[int][char]'F' | %{[char]$_})) | Get-Random})}
	return [System.String]::Join(':',$addrBytes)
}

# Get settings from device
function Get-RemoteSettings{
	[CmdletBinding()]
	param(
		[string]$ComputerName="192.168.8.1"
	)
<# 
	It should be noted that there are 2 MAC address values per Wifi interface
	1. The wifi device MAC Address
	2. The advetised interface MAC Address
	3. The factory MAC address which corresponds to the wifi device MAC Address
	This will only return the advertised MAC address, because Aply-Changes will
	 change all three entries to match.
#>
	$RemoteSettings = ssh root@$($ComputerName) "uci show wireless"
	$RemoteSystem = ssh root@$($ComputerName) "uci show system"
	$Ssid2G = [regex]::Match($RemoteSettings,"wifi2g.ssid='([^']*)").Groups[1].Value
	$Key2G = [regex]::Match($RemoteSettings,"wifi2g.key='([^']*)").Groups[1].Value
	$Mac2G = [regex]::Match($RemoteSettings,"wifi2g.macaddr='([^']*)").Groups[1].Value
	$Hidden2G = [int][regex]::Match($RemoteSettings,"wifi2g.hidden='([^']*)").Groups[1].Value
	$TxPower2G = [regex]::Match($RemoteSettings,"wifi0.txpower='([^']*)").Groups[1].Value

	$Ssid5G = [regex]::Match($RemoteSettings,"wifi5g.ssid='([^']*)").Groups[1].Value
	$Key5G = [regex]::Match($RemoteSettings,"wifi5g.key='([^']*)").Groups[1].Value
	$Mac5G = [regex]::Match($RemoteSettings,"wifi5g.macaddr='([^']*)").Groups[1].Value
	$Hidden5G = [int][regex]::Match($RemoteSettings,"wifi5g.hidden='([^']*)").Groups[1].Value
	$TxPower5G = [regex]::Match($RemoteSettings,"wifi1.txpower='([^']*)").Groups[1].Value
	
	$DvcHostName = [regex]::Match($RemoteSystem,"hostname='([^']*)").Groups[1].Value

	return $Ssid2G, $Key2G, $Mac2G, $Hidden2G, $TxPower2G, $Ssid5G, $Key5G, $Mac5G, $Hidden5G, $TxPower5G, $DvcHostName
}

# Load settings from config file
function Load-Settings {
	[CmdletBinding()]
	param(
		[System.Windows.Forms.TextBox]$PathText,
		[System.Windows.Forms.TextBox]$Ssid2G,
		[System.Windows.Forms.TextBox]$Key2G,
		[System.Windows.Forms.TextBox]$Mac2G,
		[System.Windows.Forms.CheckBox]$Hidden2G,
		[System.Windows.Forms.ComboBox]$Tx2G,
		[System.Windows.Forms.TextBox]$Ssid5G,
		[System.Windows.Forms.TextBox]$Key5G,
		[System.Windows.Forms.TextBox]$Mac5G,
		[System.Windows.Forms.CheckBox]$Hidden5G,
		[System.Windows.Forms.ComboBox]$Tx5G,
		[System.Windows.Forms.TextBox]$Hostname
	)
	$InFile = Create-FileDialog
	$PathText.Text = $InFile
	$Settings = Get-Content $InFile
	$TxSet = @{"30" = "Max"; "20" = "High"; "14" = "Medium"; "9" = "Low"}
	
	$Ssid2G.Text = [regex]::Match($Settings,"wifi2g.ssid='([^']*)").Groups[1].Value
	$Key2G.Text = [regex]::Match($Settings,"wifi2g.key='([^']*)").Groups[1].Value
	$Mac2G.Text = [regex]::Match($Settings,"wifi2g.macaddr='([^']*)").Groups[1].Value
	$Hidden2G.Checked = $true
	$Hide = [regex]::Match($Settings,"wifi2g.hidden='([^']*)").Groups[1].Value
	if($Hide -match "0") {
		$Hidden2G.Checked = $false
	}
	$Tx2Key = [regex]::Match($Settings,"wifi0.txpower='([^']*)").Groups[1].Value
	$Tx2G.SelectedItem = $TxSet[$Tx2Key]
	$Ssid5G.Text = [regex]::Match($Settings,"wifi5g.ssid='([^']*)").Groups[1].Value
	$Key5G.Text = [regex]::Match($Settings,"wifi5g.key='([^']*)").Groups[1].Value
	$Mac5G.Text = [regex]::Match($Settings,"wifi5g.macaddr='([^']*)").Groups[1].Value
	$Hidden5G.Checked = $true
	$Hide = [int][regex]::Match($Settings,"wifi5g.hidden='([^']*)").Groups[1].Value
	if($Hide -eq 0) {
		$Hidden5G.Checked = $false
	}
	$Tx5Key = [regex]::Match($Settings,"wifi1.txpower='([^']*)").Groups[1].Value
	$Tx5G.SelectedItem = $TxSet[$Tx5Key]
	$Hostname.Text = [regex]::Match($Settings,"hostname='([^']*)").Groups[1].Value
}

# Prepare setting items for being saved or for being sent to device
function Prep-Items {
	[CmdletBinding()]
	param(
		[string]$Ssid2G,
		[string]$Key2G,
		[string]$Mac2G,
		[string]$Hidden2G,
		[string]$TxPower2G,
		[string]$Ssid5G,
		[string]$Key5G,
		[string]$Mac5G,
		[string]$Hidden5G,
		[string]$TxPower5G,
		[string]$DeviceHostname
	)
	# This is only broken up into several assignments to make it easily human readable
	$Outpt = $Outpt + "system.@system[0].hostname='$DeviceHostname'`n"
	$Outpt = $Outpt + "wireless.wifi2g.ssid='$Ssid2G'`n"
	$Outpt = $Outpt + "wireless.wifi2g.key='$Key2G'`n"
	$Outpt = $Outpt + "wireless.wifi0.macaddr='$Mac2G'`n"
	$Outpt = $Outpt + "wireless.wifi2g.macaddr='$Mac2G'`n"
	$Outpt = $Outpt + "wireless.wifi2g.factory_macaddr='$Mac2G'`n"
	$Outpt = $Outpt + "wireless.wifi2g.hidden='$Hidden2G'`n"
	$Outpt = $Outpt + "wireless.wifi0.txpower='$TxPower2G'`n"
	$Outpt = $Outpt + "wireless.wifi5g.ssid='$Ssid5G'`n"
	$Outpt = $Outpt + "wireless.wifi5g.key='$Key5G'`n"
	$Outpt = $Outpt + "wireless.wifi1.macaddr='$Mac5G'`n"
	$Outpt = $Outpt + "wireless.wifi5g.macaddr='$Mac5G'`n"
	$Outpt = $Outpt + "wireless.wifi5g.factory_macaddr='$Mac5G'`n"
	$Outpt = $Outpt + "wireless.wifi5g.hidden='$Hidden5G'`n"
	$Outpt = $Outpt + "wireless.wifi1.txpower='$TxPower5G'`n"
	
	return $Outpt.Split("`n")
}

# Apply Changes to device
function Apply-Changes {
	[CmdletBinding()]
	param(
		[string]$ComputerName="192.168.8.1",
		[array]$Items
	)
	ssh root@$($ComputerName) "for item in ``opkg list-installed | grep -i 'cloud\|ddns\|mqtt\|adguard\|nas\|astrowarp\|zerotier\|tailscale' | sed 's/ - .*//'```ndo opkg remove $item --force-removal-of-dependent-packages`ndone"
	foreach($item in $Items) {
		if($item.Length -gt 5) {
			ssh root@$($ComputerName) "uci set $item"
		}
	}
	ssh root@$($ComputerName) "uci commit"
	$Confirmation = ssh root@$($ComputerName) "uci show system | grep hostname && uci show wireless | grep 'wifi\(0\|1\|2g\|5g\)\(\.ssid\|\.key\|\.macaddr\|\.factory_macaddr\|\.hidden\|\.txpower\)'"
	foreach($item in $Confirmation) {
		Write-Host $item
	}
}

# Save settings to config file
function Save-Settings {
	[CmdletBinding()]
	param(
		[array]$Items
	)
	$Outpt = ""
	foreach($item in $Items) {
		$OutPt = $OutPt + $item + "`n"
	}
	
	# Create a SaveFileDialog object
	$SaveDialog = New-Object System.Windows.Forms.SaveFileDialog

	$SaveDialog.Title = "Save Current Settings"
	$SaveDialog.InitialDirectory = (Get-Location).Path
	$SaveDialog.Filter = "Config Files (*.config)|*.config|Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
	$SaveDialog.FilterIndex = 1
	$SaveDialog.RestoreDirectory = $true
	$SaveDialog.OverwritePrompt = $true

	$Result = $SaveDialog.ShowDialog()

	if ($Result -eq [System.Windows.Forms.DialogResult]::OK) {
		# Extract the chosen file path
		$OutPath = $SaveDialog.FileName
		Write-Host "Saving file to $OutPath" -ForegroundColor Green
		Out-File -InputObject $Outpt -FilePath $OutPath -Encoding ascii -NoNewLine -Force
	}
}










# Create the application form
function Test-Form {
	$global:form = New-Object System.Windows.Forms.Form -Property @{Text = "Access Point Setup"; Size = New-Object System.Drawing.Size(600,355); FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Fixed3D; StartPosition = "CenterScreen"; ShowInTaskbar = $true}

	$SsidTxt = "SSID:"
	$MacTxt = "MAC Address:"
	$HiddenTxt = "Hidden:"
	$KeyTxt = "Key:"
	$TxTxt = "Transmit Power:"
	$TxSet = @{"30" = "Max"; "20" = "High"; "14" = "Medium"; "9" = "Low"}
	$PanelMargin = 5
	$XMargin = 2
	$StartingY = 10
	$PanelWidth = 165
	$PanelHeight = 255
	$LabelHeight = 13
	$BelowLabel = 3
	$NextEntry = 8
	$TBWidth = 150
	$TBHeight = 20

	# Create 2.4 GHz Wifi Label and Panel
	$Wifi24Label = Create-Label -PositionX 7 -PositionY $StartingY -Width 100 -Height $LabelHeight -Text "Wifi 2.4 GHz"
	$Panel24Y = $Wifi24Label.Location.Y + $Wifi24Label.Height + $BelowLabel
	$Panel24 = Create-Panel -PositionX $PanelMargin -PositionY $Panel24Y -Width $PanelWidth -Height $PanelHeight
	$global:form.Controls.Add($Wifi24Label)
	$global:form.Controls.Add($Panel24)

	# Create 5 GHz Wifi Label and Panel
	$Wifi5Label = Create-Label -PositionX 182 -PositionY $StartingY -Width 100 -Height $LabelHeight -Text "Wifi 5 GHz"
	$Panel5X = $Panel24.Location.X + $Panel24.Width + ($PanelMargin * 2)
	$Panel5Y = $Wifi5Label.Location.Y + $Wifi5Label.Height + $BelowLabel
	$Panel5 = Create-Panel -PositionX $Panel5X -PositionY $Panel5Y -Width $PanelWidth -Height $PanelHeight
	$global:form.Controls.Add($Wifi5Label)
	$global:form.Controls.Add($Panel5)

	# Create message Label
	$MsgY = $Panel24Y + $Panel24.Height + $NextEntry
	$MsgWidth = $global:form.Width - (2 * $XMargin)
	$global:MsgLabel = Create-Label -PositionX $XMargin -PositionY $MsgY -Width $MsgWidth -Height $LabelHeight -Text "Welcome to the Slate7 setup tool."
	$global:MsgLabel.ForeColor = "Blue"
	$global:form.Controls.Add($global:MsgLabel)

	# Create firmware interface Label and TextBox
	$FirmX = $Panel5.Location.X + $Panel5.Width + (10 * $XMargin)
	$FirmLabel = Create-Label -PositionX $FirmX -PositionY $StartingY -Width 100 -Height $LabelHeight -Text "Firmware File:"
	$FirmPathY = $FirmLabel.Location.Y + $FirmLabel.Height + $BelowLabel
	$FirmPathWidth = $global:form.Width - ($FirmX + (20 * $XMargin))
	$FirmPath = Create-TextBox -PositionX $FirmX -PositionY $FirmPathY -Width $FirmPathWidth -Height $TBHeight
	$global:form.Controls.Add($FirmLabel)
	$global:form.Controls.Add($FirmPath)
	
	# Create firmware file Browse Button
	$FirmButtonY = $FirmPath.Location.Y + $FirmPath.Height + $BelowLabel
	$FirmButton = Create-Button -PositionX $FirmX -PositionY $FirmButtonY -Width 50 -Height 20 -Text "Browse"
	$FirmButton.Add_Click({
		$FirmPath.Text = Create-FileDialog
	})
	$global:form.Controls.Add($FirmButton)
	
	# Create firmware file Update Button
	$UpdateX = $FirmX + $FirmButton.Width + (5 * $XMargin)
	$UpdateFirm = Create-Button -PositionX $UpdateX -PositionY $FirmButtonY -Width 125 -Height 20 -Text "Update Firmware"
	$UpdateFirm.Add_Click({
		if($FirmPath.Text) {
			Push-FirmwareUpdate -Path $FirmPath.Text -Label $global:MsgLabel
		}
		else {
			Push-FirmwareUpdate -Label $global:MsgLabel
		}
	})
	$global:form.Controls.Add($UpdateFirm)
	
	# Create firmware version Label
	$VersionText = Get-FirmwareVersion
	$VersionY = $FirmButton.Location.Y + $FirmButton.Height + $NextEntry
	$VersionLabel = Create-Label -PositionX $FirmX -PositionY $VersionY -Width $FirmPathWidth -Height $LabelHeight -Text "Current Firmware Version: $VersionText"
	$VersionLabel.ForeColor = "Blue"
	$global:form.Controls.Add($VersionLabel)

	# Create Configuration interface Label and TextBox
	$ConfigLabelX = $Panel5.Location.X + $Panel5.Width + (10 * $XMargin)
	$ConfigLabelY = $VersionLabel.Location.Y + $VersionLabel.Height + $NextEntry
	$ConfigLabel = Create-Label -PositionX $ConfigLabelX -PositionY $ConfigLabelY -Width 100 -Height $LabelHeight -Text "Configuration File:"
	$ConfigPathY = $ConfigLabel.Location.Y + $ConfigLabel.Height + $BelowLabel
	$ConfigPathWidth = $global:form.Width - ($ConfigLabelX + (20 * $XMargin))
	$ConfigPath = Create-TextBox -PositionX $ConfigLabelX -PositionY $ConfigPathY -Width $ConfigPathWidth -Height $TBHeight
	$global:form.Controls.Add($ConfigLabel)
	$global:form.Controls.Add($ConfigPath)

	# Create config file Browse Button
	$ConfigButtonY = $ConfigPath.Location.Y + $ConfigPath.Height + $BelowLabel
	$ConfigButton = Create-Button -PositionX $ConfigLabelX -PositionY $ConfigButtonY -Width 50 -Height 20 -Text "Browse"
	$ConfigButton.Add_Click({
		Load-Settings -PathText $ConfigPath -Ssid2G $Ssid24TextBox -Key2G $Key24TextBox -Mac2G $Mac24TextBox -Hidden2G $Hidden24CheckBox -Tx2G $Tx24ComboBox -Ssid5G $Ssid5TextBox -Key5G $Key5TextBox -Mac5G $Mac5TextBox -Hidden5G $Hidden5CheckBox -Tx5G $Tx5ComboBox -Hostname $HostTextBox
	})
	$global:form.Controls.Add($ConfigButton)

	# Create config file Save Button
	$SaveX = $ConfigLabelX + $ConfigButton.Width + (5 * $XMargin)
	$SaveConfig = Create-Button -PositionX $SaveX -PositionY $ConfigButtonY -Width 125 -Height 20 -Text "Save Configurations"
	$SaveConfig.Add_Click({
		$H2G = "1"
		if (-not $Hidden24CheckBox.Checked) {
			$H2G = "0"
		}
		$Tx2G = [string]$TxSet.GetEnumerator().Where({$_.Value -match $Tx24ComboBox.SelectedItem}).Key
		$H5G = "1"
		if (-not $Hidden5CheckBox.Checked) {
			$H5G = "0"
		}
		$Tx5G = [string]$TxSet.GetEnumerator().Where({$_.Value -match $Tx5ComboBox.SelectedItem}).Key
		$InItems = Prep-Items -Ssid2G $Ssid24TextBox.Text -Key2G $Key24TextBox.Text -Mac2G $Mac24TextBox.Text -Hidden2G $H2G -TxPower2G $Tx2G -Ssid5G $Ssid5TextBox.Text -Key5G $Key5TextBox.Text -Mac5G $Mac5TextBox.Text -Hidden5G $H5G -TxPower5G $Tx5G -DeviceHostname $HostTextBox.Text
		Save-Settings -Items $InItems
	})
	$global:form.Controls.Add($SaveConfig)

	# Create Apply Button
	$ApplyY = $ConfigButton.Location.Y + $ConfigButton.Height + $NextEntry
	$ApplyButton = Create-Button -PositionX $ConfigLabelX -PositionY $ApplyY -Width 50 -Height 20 -Text "Apply"
	$ApplyButton.Add_Click({
		$global:MsgLabel.Text = "Applying changes..."
		$H2G = "1"
		if (-not $Hidden24CheckBox.Checked) {
			$H2G = "0"
		}
		$Tx2G = [string]$TxSet.GetEnumerator().Where({$_.Value -match $Tx24ComboBox.SelectedItem}).Key
		$H5G = "1"
		if (-not $Hidden5CheckBox.Checked) {
			$H5G = "0"
		}
		$Tx5G = [string]$TxSet.GetEnumerator().Where({$_.Value -match $Tx5ComboBox.SelectedItem}).Key
		$InItems = Prep-Items -Ssid2G $Ssid24TextBox.Text -Key2G $Key24TextBox.Text -Mac2G $Mac24TextBox.Text -Hidden2G $H2G -TxPower2G $Tx2G -Ssid5G $Ssid5TextBox.Text -Key5G $Key5TextBox.Text -Mac5G $Mac5TextBox.Text -Hidden5G $H5G -TxPower5G $Tx5G -DeviceHostname $HostTextBox.Text
		Apply-Changes -Items $InItems
		$global:MsgLabel.Text = "Finished applying changes"
	})
	$global:form.Controls.Add($ApplyButton)

	# Create Load Remote Settings Button
	$LoadX = $ApplyButton.Location.X + $ApplyButton.Width + (5 * $XMargin)
	$LoadRemote = Create-Button -PositionX $LoadX -PositionY $ApplyY -Width 125 -Height 20 -Text "Load Remote Settings"
	$LoadRemote.Add_Click({
		$global:MsgLabel.Text = "Loading settings from the device..."
		$RemoteSettings = Get-RemoteSettings
		$Ssid24TextBox.Text = $RemoteSettings[0]
		$Key24TextBox.Text = $RemoteSettings[1]
		$Mac24TextBox.Text = $RemoteSettings[2]
		if($RemoteSettings[3] -eq 1) {
			$Hidden24CheckBox.Checked = $true
		}
		else {
			$Hidden24CheckBox.Checked = $false
		}
		$Tx24ComboBox.SelectedIndex = $Tx24ComboBox.Items.IndexOf($TxSet[$RemoteSettings[4]])
		
		$Ssid5TextBox.Text = $RemoteSettings[5]
		$Key5TextBox.Text = $RemoteSettings[6]
		$Mac5TextBox.Text = $RemoteSettings[7]
		if($RemoteSettings[8] -eq 1) {
			$Hidden5CheckBox.Checked = $true
		}
		else {
			$Hidden5CheckBox.Checked = $false
		}
		$Tx5ComboBox.SelectedIndex = $Tx5ComboBox.Items.IndexOf($TxSet[$RemoteSettings[9]])
		$HostTextBox.text = $RemoteSettings[10]
		$global:MsgLabel.Text = "Finished loading settings"
	})
	$global:form.Controls.Add($LoadRemote)
	
	# Create device hostname Label and TexBox
	$HostLabelX = $Panel5.Location.X + $Panel5.Width + (10 * $XMargin)
	$HostLabelY = $ApplyButton.Location.Y + $ApplyButton.Height + $NextEntry
	$HostLabel = Create-Label -PositionX $HostLabelX -PositionY $HostLabelY -Width 100 -Height $LabelHeight -Text "Device Hostname:"
	$HostWidth = $global:form.Width - ($HostLabelX + (20 * $XMargin))
	$HostTextY = $HostLabel.Location.Y + $HostLabel.Height + $BelowLabel
	$HostTextBox = Create-TextBox -PositionX $HostLabelX -PositionY $HostTextY -Width $HostWidth -Height $TBHeight
	$global:form.Controls.Add($HostLabel)
	$global:form.Controls.Add($HostTextBox)

	# Create 2.4 GHz SSID Label
	$Ssid24Label = Create-Label -PositionX $XMargin -PositionY $StartingY -Width 35 -Height $LabelHeight -Text $SsidTxt
	$Panel24.Controls.Add($SSID24Label)

	# Create 2.4 GHz Wifi SSID TextBox
	if(Test-Path -Path .\result_config) {
		$Ssid24 = Get-ConfigValue .\result_config "0.ssid='([^']*)'"
	}
	else {
		$Ssid24 = "Hotspot1"
	}
	$Ssid24Y = $Ssid24Label.Location.Y + $Ssid24Label.Height + $BelowLabel
	$Ssid24TextBox = Create-TextBox -PositionX $XMargin -PositionY $Ssid24Y -Width $TBWidth -Height $TBHeight -Text $Ssid24
	$Panel24.Controls.Add($Ssid24TextBox)

	# Create 2.4 GHz Wifi security key Label
	$Key24Y = $Ssid24TextBox.Location.Y + $Ssid24TextBox.Height + $NextEntry
	$Key24Label = Create-Label -PositionX $XMargin -PositionY $Key24Y -Width 35 -Height $LabelHeight -Text $KeyTxt
	$Panel24.Controls.Add($Key24Label)

	# Create 2.4 GHz Wifi security key TextBox
	if(Test-Path -Path .\result_config) {
		$Key24 = Get-ConfigValue .\result_config "0.key='([^']*)'"
	}
	else {
		$Key24 = Get-WiFiKey
	}
	$Key24TextBoxY = $Key24Label.Location.Y + $Key24Label.Height + $BelowLabel
	$Key24TextBox = Create-TextBox -PositionX $XMargin -PositionY $Key24TextBoxY -Width $TBWidth -Height $TBHeight -Text $Key24
	$Panel24.Controls.Add($Key24TextBox)

	# Create 2.4 GHz Wifi security key generation Button
	$Key24ButtonY = $Key24TextBox.Location.Y + $Key24TextBox.Height + $BelowLabel
	$Key24ButtonX = ($XMargin + ($Key24TextBox.Width - 100)/2)
	$Key24Button = Create-Button -PositionX $Key24ButtonX -PositionY $Key24ButtonY -Width 100 -Height $TBHeight -Text "Generate Key"
	$Key24Button.Add_Click({$Key24TextBox.Text = Get-WiFiKey})
	$Panel24.Controls.Add($Key24Button)

	# Create 2.4 GHz Wifi MAC address Label
	$Mac24Y = $Key24Button.Location.Y + $Key24Button.Height + $NextEntry
	$Mac24Label = Create-Label -PositionX $XMargin -PositionY $Mac24Y -Width 90 -Height $LabelHeight -Text $MacTxt
	$Panel24.Controls.Add($Mac24Label)

	# Create 2.5 GHz Wifi MAC address TextBox
	if(Test-Path -Path .\result_config) {
		$Mac24 = Get-ConfigValue .\result_config "0.macaddress='([^']*)'"
	}
	else {
		$Mac24 = Get-MacAddress
	}
	$Mac24TextBoxY = $Mac24Label.Location.Y + $Mac24Label.Height + $BelowLabel
	$Mac24TextBox = Create-TextBox -PositionX $XMargin -PositionY $Mac24TextBoxY -Width $TBWidth -Height $TBHeight -Text $Mac24
	$Panel24.Controls.Add($Mac24TextBox)

	# Create 2.4 GHz Wifi MAC address generation Button
	$Mac24ButtonX = ($XMargin + ($Mac24TextBox.Width - 100)/2)
	$Mac24ButtonY = $Mac24TextBox.Location.Y + $TBHeight + $BelowLabel
	$Mac24Button = Create-Button -PositionX $Mac24ButtonX -PositionY $Mac24ButtonY -Width 100 -Height $TBHeight -Text "Generate MAC"
	$Mac24Button.Add_Click({$Mac24TextBox.Text = Get-MacAddress})
	$Panel24.Controls.Add($Mac24Button)

	# Create 2.4 GHz Wifi hidden property Label
	$Hidden24Y = $Mac24Button.Location.Y + $Mac24Button.Height + $NextEntry
	$Hidden24Label = Create-Label -PositionX $XMargin -PositionY $Hidden24Y -Width 45 -Height $LabelHeight -Text $HiddenTxt
	$Panel24.Controls.Add($Hidden24Label)

	# Create 2.4 GHz Wifi hidden property CheckBox
	$Hidden24CheckBox = Create-CheckBox -PositionX ($Hidden24Label.Width + $XMargin) -PositionY ($Hidden24Y - $BelowLabel) -Selected
	$Panel24.Controls.Add($Hidden24CheckBox)

	# Create 2.4 GHz Wifi transmt power Label
	$Tx24Y = $Hidden24CheckBox.Location.Y + $Hidden24CheckBox.Height + $NextEntry
	$Tx24Label = Create-Label -PositionX $XMargin -PositionY $Tx24Y -Width 90 -Height 15 -Text $TxTxt
	$Panel24.Controls.Add($Tx24Label)

	# Create 2.4 GHz Wifi transmit power ComboBox (dropdown menu)
	$Tx24X = 2 * $XMargin + $Tx24Label.Width
	$Tx24ComboBox = Create-ComboBox -PositionX $Tx24X -PositionY $Tx24Y -Width 60 -Height $TBHeight
	$Panel24.Controls.Add($Tx24ComboBox)

	# Create 5 GHz Wifi SSID Label
	$Ssid5Label = Create-Label -PositionX $XMargin -PositionY $StartingY -Width 35 -Height $LabelHeight -Text $SsidTxt
	$Panel5.Controls.Add($Ssid5Label)

	# Create 5 GHz Wifi SSID TextBox
	if(Test-Path -Path .\result_config) {
		$Ssid5 = Get-ConfigValue .\result_config "1.ssid='([^']*)'"
	}
	else {
		$Ssid5 = "Hotspot2"
	}
	$Ssid5Y = $Ssid5Label.Location.Y + $Ssid5Label.Height + $BelowLabel
	$Ssid5TextBox = Create-TextBox -PositionX $XMargin -PositionY $Ssid5Y -Width $TBWidth -Height $TBHeight -Text $Ssid5
	$Panel5.Controls.Add($Ssid5TextBox)

	# Create 5 GHz Wifi security key Label
	$Key5Y = $Ssid5TextBox.Location.Y + $Ssid5TextBox.Height + $NextEntry
	$Key5Label = Create-Label -PositionX $XMargin -PositionY $Key5Y -Width 35 -Height $LabelHeight -Text $KeyTxt
	$Panel5.Controls.Add($Key5Label)

	# Create 5 GHz Wifi security key TextBox
	if(Test-Path -Path .\result_config) {
		$Key5 = Get-ConfigValue .\result_config "1.key='([^']*)'"
	}
	else {
		$Key5 = Get-WiFiKey
	}
	$Key5TextBoxY = $Key5Label.Location.Y + $Key5Label.Height + $BelowLabel
	$Key5TextBox = Create-TextBox -PositionX $XMargin -PositionY $Key5TextBoxY -Width $TBWidth -Height $TBHeight -Text $Key5
	$Panel5.Controls.Add($Key5TextBox)

	# Create 5 GHz Wifi security key generation Button
	$Key5ButtonY = $Key5TextBox.Location.Y + $Key5TextBox.Height + $BelowLabel
	$Key5ButtonX = ($XMargin + ($Key5TextBox.Width - 100)/2)
	$Key5Button = Create-Button -PositionX $Key5ButtonX -PositionY $Key5ButtonY -Width 100 -Height $TBHeight -Text "Generate Key"
	$Key5Button.Add_Click({$Key5TextBox.Text = Get-WiFiKey})
	$Panel5.Controls.Add($Key5Button)

	# Create 5 GHz Wifi MAC address Label
	$Mac5Y = $Key5Button.Location.Y + $Key5Button.Height + $NextEntry
	$Mac5Label = Create-Label -PositionX $XMargin -PositionY $Mac5Y -Width 90 -Height $LabelHeight -Text $MacTxt
	$Panel5.Controls.Add($Mac5Label)

	# Create 5 GHz Wifi MAC address TextBox
	if(Test-Path -Path .\result_config) {
		$Mac5 = Get-ConfigValue .\result_config "1.macaddress='([^']*)'"
	}
	else {
		$Mac5 = Get-MacAddress
	}
	$Mac5TextBoxY = $Mac5Label.Location.Y + $Mac5Label.Height + $BelowLabel
	$Mac5TextBox = Create-TextBox -PositionX $XMargin -PositionY $Mac5TextBoxY -Width $TBWidth -Height $TBHeight -Text $Mac5
	$Panel5.Controls.Add($Mac5TextBox)

	# Create 5 GHz Wifi MAC address generation Button
	$Mac5ButtonX = ($XMargin + ($Mac5TextBox.Width - 100)/2)
	$Mac5ButtonY = $Mac5TextBox.Location.Y + $TBHeight + $BelowLabel
	$Mac5Button = Create-Button -PositionX $Mac5ButtonX -PositionY $Mac5ButtonY -Width 100 -Height $TBHeight -Text "Generate MAC"
	$Mac5Button.Add_Click({$Mac5TextBox.Text = Get-MacAddress})
	$Panel5.Controls.Add($Mac5Button)

	# Create 5 GHz Wifi hidden property Label
	$Hidden5Y = $Mac5Button.Location.Y + $Mac5Button.Height + $NextEntry
	$Hidden5Label = Create-Label -PositionX $XMargin -PositionY $Hidden5Y -Width 45 -Height $LabelHeight -Text $HiddenTxt
	$Panel5.Controls.Add($Hidden5Label)

	# Create 5 GHz Wifi hidden property CheckBox
	$Hidden5CheckBox = Create-CheckBox -PositionX ($Hidden5Label.Width + $XMargin) -PositionY ($Hidden5Y - $BelowLabel) -Selected
	$Panel5.Controls.Add($Hidden5CheckBox)

	# Create 5 GHz Wifi transmit power Label
	$Tx5Y = $Hidden5CheckBox.Location.Y + $Hidden5CheckBox.Height + $NextEntry
	$Tx5Label = Create-Label -PositionX $XMargin -PositionY $Tx5Y -Width 88 -Height $LabelHeight -Text $TxTxt
	$Panel5.Controls.Add($Tx5Label)

	# Create 5 GHz Wifi transmit power ComboBox
	$Tx5X = 2 * $XMargin + $Tx5Label.Width
	$Tx5ComboBox = Create-ComboBox -PositionX $Tx5X -PositionY $Tx5Y -Width 60 -Height $TBHeight
	$Panel5.Controls.Add($Tx5ComboBox)

	# Display Window
	[void]$global:form.ShowDialog()
}

Get-SshSetup
Wait-Connection
Get-PublicKey
Send-PublicKey
Test-Form