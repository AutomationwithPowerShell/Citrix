#==============================================================================================
# Modified On: 03/2025
# Reference/Author : https://blog.sachathomet.ch/2014/11/30/xendesktop-and-xenapp-7-x-healthcheck-oops-i-did-it-again/
# Modified:Naveen Jogga Ram
# File name: XA-and-XD-HealthCheck.ps1
#
# Description: This script checks a Citrix XenDesktop and/or XenApp 7.x Farm
# It generates a HTML output File which will bef sent as Email.
#
#
# Prerequisite: Config file, a XenDesktop Controller with according privileges necessary 
# Config file:  In order for the script to work properly, it needs a configuration file.
#               This has the same name as the script, with extension _Parameters.
#               The script name can't contain any another point, even with a version.
#               Example: Script = "XenDesktop-HealthCheck.ps1", Config = "XenDesktop-HealthCheck_Parameters.xml"
#
# Call by : Manual or by Scheduled Task, e.g. once a day
#
#==============================================================================================

#Don't change below here if you don't know what you are doing ... 
#==============================================================================================
# Load only the snap-ins, which are used
#Set-ExecutionPolicy -ExecutionPolicy RemoteSigned 
if ((Get-PSSnapin "Citrix.Broker.Admin.*" -EA silentlycontinue) -eq $null) {
try { Add-PSSnapin Citrix.Broker.Admin.* -ErrorAction Stop }
catch { write-error "Error Get-PSSnapin Citrix.Broker.Admin.* Powershell snapin"; Return }
}

#==============================================================================================
# Import Variables from XML:

If (![string]::IsNullOrEmpty($hostinvocation)) {
	[string]$Global:ScriptPath = [System.IO.Path]::GetDirectoryName([System.Windows.Forms.Application]::ExecutablePath)
	[string]$Global:ScriptFile = [System.IO.Path]::GetFileName([System.Windows.Forms.Application]::ExecutablePath)
	[string]$global:ScriptName = [System.IO.Path]::GetFileNameWithoutExtension([System.Windows.Forms.Application]::ExecutablePath)
} ElseIf ($Host.Version.Major -lt 3) {
	[string]$Global:ScriptPath = Split-Path -parent $MyInvocation.MyCommand.Definition
	[string]$Global:ScriptFile = Split-Path -Leaf $script:MyInvocation.MyCommand.Path
	[string]$global:ScriptName = $ScriptFile.Split('.')[0].Trim()
} Else {
	[string]$Global:ScriptPath = $PSScriptRoot
	[string]$Global:ScriptFile = Split-Path -Leaf $PSCommandPath
	[string]$global:ScriptName = $ScriptFile.Split('.')[0].Trim()
}

Set-StrictMode -Version Latest

# Import parameter file
$Global:ParameterFile = $ScriptName + "_Parameters.xml"
$Global:ParameterFilePath = $ScriptPath
[xml]$cfg = Get-Content ($ParameterFilePath + "\" + $ParameterFile) # Read content of XML file

# Import variables
Function New-XMLVariables {
	# Create a variable reference to the XML file
	$cfg.Settings.Variables.Variable | foreach {
		# Set Variables contained in XML file
		$VarValue = $_.Value
		$CreateVariable = $True # Default value to create XML content as Variable
		switch ($_.Type) {
			# Format data types for each variable 
			'[string]' { $VarValue = [string]$VarValue } # Fixed-length string of Unicode characters
			'[char]' { $VarValue = [char]$VarValue } # A Unicode 16-bit character
			'[byte]' { $VarValue = [byte]$VarValue } # An 8-bit unsigned character
            '[bool]' { If ($VarValue.ToLower() -eq 'false'){$VarValue = [bool]$False} ElseIf ($VarValue.ToLower() -eq 'true'){$VarValue = [bool]$True} } # An boolean True/False value
			'[int]' { $VarValue = [int]$VarValue } # 32-bit signed integer
			'[long]' { $VarValue = [long]$VarValue } # 64-bit signed integer
			'[decimal]' { $VarValue = [decimal]$VarValue } # A 128-bit decimal value
			'[single]' { $VarValue = [single]$VarValue } # Single-precision 32-bit floating point number
			'[double]' { $VarValue = [double]$VarValue } # Double-precision 64-bit floating point number
			'[DateTime]' { $VarValue = [DateTime]$VarValue } # Date and Time
			'[Array]' { $VarValue = [Array]$VarValue.Split(',') } # Array
			'[Command]' { $VarValue = Invoke-Expression $VarValue; $CreateVariable = $False } # Command
		}
		If ($CreateVariable) { New-Variable -Name $_.Name -Value $VarValue -Scope $_.Scope -Force }
	}
}

New-XMLVariables

$scriptstart = Get-Date


$PvsWriteMaxSizeInGB = $PvsWriteMaxSize * 1Gb

ForEach ($DeliveryController in $DeliveryControllers){
    If ($DeliveryController -ieq "LocalHost"){
        $DeliveryController = [System.Net.DNS]::GetHostByName('').HostName
    }
    If (Test-Connection $DeliveryController) {
        $AdminAddress = $DeliveryController
        break
    }
}

$ReportDate = (Get-Date -UFormat "%A, %d. %B %Y %R")


$currentDir = Split-Path $MyInvocation.MyCommand.Path
$outputpath = Join-Path $currentDir "" #add here a custom output folder if you wont have it on the same directory
$outputdate = Get-Date -Format 'yyyyMMddHHmm'
$logfile = Join-Path $outputpath ("CTXXDHealthCheck.log")
$resultsHTM = Join-Path $outputpath ("CTXXDHealthCheck.htm") #add $outputdate in filename if you like
  
#Header for Table "XD/XA Controllers" Get-BrokerController
$XDControllerFirstheaderName = "ControllerServer"
$XDControllerHeaderNames = "Ping", 	"State","DesktopsRegistered", "CitrixServices"
$XDControllerHeaderWidths = "2",	"2", 	"4", 				   "4"				
$XDControllerTableWidth= 1200
foreach ($disk in $diskLettersControllers)
{
    $XDControllerHeaderNames += "$($disk)Freespace"
    $XDControllerHeaderWidths += "4"
}
$XDControllerHeaderNames +=  	"AvgCPU", 	"MemUsg", 	"Uptime"
$XDControllerHeaderWidths +=    "4",		"4",		"6"


####Citrix Storefront Server

#Header for Table "XD/XA Controllers" Get-SfDetail
$SFControllerFirstheaderName = "StorefrontServer"
$SFControllerHeaderNames = "Ping",  "CitrixServices"
$SFControllerHeaderWidths = "2", 	 "4"				
$SFControllerTableWidth= 1200
foreach ($disk in $diskLettersControllers)
{
    $SFControllerHeaderNames += "$($disk)Freespace"
    $SFControllerHeaderWidths += "4"
}
$SFControllerHeaderNames +=  	"AvgCPU", 	"MemUsg", 	"Uptime"
$SFControllerHeaderWidths +=    "4",		"4",		"6"



#Header for Table "CTX Licenses" Get-BrokerController
$CTXLicFirstheaderName = "LicenseServer"
$CTXLicHeaderNames = "LicenseName", 	"Count","InUse", 	"Available"
$CTXLicHeaderWidths = "4",	"2", 	"2", 					"2"
$CTXLicTableWidth= 1200
 
#Header for Table "DeliveryGroups" Get-BrokerDesktopGroup
$AssigmentFirstheaderName = "DeliveryGroup"
$vAssigmentHeaderNames = 	"PublishedName","TotalMachines", "DesktopsInUse","DesktopsFree","DesktopsUnregistered","DesktopKind" #, "SessionSupport" #,"MaintenanceMode" , "MaintenanceMode" , "ShutdownAfterUse",  "MinimumFunctionalLevel",,"DesktopsAvailable"
$vAssigmentHeaderWidths = 	"6", 			"3", 			"3", 	              "3", 		      "3", 			"3" #, 					"4" 		#	,"4"  , 			"4"			 "2", 			"2"
$Assigmenttablewidth = 1200
  
#Header for Table "VDI Checks" Get-BrokerMachine
$VDIfirstheaderName = "VDIName"

$VDIHeaderNames = "CatalogName","DeliveryGroup","PowerState",  "MaintMode","RegState","VDAVersion" #, 	"Uptime", 	  "WriteCacheType", "WriteCacheSize", "Tags", "HostedOn", "displaymode", "OSBuild","Ping",,"AssociatedUserNames"
$VDIHeaderWidths = "7",         "7",		    "3",           "3", 	    "3", 		"3" #,  "4", 			  "4",			  "4",			  "4", "4", "4", 		"4", 				"4",			  "4"

$VDItablewidth = 1200
  
#Header for Table "XenApp Checks" Get-BrokerMachine
$XenAppfirstheaderName = "XenApp-Server"
$XenAppHeaderNames = "CatalogName", "DeliveryGroup", "Ping","Serverload", "MaintMode","Uptime", 	"RegState", "VDAVersion" #,"SessionSupport" #, "Spooler",  	"CitrixPrint", "OSBuild"
$XenAppHeaderWidths = "7", 			"7", 			 "2", 	"2", 	      "2", 		  "2", 		     "2", 		 "3"  #,"4"  #, 		"4", 		 	"4", 		"4"
foreach ($disk in $diskLettersWorkers)
{
    $XenAppHeaderNames += "$($disk)Freespace"
    $XenAppHeaderWidths += "3"
}

if ($ShowConnectedXenAppUsers -eq "1") { 

	$XenAppHeaderNames += "AvgCPU", 	"MemUsg", 	"ActiveSessions"#, "WriteCacheType", "WriteCacheSize", "Tags","HostedOn",,  "ConnectedUsers" 
	$XenAppHeaderWidths +="2",		"2",			  "4" #,			"4",			"4",			"4","4",			"4"
}
else { 
	$XenAppHeaderNames += "AvgCPU", 	"MemUsg", 	"ActiveSessions" #, "WriteCacheType", "WriteCacheSize", "Tags","HostedOn"
	$XenAppHeaderWidths +="2",		"2",		"4" #,			  "4",			"4",			"4","4"

}

$XenApptablewidth = 1200
  
#==============================================================================================
#log function
function LogMe() {
Param(
[parameter(Mandatory = $true, ValueFromPipeline = $true)] $logEntry,
[switch]$display,
[switch]$error,
[switch]$warning,
[switch]$progress
)
  
if ($error) { $logEntry = "[ERROR] $logEntry" ; Write-Host "$logEntry" -Foregroundcolor Red }
elseif ($warning) { Write-Warning "$logEntry" ; $logEntry = "[WARNING] $logEntry" }
elseif ($progress) { Write-Host "$logEntry" -Foregroundcolor Green }
elseif ($display) { Write-Host "$logEntry" }
  
#$logEntry = ((Get-Date -uformat "%D %T") + " - " + $logEntry)
$logEntry | Out-File $logFile -Append
}
  
#==============================================================================================
function Ping([string]$hostname, [int]$timeout = 200) {
$ping = new-object System.Net.NetworkInformation.Ping #creates a ping object
try { $result = $ping.send($hostname, $timeout).Status.ToString() }
catch { $result = "Failure" }
return $result
}
#==============================================================================================
# The function will check the processor counter and check for the CPU usage. Takes an average CPU usage for 5 seconds. It check the current CPU usage for 5 secs.
Function CheckCpuUsage() 
{ 
	param ($hostname)
	Try { $CpuUsage=(get-counter -ComputerName $hostname -Counter "\Processor(_Total)\% Processor Time" -SampleInterval 1 -MaxSamples 5 -ErrorAction Stop | select -ExpandProperty countersamples | select -ExpandProperty cookedvalue | Measure-Object -Average).average
    	$CpuUsage = [math]::round($CpuUsage, 1); return $CpuUsage
	} Catch { "Error returned while checking the CPU usage. Perfmon Counters may be fault" | LogMe -error; return 101 } 
}
#============================================================================================== 
# The function check the memory usage and report the usage value in percentage
Function CheckMemoryUsage() 
{ 
	param ($hostname)
    Try 
	{   $SystemInfo =Invoke-Command -ComputerName $hostname -ScriptBlock{Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop | Select-Object TotalVisibleMemorySize, FreePhysicalMemory}   # (Get-WmiObject -computername "Computername" -Class Win32_OperatingSystem -ErrorAction Stop | Select-Object TotalVisibleMemorySize, FreePhysicalMemory)
    	$TotalRAM = $SystemInfo.TotalVisibleMemorySize/1MB 
    	$FreeRAM = $SystemInfo.FreePhysicalMemory/1MB 
    	$UsedRAM = $TotalRAM - $FreeRAM 
    	$RAMPercentUsed = ($UsedRAM / $TotalRAM) * 100 
    	$RAMPercentUsed = [math]::round($RAMPercentUsed, 2);
    	return $RAMPercentUsed
	} Catch { "Error returned while checking the Memory usage. Perfmon Counters may be fault" | LogMe -error; return 101 } 
}
#==============================================================================================

# The function check the HardDrive usage and report the usage value in percentage and free space
Function CheckHardDiskUsage() 
{ 
	param ($hostname)
    Try 
	{   
    	$HardDisk = $null
		$HardDisk = Invoke-Command -ComputerName $hostname  -ScriptBlock{(Get-WmiObject Win32_LogicalDisk |?{$_.DeviceID -eq "C:"})} #Get-WmiObject Win32_LogicalDisk -ComputerName $hostname -Filter "DeviceID='$deviceID'" -ErrorAction Stop | Select-Object Size,FreeSpace
        if ($HardDisk -ne $null)
		{
		$DiskTotalSize = $HardDisk.Size 
        $DiskFreeSpace = $HardDisk.FreeSpace 
        $frSpace=[Math]::Round(($DiskFreeSpace/1073741824),2)
		$PercentageDS = (($DiskFreeSpace / $DiskTotalSize ) * 100); $PercentageDS = [math]::round($PercentageDS, 2)
		
		Add-Member -InputObject $HardDisk -MemberType NoteProperty -Name PercentageDS -Value $PercentageDS
		Add-Member -InputObject $HardDisk -MemberType NoteProperty -Name frSpace -Value $frSpace
		} 
		
    	return $HardDisk
	} Catch { "Error returned while checking the Hard Disk usage. Perfmon Counters may be fault" | LogMe -error; return $null } 
}


#==============================================================================================
Function writeHtmlHeader
{
param($title, $fileName)
$date = $ReportDate
$head = @"
<html>
<head>
<meta http-equiv='Content-Type' content='text/html; charset=iso-8859-1'>
<title>$title</title>
<STYLE TYPE="text/css">
<!--
td {
font-family: Tahoma;
font-size: 11px;
border-top: 1px solid #999999;
border-right: 1px solid #999999;
border-bottom: 1px solid #999999;
border-left: 1px solid #999999;
padding-top: 0px;
padding-right: 0px;
padding-bottom: 0px;
padding-left: 0px;
overflow: hidden;
}
body {
margin-left: 5px;
margin-top: 5px;
margin-right: 0px;
margin-bottom: 10px;
table {
table-layout:fixed;
border: thin solid #000000;
}
-->
</style>
</head>
<body>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='48' align='center' valign="middle">
<font face='tahoma' color='#003399' size='4'>
<strong>$title - $date</strong></font>
</td>
</tr>
</table>
"@
$head | Out-File $fileName
}
  
# ==============================================================================================
Function writeTableHeader
{
param($fileName, $firstheaderName, $headerNames, $headerWidths, $tablewidth)
$tableHeader = @"
  
<table width='$tablewidth'><tbody>
<tr bgcolor=#CCCCCC>
<td width='6%' align='left'><strong>$firstheaderName</strong></td>      
"@ ##commented on 17th feb
  
$i = 0
while ($i -lt $headerNames.count) {
$headerName = $headerNames[$i]
$headerWidth = $headerWidths[$i]
$tableHeader += "<td width='" + $headerWidth + "%' align='Left'><strong>$headerName</strong></td>"
$i++
}
  
$tableHeader += "</tr>"
  
$tableHeader | Out-File $fileName -append
}
  
# ==============================================================================================
Function writeTableFooter
{
param($fileName)
"</table><br/>"| Out-File $fileName -append
}
  
#==============================================================================================
Function writeData
{
param($data, $fileName, $headerNames)

$tableEntry  =""  
$data.Keys | sort | foreach {
$tableEntry += "<tr>"
$computerName = $_
$tableEntry += ("<td bgcolor='#CCCCCC' align=Left><font color='#003399'>$computerName</font></td>")
#$data.$_.Keys | foreach {
$headerNames | foreach {
#"$computerName : $_" | LogMe -display
try {
if ($data.$computerName.$_[0] -eq "SUCCESS") { $bgcolor = "#387C44"; $fontColor = "#FFFFFF" }
elseif ($data.$computerName.$_[0] -eq "WARNING") { $bgcolor = "#FF7700"; $fontColor = "#FFFFFF" }
elseif ($data.$computerName.$_[0] -eq "ERROR") { $bgcolor = "#FF0000"; $fontColor = "#FFFFFF" }
else { $bgcolor = "#CCCCCC"; $fontColor = "#003399" }
$testResult = $data.$computerName.$_[1]
}
catch {
$bgcolor = "#CCCCCC"; $fontColor = "#003399"
$testResult = ""
}
$tableEntry += ("<td bgcolor='" + $bgcolor + "' align=Left><font color='" + $fontColor + "'>$testResult</font></td>") ###Commented on 17th Feb
}
$tableEntry += "</tr>"
}
$tableEntry | Out-File $fileName -append
}
  
# ==============================================================================================
Function writeHtmlFooter
{
param($fileName)
@"
</table>
<table width='1200'>
<tr bgcolor='#CCCCCC'>
<td colspan='7' height='25' align='left'>
<font face='courier' color='#000000' size='2'>

<strong>Uptime Threshold: </strong> $maxUpTimeDays days <br>
<strong>Database: </strong> $dbinfo <br>
<strong>LicenseServerName: </strong> $lsname <strong>LicenseServerPort: </strong> $lsport <br>
<strong>LocalHostCacheEnabled: </strong> $LHC <br>
<strong>CreatedBy: </strong> Nram@Alhilalbank.ae <br>


</font>
</td>
</table>
</body>
</html>
"@ | Out-File $FileName -append
}

# ==============================================================================================
Function ToHumanReadable()
{
  param($timespan)
  
  If ($timespan.TotalHours -lt 1) {
    return $timespan.Minutes + "minutes"
  }

  $sb = New-Object System.Text.StringBuilder
  If ($timespan.Days -gt 0) {
    [void]$sb.Append($timespan.Days)
    [void]$sb.Append(" days")
    [void]$sb.Append(", ")    
  }
  If ($timespan.Hours -gt 0) {
    [void]$sb.Append($timespan.Hours)
    [void]$sb.Append(" hours")
  }
  If ($timespan.Minutes -gt 0) {
    [void]$sb.Append(" and ")
    [void]$sb.Append($timespan.Minutes)
    [void]$sb.Append(" minutes")
  }
  return $sb.ToString()
}

# ==============================================================================================
function Get-CitrixMaintenanceInfo {
	[CmdletBinding()]
	[OutputType([System.Management.Automation.PSCustomObject])]
	param
	(
		[Parameter(Mandatory = $false,
				   ValueFromPipeline = $true,
				   Position = 0)]
		[System.String[]]$AdminAddress = 'localhost',
		[Parameter(Mandatory = $false,
				   ValueFromPipeline = $true,
				   Position = 1)]
		[System.Management.Automation.PSCredential]$Credential
	) # Param
	
	Try {
		$PSSessionParam = @{ }
		If ($null -ne $Credential) { $PSSessionParam['Credential'] = $Credential } #Splatting
		If ($null -ne $AdminAddress) { $PSSessionParam['ComputerName'] = $AdminAddress } #Splatting
		
		# Create Session
		$Session = New-PSSession -ErrorAction Ignore @PSSessionParam
		
		# Create script block for invoke command
		$ScriptBlock = {
			if ((Get-PSSnapin "Get-PSSnapin Citrix.ConfigurationLogging.Admin.*" -ErrorAction silentlycontinue) -eq $null) {
				try { Add-PSSnapin Citrix.ConfigurationLogging.Admin.* -ErrorAction Stop } catch { write-error "Error Get-PSSnapin Citrix.ConfigurationLogging.Admin.* Powershell snapin"; Return }
			} #If
			
			$Date = Get-Date
			$StartDate = $Date.AddDays(-7) # Hard coded value for how many days back
			$EndDate = $Date
			
			# Command to get the informations from log
			$LogEntrys = Get-LogLowLevelOperation -MaxRecordCount 1000000 -Filter { StartTime -ge $StartDate -and EndTime -le $EndDate } | Where { $_.Details.PropertyName -eq 'MAINTENANCEMODE' } | Sort EndTime -Descending
			
			# Build an object with the data for the output
			[array]$arrMaintenance = @()
			ForEach ($LogEntry in $LogEntrys) {
				$TempObj = New-Object -TypeName psobject -Property @{
					User = $LogEntry.User
					TargetName = $LogEntry.Details.TargetName
					NewValue = $LogEntry.Details.NewValue
					PreviousValue = $LogEntry.Details.PreviousValue
					StartTime = $LogEntry.Details.StartTime
					EndTime = $LogEntry.Details.EndTime
				} #TempObj
				$arrMaintenance += $TempObj
			} #ForEach				
			$arrMaintenance
		} # ScriptBlock
		
		# Run the script block with invoke-command, return the values and close the session
		$MaintLogs = Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ErrorAction Stop
		Write-Output $MaintLogs
		Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
		
	} Catch {
		Write-Warning "Error occurs: $_"
	} # Try/Catch
} # Get-CitrixMaintenanceInfo

#==============================================================================================

$wmiOSBlock = {param($computer)
  try { $wmi= Invoke-Command -ComputerName $computer -ScriptBlock{Get-WmiObject -class Win32_OperatingSystem }}
  catch { $wmi = $null }
  return $wmi
}

#==============================================================================================
# == MAIN SCRIPT ==
#==============================================================================================
rm $logfile -force -EA SilentlyContinue
rm $resultsHTM -force -EA SilentlyContinue
  
"#### Begin with Citrix XenDestop / XenApp HealthCheck ######################################################################" | LogMe -display -progress
  
" " | LogMe -display -progress

# get some farm infos, which will be presented in footer 
$dbinfo = Get-BrokerDBConnection -AdminAddress $AdminAddress
$brokersiteinfos = Get-BrokerSite
$lsname = $brokersiteinfos.LicenseServerName
$lsport = $brokersiteinfos.LicenseServerPort
$CLeasing = $brokersiteinfos.ConnectionLeasingEnabled
$LHC =$brokersiteinfos.LocalHostCacheEnabled


# Log the loaded Citrix PS Snapins
(Get-PSSnapin "Citrix.*" -EA silentlycontinue).Name | ForEach {"PSSnapIn: " + $_ | LogMe -display -progress}
  
#== Controller Check ============================================================================================
"Check Controllers #############################################################################" | LogMe -display -progress
  
" " | LogMe -display -progress
  
$ControllerResults = @{}
$Controllers = Get-BrokerController -AdminAddress $AdminAddress

# Get first DDC version (should be all the same unless an upgrade is in progress)
$ControllerVersion = $Controllers[0].ControllerVersion
"Version: $controllerversion " | LogMe -display -progress

if ($ControllerVersion -lt 7 ) {
  "XenDesktop/XenApp Version below 7.x ($controllerversion) - only DesktopCheck will be performed" | LogMe -display -progress
  #$ShowXenAppTable = 0 #doesent work with XML variables
  Set-Variable -Name ShowXenAppTable -Value 0
} 
else { 
  "XenDesktop/XenApp Version above 7.x ($controllerversion) - XenApp and DesktopCheck will be performed" | LogMe -display -progress
}

foreach ($Controller in $Controllers) {
$tests = @{}
  
#Name of $Controller
$ControllerDNS = $Controller | %{($_.DNSName).split(".")[0] }
"Controller: $ControllerDNS" | LogMe -display -progress
  
#Ping $Controller
$result = Ping $ControllerDNS 100
if ($result -ne "SUCCESS") { $tests.Ping = "Error", $result }
else { $tests.Ping = "SUCCESS", $result 

#Now when Ping is ok also check this:
  
#State of this controller
$ControllerState = $Controller | %{ $_.State }
"State: $ControllerState" | LogMe -display -progress

if ($ControllerState -ne "Active") { $tests.State = "ERROR", $ControllerState }
else { $tests.State = "SUCCESS", $ControllerState }
  
#DesktopsRegistered on this controller
$ControllerDesktopsRegistered = $Controller | %{ $_.DesktopsRegistered }
"Registered: $ControllerDesktopsRegistered" | LogMe -display -progress
$tests.DesktopsRegistered = "NEUTRAL", $ControllerDesktopsRegistered

# Get all services
$ActiveSiteServices=Invoke-Command -ComputerName $Controller.DNSName -ScriptBlock{Get-Service |?{($_.Name -like 'Citrix*') -and ($_.StartType -eq "Automatic") -and($_.Status -ne "Running")}}

# Check if there are any stopped services
if ($ActiveSiteServices) {
    # If there are stopped services, print the list of stopped services
    Write-Host "The following services are not running:"
    $NotRunning_Service=$ActiveSiteServices | ForEach-Object { $_.Name }
    $tests.CitrixServices ="Warning","$NotRunning_Service"

} 
else {
    
        # If no services are stopped, print success message
    Write-Host "All services are running successfully."
    $tests.CitrixServices ="SUCCESS","OK"

}

#==============================================================================================
#               CHECK CPU AND MEMORY USAGE 
#==============================================================================================

        # Check the AvgCPU value for 5 seconds
        $AvgCPUval = CheckCpuUsage ($ControllerDNS)
		#$VDtests.LoadBalancingAlgorithm = "SUCCESS", "LB is set to BEST EFFORT"} 
			
        if( [int] $AvgCPUval -lt 75) { "CPU usage is normal [ $AvgCPUval % ]" | LogMe -display; $tests.AvgCPU = "SUCCESS", "$AvgCPUval %" }
		elseif([int] $AvgCPUval -lt 85) { "CPU usage is medium [ $AvgCPUval % ]" | LogMe -warning; $tests.AvgCPU = "WARNING", "$AvgCPUval %" }   	
		elseif([int] $AvgCPUval -lt 95) { "CPU usage is high [ $AvgCPUval % ]" | LogMe -error; $tests.AvgCPU = "ERROR", "$AvgCPUval %" }
		elseif([int] $AvgCPUval -eq 101) { "CPU usage test failed" | LogMe -error; $tests.AvgCPU = "ERROR", "Err" }
        else { "CPU usage is Critical [ $AvgCPUval % ]" | LogMe -error; $tests.AvgCPU = "ERROR", "$AvgCPUval %" }   
		$AvgCPUval = 0

        # Check the Physical Memory usage       
        $UsedMemory = CheckMemoryUsage ($ControllerDNS)
        if( $UsedMemory -lt 75) { "Memory usage is normal [ $UsedMemory % ]" | LogMe -display; $tests.MemUsg = "SUCCESS", "$UsedMemory %" }
		elseif( [int] $UsedMemory -lt 85) { "Memory usage is medium [ $UsedMemory % ]" | LogMe -warning; $tests.MemUsg = "WARNING", "$UsedMemory %" }   	
		elseif( [int] $UsedMemory -lt 95) { "Memory usage is high [ $UsedMemory % ]" | LogMe -error; $tests.MemUsg = "ERROR", "$UsedMemory %" }
		elseif( [int] $UsedMemory -eq 101) { "Memory usage test failed" | LogMe -error; $tests.MemUsg = "ERROR", "Err" }
        else { "Memory usage is Critical [ $UsedMemory % ]" | LogMe -error; $tests.MemUsg = "ERROR", "$UsedMemory %" }   
		$UsedMemory = 0  

        foreach ($disk in $diskLettersControllers)
        {
            # Check Disk Usage 
		    $HardDisk = CheckHardDiskUsage -hostname $ControllerDNS # -deviceID "$($disk):"
		    if ($HardDisk -ne $null) {	
			    $XAPercentageDS = $HardDisk.PercentageDS
			    $frSpace = $HardDisk.frSpace
			
	            If ( [int] $XAPercentageDS -gt 15) { "Disk Free is normal [ $XAPercentageDS % ]" | LogMe -display; $tests."$($disk)Freespace" = "SUCCESS", "$frSpace GB" } 
			    ElseIf ([int] $XAPercentageDS -eq 0) { "Disk Free test failed" | LogMe -error; $tests."$($disk)Freespace" = "ERROR", "Err" }
			    ElseIf ([int] $XAPercentageDS -lt 5) { "Disk Free is Critical [ $XAPercentageDS % ]" | LogMe -error; $tests."$($disk)Freespace" = "ERROR", "$frSpace GB" } 
			    ElseIf ([int] $XAPercentageDS -lt 15) { "Disk Free is Low [ $XAPercentageDS % ]" | LogMe -warning; $tests."$($disk)Freespace" = "WARNING", "$frSpace GB" }     
	            Else { "Disk Free is Critical [ $XAPercentageDS % ]" | LogMe -error; $tests."$($disk)Freespace" = "ERROR", "$frSpace GB" }  
        
			    $XAPercentageDS = 0
			    $frSpace = 0
			    $HardDisk = $null
		    }
        }
		
    # Check uptime (Query over WMI)
    $tests.WMI = "ERROR","Error"
    try { $wmi=$wmi = Get-WmiObject -class Win32_OperatingSystem -computer $ControllerDNS  }
    catch { $wmi = $null }

    # Perform WMI related checks
    if ($wmi -ne $null) {
        $tests.WMI = "SUCCESS", "Success"
        $LBTime=$wmi.ConvertToDateTime($wmi.Lastbootuptime)
        [TimeSpan]$uptime=New-TimeSpan $LBTime $(get-date)

        if ($uptime.days -lt $minUpTimeDaysDDC){
            "reboot warning, last reboot: {0:D}" -f $LBTime | LogMe -display -warning
            $tests.Uptime = "WARNING", (ToHumanReadable($uptime))
        }
        else { $tests.Uptime = "SUCCESS", (ToHumanReadable($uptime)) }
    }
    else { "WMI connection failed - check WMI for corruption" | LogMe -display -error }
}


  
" --- " | LogMe -display -progress
#Fill $tests into array
$ControllerResults.$ControllerDNS = $tests
}
 
######################################################################################

####Checking the SF informaton

$SFResults = @{}

foreach ($StoreFrontServer in $StoreFrontServers) {
$tests = @{}

#Name of $Controller
$StoreFrontServerDNS = $StoreFrontServer
"SFController: $StoreFrontServerDNS" | LogMe -display -progress
  
#Ping $Controller
$result = Ping $StoreFrontServerDNS 100
if ($result -ne "SUCCESS") { $tests.Ping = "Error", $result }
else { $tests.Ping = "SUCCESS", $result 

#Now when Ping is ok also check this:

# Get all services
$SFActiveSiteServices=Invoke-Command -ComputerName $StoreFrontServerDNS  -ScriptBlock{Get-Service |?{ (($_.Name -ilike "Citrix*") -or ($_.Name -like "W3SVC*")) -and ($_.StartType -eq "Automatic") -and ($_.Status -ne "Running")}}


# Check if there are any stopped services
if ($SFActiveSiteServices) {
    # If there are stopped services, print the list of stopped services
    Write-Host "The following services are not running:$(($SFActiveSiteServices).Name)"
    $NotRunning_Service=$SFActiveSiteServices | ForEach-Object { $_.Name }
    $tests.CitrixSFServices ="Warning","$NotRunning_Service"

} 
else {
    
        # If no services are stopped, print success message
    Write-Host "All services are running successfully."
    $tests.CitrixServices ="SUCCESS","OK"

}

#==============================================================================================
#               CHECK CPU AND MEMORY USAGE 
#==============================================================================================

        # Check the AvgCPU value for 5 seconds
        $AvgCPUval = CheckCpuUsage ($StoreFrontServerDNS)
		#$VDtests.LoadBalancingAlgorithm = "SUCCESS", "LB is set to BEST EFFORT"} 
			
        if( [int] $AvgCPUval -lt 75) { "CPU usage is normal [ $AvgCPUval % ]" | LogMe -display; $tests.AvgCPU = "SUCCESS", "$AvgCPUval %" }
		elseif([int] $AvgCPUval -lt 85) { "CPU usage is medium [ $AvgCPUval % ]" | LogMe -warning; $tests.AvgCPU = "WARNING", "$AvgCPUval %" }   	
		elseif([int] $AvgCPUval -lt 95) { "CPU usage is high [ $AvgCPUval % ]" | LogMe -error; $tests.AvgCPU = "ERROR", "$AvgCPUval %" }
		elseif([int] $AvgCPUval -eq 101) { "CPU usage test failed" | LogMe -error; $tests.AvgCPU = "ERROR", "Err" }
        else { "CPU usage is Critical [ $AvgCPUval % ]" | LogMe -error; $tests.AvgCPU = "ERROR", "$AvgCPUval %" }   
		$AvgCPUval = 0

        # Check the Physical Memory usage       
        $UsedMemory = CheckMemoryUsage ($StoreFrontServerDNS)
        if( $UsedMemory -lt 75) { "Memory usage is normal [ $UsedMemory % ]" | LogMe -display; $tests.MemUsg = "SUCCESS", "$UsedMemory %" }
		elseif( [int] $UsedMemory -lt 85) { "Memory usage is medium [ $UsedMemory % ]" | LogMe -warning; $tests.MemUsg = "WARNING", "$UsedMemory %" }   	
		elseif( [int] $UsedMemory -lt 95) { "Memory usage is high [ $UsedMemory % ]" | LogMe -error; $tests.MemUsg = "ERROR", "$UsedMemory %" }
		elseif( [int] $UsedMemory -eq 101) { "Memory usage test failed" | LogMe -error; $tests.MemUsg = "ERROR", "Err" }
        else { "Memory usage is Critical [ $UsedMemory % ]" | LogMe -error; $tests.MemUsg = "ERROR", "$UsedMemory %" }   
		$UsedMemory = 0  

        foreach ($disk in $diskLettersControllers)
        {
            # Check Disk Usage 
		    $HardDisk = CheckHardDiskUsage -hostname $StoreFrontServerDNS # -deviceID "$($disk):"
		    if ($HardDisk -ne $null) {	
			    $XAPercentageDS = $HardDisk.PercentageDS
			    $frSpace = $HardDisk.frSpace
			
	            If ( [int] $XAPercentageDS -gt 15) { "Disk Free is normal [ $XAPercentageDS % ]" | LogMe -display; $tests."$($disk)Freespace" = "SUCCESS", "$frSpace GB" } 
			    ElseIf ([int] $XAPercentageDS -eq 0) { "Disk Free test failed" | LogMe -error; $tests."$($disk)Freespace" = "ERROR", "Err" }
			    ElseIf ([int] $XAPercentageDS -lt 5) { "Disk Free is Critical [ $XAPercentageDS % ]" | LogMe -error; $tests."$($disk)Freespace" = "ERROR", "$frSpace GB" } 
			    ElseIf ([int] $XAPercentageDS -lt 15) { "Disk Free is Low [ $XAPercentageDS % ]" | LogMe -warning; $tests."$($disk)Freespace" = "WARNING", "$frSpace GB" }     
	            Else { "Disk Free is Critical [ $XAPercentageDS % ]" | LogMe -error; $tests."$($disk)Freespace" = "ERROR", "$frSpace GB" }  
        
			    $XAPercentageDS = 0
			    $frSpace = 0
			    $HardDisk = $null
		    }
        }
		
    # Check uptime (Query over WMI)
    $tests.WMI = "ERROR","Error"
    try { $wmi= Get-WmiObject -class Win32_OperatingSystem -computer $StorefrontServer  }
    catch { $wmi = $null }

    # Perform WMI related checks
    if ($wmi -ne $null) {
        $tests.WMI = "SUCCESS", "Success"
        $LBTime=$wmi.ConvertToDateTime($wmi.Lastbootuptime)
        [TimeSpan]$uptime=New-TimeSpan $LBTime $(get-date)

        if ($uptime.days -lt $minUpTimeDaysDDC){
            "reboot warning, last reboot: {0:D}" -f $LBTime | LogMe -display -warning
            $tests.Uptime = "WARNING", (ToHumanReadable($uptime))
        }
        else { $tests.Uptime = "SUCCESS", (ToHumanReadable($uptime)) }
    }
    else { "WMI connection failed - check WMI for corruption" | LogMe -display -error }

}


  
" --- " | LogMe -display -progress
#Fill $tests into array
$SFResults.$StoreFrontServerDNS = $tests


}

  
#== DeliveryGroups Check ============================================================================================
"Check Assigments #############################################################################" | LogMe -display -progress
  
" " | LogMe -display -progress
  
$AssigmentsResults = @{}
$Assigments = Get-BrokerDesktopGroup -AdminAddress $AdminAddress| ?{($_.Name -imatch "DG1") -or ($_.Name -imatch "DG2*")} 
  
foreach ($Assigment in $Assigments) {
  $tests = @{}
  
  #Name of DeliveryGroup
  $DeliveryGroup = $Assigment | %{ $_.Name }
  "DeliveryGroup: $DeliveryGroup" | LogMe -display -progress
  
  if ($ExcludedCatalogs -contains $DeliveryGroup) {
    "Excluded Delivery Group, skipping" | LogMe -display -progress
  } 
  else {

  #PublishedName","TotalMachines", "DesktopsInUse","DesktopsFree","DesktopsUnregistered","DesktopKind", "SessionSupport"
    #PublishedName
    $AssigmentDesktopPublishedName = $Assigment | %{ $_.PublishedName }
    "PublishedName: $AssigmentDesktopPublishedName" | LogMe -display -progress
    $tests.PublishedName = "NEUTRAL", $AssigmentDesktopPublishedName
  
    #DesktopsTotal
    $TotalDesktops = $Assigment | %{ $_.TotalDesktops}
    "TotalDesktops : $TotalDesktops" | LogMe -display -progress
    $tests.TotalMachines = "NEUTRAL", $TotalDesktops

    #DesktopsInUse
    $AssigmentDesktopsInUse = $Assigment | %{ $_.Sessions }
    "DesktopsInUse: $AssigmentDesktopsInUse" | LogMe -display -progress
    $tests.DesktopsInUse = "NEUTRAL", $AssigmentDesktopsInUse
  
    #DesktopsAvailable
    $AssigmentDesktopsAvailable = $TotalDesktops - $AssigmentDesktopsInUse
    "DesktopsAvailable: $AssigmentDesktopsAvailable" | LogMe -display -progress
    $tests.DesktopsFree = "NEUTRAL", $AssigmentDesktopsAvailable



    #DesktopKind
    $AssigmentDesktopsKind = $Assigment | %{ $_.DesktopKind }
    "DesktopKind: $AssigmentDesktopsKind" | LogMe -display -progress
    $tests.DesktopKind = "NEUTRAL", $AssigmentDesktopsKind


	if ($SessionSupport -eq "MultiSession" ) { 
	
	$tests.DesktopsFree = "NEUTRAL", "N/A"
	$tests.DesktopsInUse = "NEUTRAL", "N/A"
		
	}

    else { 
			#DesktopsInUse
			$AssigmentDesktopsInUse = $Assigment | %{ $_.DesktopsInUse }
			"DesktopsInUse: $AssigmentDesktopsInUse" | LogMe -display -progress
			$tests.DesktopsInUse = "NEUTRAL", $AssigmentDesktopsInUse
	
			#DesktopFree
			$AssigmentDesktopsFree = $AssigmentDesktopsAvailable - $AssigmentDesktopsInUse
			"DesktopsFree: $AssigmentDesktopsFree" | LogMe -display -progress
  
			if ($AssigmentDesktopsKind -eq "shared") {
			if ($AssigmentDesktopsFree -gt 0 ) {
				"DesktopsFree < 1 ! ($AssigmentDesktopsFree)" | LogMe -display -progress
				$tests.DesktopsFree = "SUCCESS", $AssigmentDesktopsFree
			} elseif ($AssigmentDesktopsFree -lt 0 ) {
				"DesktopsFree < 1 ! ($AssigmentDesktopsFree)" | LogMe -display -progress
				$tests.DesktopsFree = "SUCCESS", "N/A"
			} else {
				$tests.DesktopsFree = "WARNING", $AssigmentDesktopsFree
				"DesktopsFree > 0 ! ($AssigmentDesktopsFree)" | LogMe -display -progress
			}
			} else {
			$tests.DesktopsFree = "NEUTRAL", "N/A"
			}
	
	
	}
#>
		
   <#
    #inMaintenanceMode
    $AssigmentDesktopsinMaintenanceMode = $Assigment | %{ $_.inMaintenanceMode }
    "inMaintenanceMode: $AssigmentDesktopsinMaintenanceMode" | LogMe -display -progress
    if ($AssigmentDesktopsinMaintenanceMode) { $tests.MaintenanceMode = "WARNING", "ON" }
    else { $tests.MaintenanceMode = "SUCCESS", "OFF" }
    #>
  
    #DesktopsUnregistered
    $AssigmentDesktopsUnregistered = $Assigment | %{ $_.DesktopsUnregistered }
    "DesktopsUnregistered: $AssigmentDesktopsUnregistered" | LogMe -display -progress    
    if ($AssigmentDesktopsUnregistered -gt 0 ) {
      "DesktopsUnregistered > 0 ! ($AssigmentDesktopsUnregistered)" | LogMe -display -progress
      $tests.DesktopsUnregistered = "WARNING", $AssigmentDesktopsUnregistered
    } else {
      $tests.DesktopsUnregistered = "SUCCESS", $AssigmentDesktopsUnregistered
      "DesktopsUnregistered <= 0 ! ($AssigmentDesktopsUnregistered)" | LogMe -display -progress
    }
  
    
      
    #Fill $tests into array
    $AssigmentsResults.$DeliveryGroup = $tests
  }
  " --- " | LogMe -display -progress
}
  
# ======= License Check ========
  
# ======= License Check ========
if($ShowCTXLicense -eq 1 ){

    $myCollection = @()
    try 
	{
        $LicWMIQuery = Invoke-Command -ComputerName $lsname -ScriptBlock {get-wmiobject -namespace "ROOT\CitrixLicensing" -query "select * from Citrix_GT_License_Pool" -ErrorAction Stop | ?{$_.PLD -ilike "XDT_PLT_CCS"} }
        
        foreach ($group in $($LicWMIQuery | group pld))
        {
            $lics = $group | select -ExpandProperty group
            $i = 1

            $myArray_Count = 0
		    $myArray_InUse = 0
		    $myArray_Available = 0
		
		    foreach ($lic in @($lics))
		    {
		    $myArray = "" | Select-Object LicenseServer,LicenceName,Count,InUse,Available
		    $myArray.LicenseServer = $lsname
		    $myArray.LicenceName = "$($lics.pld)"
		    $myArray.Count = $Lic.count - $Lic.Overdraft
		    if ($Lic.inusecount -gt $myArray.Count) {$myArray.InUse = $myArray.Count} else {$myArray.InUse = $Lic.inusecount}
		    $myArray.Available = $myArray.count - $myArray.InUse
		    $myCollection += $myArray
	
		
		    $myArray_Count += $Lic.count
		    $myArray_InUse += $Lic.inusecount
		    $myArray_Available += $Lic.pooledavailable
				
		    $i++
		    }

    }
    }
    catch
    {
            $myArray = "" | Select-Object LicenseServer,LicenceName,Count,InUse,Available
		    $myArray.LicenseServer = $lsname
		    $myArray.LicenceName = "n/a"
		    $myArray.Count = "n/a"
		    $myArray.InUse = "n/a"
		    $myArray.Available = "n/a"
		    $myCollection += $myArray 
    }
    
    $CTXLicResults = @{}

    foreach ($line in $myCollection){
        $tests = @{}


        if ($line.LicenceName -eq "n/a")
        {
            $tests.LicenseServer ="error", $line.LicenseServer
            $tests.Count ="error", $line.Count
		    $tests.InUse ="error", $line.InUse
		    $tests.Available ="error", $line.Available
        }
        else
        {
            $tests.LicenseName ="NEUTRAL", ($line.LicenceName)
            $tests.Count ="NEUTRAL", $line.Count
		    $tests.InUse ="NEUTRAL", $line.InUse
		    ##checking Percentage of license available
            if($line.Available -lt ($line.Count*0.1) ){ 
            "Available Licenses are $(($line).Available)" | LogMe -display -progress
             $tests.Available = "WARNING", $line.Available
              }

            else {
            $tests.Available = "SUCCESS", $line.Available 
            }
            }


            $CTXLicResults.(($line.LicenseServer.Split(".")[0]).ToUpper()) =  $tests
        }

}
else {"CTX License Check skipped because ShowCTXLicense = 0 " | LogMe -display -progress }

# ======= Desktop Check ========
"Check virtual Desktops ####################################################################################" | LogMe -display -progress
" " | LogMe -display -progress
  
if($ShowDesktopTable -eq 1 ) {
  
$allResults = @{}
  
$machines = Get-BrokerMachine -MaxRecordCount $maxmachines -AdminAddress $AdminAddress| Where-Object {($_.CatalogName -ilike "Catalog1*") -and @(compare $_.tags $ExcludedTags -IncludeEqual | ? {$_.sideindicator -eq '=='}).count -eq 0}
  
# SessionSupport only availiable in XD 7.x - for this reason only distinguish in Version above 7 if Desktop or XenApp
#if($controllerversion -lt 7 ) { $machines = Get-BrokerMachine -MaxRecordCount $maxmachines -AdminAddress $AdminAddress -and ($_.CatalogName -ilike "Catalog1*") -and @(compare $_.tags $ExcludedTags -IncludeEqual | ? {$_.sideindicator -eq '=='}).count -eq 0}
#else { $machines = Get-BrokerMachine -MaxRecordCount $maxmachines -AdminAddress $AdminAddress| Where-Object {($_.CatalogName -ilike "Catalog1*") -and @(compare $_.tags $ExcludedTags -IncludeEqual | ? {$_.sideindicator -eq '=='}).count -eq 0} }

$Maintenance = Get-CitrixMaintenanceInfo -AdminAddress $AdminAddress 

foreach($machine in $machines) 
{
$tests = @{}
  
$ErrorVDI = 0
  
# Column Name of Desktop
$machineDNS = $machine | %{ $_.HostedMachineName }
#"State: $machineDNS"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append


# Column CatalogName
$CatalogName = $machine | %{ $_.CatalogName }
$tests.CatalogName = "NEUTRAL", $CatalogName
#"CatalogName: $CatalogName" |Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append 


# Column DeliveryGroup
$DeliveryGroup = $machine | %{ $_.DesktopGroupName }
$tests.DeliveryGroup = "NEUTRAL", $DeliveryGroup
#"DGGroup: $DeliveryGroup" | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append 

# Column Powerstate
$Powered = $machine | %{ $_.PowerState }
#$tests.PowerState = "NEUTRAL", $Powered

if ($Powered -eq "On" -and ($machine.RegistrationState -eq "Unregistered")) {
$tests.PowerState = "ERROR", $Powered
#"PowerState: $Powered"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append


}
elseif ($Powered -eq "OFF" -and ($machine.RegistrationState -eq "Unregistered")) {
$tests.PowerState = "NEUTRAL", $Powered
#"PowerState: $Powered"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append


}
else { 
$tests.PowerState = "SUCCESS", $Powered
#"PowerState: $Powered" | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append

}



# Column RegistrationState
$RegistrationState = $machine | %{ $_.RegistrationState }
"State: $RegistrationState" | LogMe -display -progress
if (($RegistrationState -ne "Registered") -and($Powered -eq "On" )) {
$tests.RegState = "ERROR", $RegistrationState
$ErrorVDI = $ErrorVDI + 1

#"RegState: $RegistrationState"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append

}

elseif ($RegistrationState -ne "Registered" -and($Powered -eq "OFF" )) {
$tests.RegState = "NEUTRAL", $RegistrationState
#"RegState: $RegistrationState"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append

}

else { $tests.RegState = "NEUTRAL", $RegistrationState 
#"RegState: $RegistrationState"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append
}

 
# Column MaintenanceMode
$MaintenanceMode = $machine | %{ $_.InMaintenanceMode }
"MaintenanceMode: $MaintenanceMode" | LogMe -display -progress
if ($MaintenanceMode -eq $true) {
	$MaintenanceModeOn = "ON"
	"MaintenanceModeInfo: $MaintenanceModeOn" | LogMe -display -progress
   # "Maintenance: $MaintenanceMode"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append
	$tests.MaintMode = "WARNING", $MaintenanceModeOn
	$ErrorVDI = $ErrorVDI + 1
}
else { $tests.MaintMode = "NEUTRAL", "OFF" 
   # "Maintenance: $MaintenanceMode"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append
   "MaintenanceModeInfo: $MaintenanceModeOn" | LogMe -display -progress

}



# Column VDAVersion AgentVersion
$VDAVersion_Trim =$machine | %{ ($_.AgentVersion)}

$splitString = $VDAVersion_Trim.Split('.')
$VDAVersion = "$($splitString[0]).$($splitString[1]).$($splitString[2])"
"VDAVersion: $VDAVersion" | LogMe -display -progress
$tests.VDAVersion = "NEUTRAL", $VDAVersion
#"VDAVersion: $VDAVersion"  | Out-File 'C:\o1785\Citrix HealthCheck\output.csv' -Append




##Printing output in HTML for VDI
if ($ExcludedCatalogs -contains $CatalogName) {
"$machineDNS in excluded folder - skipping" | LogMe -display -progress
}
else {

##Need to check line from 1072 to 1078---- 17th Feb
# Check if error exists on this vdi
#if ($ShowOnlyErrorVDI -eq 0 ) { $allResults.$machineDNS = $tests }
#else {
#if ($ErrorVDI -gt 0) { $allResults.$machineDNS = $tests }
#else { "$machineDNS is ok, no output into HTML-File" | LogMe -display -progress }
#}
$allResults.$machineDNS = $tests
}

}

}
else{ "Desktop Check skipped because ShowDesktopTable = 0 " | LogMe -display -progress 
}
  
# ======= XenApp Check ========
"Check XenApp Servers ####################################################################################" | LogMe -display -progress
" " | LogMe -display -progress
  
# Check XenApp only if $ShowXenAppTable is 1
#Skip2
if($ShowXenAppTable -eq 1 ) {
$allXenAppResults = @{}
$tests = @{}
$CatalogResults = @{}
$Catalogs = Get-BrokerCatalog -AdminAddress $AdminAddress
foreach ($Catalog in $Catalogs) {
  
  
  #Name of MachineCatalog
  $CatalogName = $Catalog | %{ $_.Name }

   if ($ExcludedCatalogs -like "*$CatalogName*" ) 
  { 
  "$CatalogName is excluded folder hence skipping" | LogMe -display -progress
    }
else 
{
"$CatalogName is available and processing" | LogMe -display -progress


  
#$XAmachines = Get-BrokerMachine -MaxRecordCount $maxmachines -AdminAddress $AdminAddress | Where-Object {$_.SessionSupport -eq "MultiSession" -and @(compare $_.tags $ExcludedTags -IncludeEqual | ? {$_.sideindicator -eq '=='}).count -eq 0}
$XAmachines = Get-BrokerMachine -MaxRecordCount $maxmachines -MachineName "*MachineName*" -CatalogName $CatalogName -AdminAddress $AdminAddress | Where-Object {$_.SessionSupport -eq "MultiSession" -and @(compare $_.tags $ExcludedTags -IncludeEqual | ? {$_.sideindicator -eq '=='}).count -eq 0}
$Maintenance = Get-CitrixMaintenanceInfo -AdminAddress $AdminAddress
  
foreach ($XAmachine in $XAmachines) {
$tests = @{}
  
# Column Name of Machine
$machineDNS = $XAmachine | %{ ($_.DNSName).split(".")[0] }
"Machine: $machineDNS" | LogMe -display -progress
  
# Column CatalogNameName
$CatalogName = $XAmachine | %{ $_.CatalogName }
"Catalog: $CatalogName" | LogMe -display -progress
$tests.CatalogName = "NEUTRAL", $CatalogName
  
# Ping Machine
$result = Ping $machineDNS 100
if ($result -eq "SUCCESS") {
$tests.Ping = "SUCCESS", $result
  
#==============================================================================================
# Column Uptime (Query over WMI - only if Ping successfull)
$tests.WMI = "ERROR","Error"
$job = Start-Job -ScriptBlock $wmiOSBlock -ArgumentList $machineDNS
$wmi = Wait-job $job -Timeout 15 | Receive-Job

# Perform WMI related checks
if ($wmi -ne $null) {
	$tests.WMI = "SUCCESS", "Success"
	$LBTime=[Management.ManagementDateTimeConverter]::ToDateTime($wmi.Lastbootuptime)
	[TimeSpan]$uptime=New-TimeSpan $LBTime $(get-date)

	if ($uptime.days -gt $maxUpTimeDays) {
		"reboot warning, last reboot: {0:D}" -f $LBTime | LogMe -display -warning
		$tests.Uptime = "WARNING", $uptime.days
	} else {
		$tests.Uptime = "SUCCESS", $uptime.days
	}
} 
else {
	"WMI connection failed - check WMI for corruption" | LogMe -display -error
	stop-job $job
}

}
else { $tests.Ping = "Error", $result }
#END of Ping-Section
  

# Column Serverload
$Serverload = $XAmachine | %{ $_.LoadIndex }
"Serverload: $Serverload" | LogMe -display -progress
if ($Serverload -ge $loadIndexError) { $tests.Serverload = "ERROR", $Serverload }
elseif ($Serverload -ge $loadIndexWarning) { $tests.Serverload = "WARNING", $Serverload }
else { $tests.Serverload = "SUCCESS", $Serverload }
  
# Column MaintMode
$MaintMode = $XAmachine | %{ $_.InMaintenanceMode }
"MaintenanceMode: $MaintMode" | LogMe -display -progress
if ($MaintMode) { 
	$objMaintenance = $Maintenance | Where { $_.TargetName.ToUpper() -eq $XAmachine.MachineName.ToUpper() } | Select -First 1
	If ($null -ne $objMaintenance){$MaintenanceModeOn = ("ON, " + $objMaintenance.User)} Else {$MaintenanceModeOn = "ON"}
	"MaintenanceModeInfo: $MaintenanceModeOn" | LogMe -display -progress
	$tests.MaintMode = "WARNING", $MaintenanceModeOn
	$ErrorVDI = $ErrorVDI + 1
}
else { $tests.MaintMode = "SUCCESS", "OFF" }
  
# Column RegState
$RegState = $XAmachine | %{ $_.RegistrationState }
"State: $RegState" | LogMe -display -progress
  
if ($RegState -ne "Registered") { $tests.RegState = "ERROR", $RegState }
else { $tests.RegState = "SUCCESS", $RegState }

# Column VDAVersion AgentVersion
$VDAVersion_Trim = $XAmachine | %{ $_.AgentVersion}
$splitString = $VDAVersion_Trim.Split('.')
$VDAVersion = "$($splitString[0]).$($splitString[1]).$($splitString[2])"
"VDAVersion: $VDAVersion" | LogMe -display -progress
$tests.VDAVersion = "NEUTRAL", $VDAVersion

# Column ActiveSessions
$ActiveSessions = $XAmachine | %{ $_.SessionCount }
"Active Sessions: $ActiveSessions" | LogMe -display -progress
$tests.ActiveSessions = "NEUTRAL", $ActiveSessions


# Column DeliveryGroup
$DeliveryGroup = $XAmachine | %{ $_.DesktopGroupName }
"DeliveryGroup: $DeliveryGroup" | LogMe -display -progress
$tests.DeliveryGroup = "NEUTRAL", $DeliveryGroup


#==============================================================================================
#               CHECK CPU AND MEMORY USAGE 
#==============================================================================================

        # Check the AvgCPU value for 5 seconds
        $XAAvgCPUval = CheckCpuUsage ($machineDNS)
		#$VDtests.LoadBalancingAlgorithm = "SUCCESS", "LB is set to BEST EFFORT"} 
			
        if( [int] $XAAvgCPUval -lt 75) { "CPU usage is normal [ $XAAvgCPUval % ]" | LogMe -display; $tests.AvgCPU = "SUCCESS", "$XAAvgCPUval %" }
		elseif([int] $XAAvgCPUval -lt 85) { "CPU usage is medium [ $XAAvgCPUval % ]" | LogMe -warning; $tests.AvgCPU = "WARNING", "$XAAvgCPUval %" }   	
		elseif([int] $XAAvgCPUval -lt 95) { "CPU usage is high [ $XAAvgCPUval % ]" | LogMe -error; $tests.AvgCPU = "ERROR", "$XAAvgCPUval %" }
		elseif([int] $XAAvgCPUval -eq 101) { "CPU usage test failed" | LogMe -error; $tests.AvgCPU = "ERROR", "Err" }
        else { "CPU usage is Critical [ $XAAvgCPUval % ]" | LogMe -error; $tests.AvgCPU = "ERROR", "$XAAvgCPUval %" }   
		$XAAvgCPUval = 0

        # Check the Physical Memory usage       
        [int] $XAUsedMemory = CheckMemoryUsage ($machineDNS)
        if( [int] $XAUsedMemory -lt 75) { "Memory usage is normal [ $XAUsedMemory % ]" | LogMe -display; $tests.MemUsg = "SUCCESS", "$XAUsedMemory %" }
		elseif( [int] $XAUsedMemory -lt 85) { "Memory usage is medium [ $XAUsedMemory % ]" | LogMe -warning; $tests.MemUsg = "WARNING", "$XAUsedMemory %" }   	
		elseif( [int] $XAUsedMemory -lt 95) { "Memory usage is high [ $XAUsedMemory % ]" | LogMe -error; $tests.MemUsg = "ERROR", "$XAUsedMemory %" }
		elseif( [int] $XAUsedMemory -eq 101) { "Memory usage test failed" | LogMe -error; $tests.MemUsg = "ERROR", "Err" }
        else { "Memory usage is Critical [ $XAUsedMemory % ]" | LogMe -error; $tests.MemUsg = "ERROR", "$XAUsedMemory %" }   
		$XAUsedMemory = 0  

        foreach ($disk in $diskLettersWorkers)
        {
            # Check Disk Usage 
            $HardDisk = CheckHardDiskUsage -hostname $machineDNS #-deviceID "$($disk):"
		    if ($HardDisk -ne $null) {	
			    $XAPercentageDS = $HardDisk.PercentageDS
			    $frSpace = $HardDisk.frSpace

			    If ( [int] $XAPercentageDS -gt 15) { "Disk Free is normal [ $XAPercentageDS % ]" | LogMe -display; $tests."$($disk)Freespace" = "SUCCESS", "$frSpace GB" } 
			    ElseIf ([int] $XAPercentageDS -eq 0) { "Disk Free test failed" | LogMe -error; $tests.CFreespace = "ERROR", "Err" }
			    ElseIf ([int] $XAPercentageDS -lt 5) { "Disk Free is Critical [ $XAPercentageDS % ]" | LogMe -error; $tests."$($disk)Freespace" = "ERROR", "$frSpace GB" } 
			    ElseIf ([int] $XAPercentageDS -lt 15) { "Disk Free is Low [ $XAPercentageDS % ]" | LogMe -warning; $tests."$($disk)Freespace" = "WARNING", "$frSpace GB" }     
			    Else { "Disk Free is Critical [ $XAPercentageDS % ]" | LogMe -error; $tests."$($disk)Freespace" = "ERROR", "$frSpace GB" }
			
			    $XAPercentageDS = 0
			    $frSpace = 0
			    $HardDisk = $null
		    }
		
        }

	




  
" --- " | LogMe -display -progress
  
# Check to see if the server is in an excluded folder path
if ($ExcludedCatalogs -contains $CatalogName) { "$machineDNS in excluded folder - skipping" | LogMe -display -progress }
else { $allXenAppResults.$machineDNS = $tests }
}
}
  }

  }#skip2end
  

else { "XenApp Check skipped because ShowXenAppTable = 0 or Farm is < V7.x " | LogMe -display -progress }
  
####################### Check END ####################################################################################" | LogMe -display -progress
# ======= Write all results to an html file =================================================
# Add Version of XenDesktop to EnvironmentName
$XDmajor, $XDminor = $controllerversion.Split(".")[0..1]
$XDVersion = "$XDmajor.$XDminor"
$EnvironmentNameOut = "$EnvironmentName 2402 CU1" #Need to update manually whenever there is Citrix Uprade
$emailSubject = ("$EnvironmentNameOut Farm Report - " + $ReportDate)

Write-Host ("Saving results to html report: " + $resultsHTM)
writeHtmlHeader "$EnvironmentNameOut Farm Report" $resultsHTM
  
# Write Table with the Controllers
writeTableHeader $resultsHTM $XDControllerFirstheaderName $XDControllerHeaderNames $XDControllerHeaderWidths $XDControllerTableWidth
$ControllerResults | sort-object -property XDControllerFirstheaderName | %{ writeData $ControllerResults $resultsHTM $XDControllerHeaderNames }
writeTableFooter $resultsHTM

# Write Table with the StorefrontServers
writeTableHeader $resultsHTM $SFControllerFirstheaderName $SFControllerHeaderNames $SFControllerHeaderWidths $SFControllerTableWidth
$SFResults | sort-object -property SFControllerFirstheaderName | %{ writeData $SFResults $resultsHTM $SFControllerHeaderNames }
writeTableFooter $resultsHTM

# Write Table with the License
writeTableHeader $resultsHTM $CTXLicFirstheaderName $CTXLicHeaderNames $CTXLicHeaderWidths $CTXLicTableWidth
$CTXLicResults | sort-object -property LicenseName | %{ writeData $CTXLicResults $resultsHTM $CTXLicHeaderNames }
writeTableFooter $resultsHTM
  
# Write Table with the Assignments (Delivery Groups)
writeTableHeader $resultsHTM $AssigmentFirstheaderName $vAssigmentHeaderNames $vAssigmentHeaderWidths $Assigmenttablewidth
$AssigmentsResults | sort-object -property TotalMachines -Descending | %{ writeData $AssigmentsResults $resultsHTM $vAssigmentHeaderNames }
writeTableFooter $resultsHTM

# Write Table with all XenApp Servers
if ($ShowXenAppTable -eq 1 ) {
writeTableHeader $resultsHTM $XenAppFirstheaderName $XenAppHeaderNames $XenAppHeaderWidths $XenApptablewidth
$allXenAppResults | sort-object -property CatalogName | %{ writeData $allXenAppResults $resultsHTM $XenAppHeaderNames }
writeTableFooter $resultsHTM
}
else { "No XenApp output in HTML " | LogMe -display -progress }

# Write Table with all Desktops
if ($ShowDesktopTable -eq 1 ) {
writeTableHeader $resultsHTM $VDIFirstheaderName $VDIHeaderNames $VDIHeaderWidths $VDItablewidth
$allResults | sort-object -property CatalogName | %{ writeData $allResults $resultsHTM $VDIHeaderNames }
writeTableFooter $resultsHTM
}
else { "No XenDesktop output in HTML " | LogMe -display -progress }
  
 
writeHtmlFooter $resultsHTM

$scriptend = Get-Date
$scriptruntime =  $scriptend - $scriptstart | select TotalSeconds
$scriptruntimeInSeconds = $scriptruntime.TotalSeconds
#Write-Host $scriptruntime.TotalSeconds
"Script was running for $scriptruntimeInSeconds " | LogMe -display -progress

#send email
$emailMessage = New-Object System.Net.Mail.MailMessage
$emailMessage.From = $emailFrom
#$emailMessage.To.Add( $emailTo )
$emailMessage.Bcc.Add($emailBcc)
$emailMessage.Subject = $emailSubject 
$emailMessage.IsBodyHtml = $true
$emailMessage.Body = (gc $resultsHTM) | Out-String
$emailMessage.Attachments.Add($resultsHTM)
$emailMessage.Priority = ($emailPrio)
$emailMessage.Sender="Virtualteam@Cloud.com"
$emailMessage.Sender.DisplayName

$smtpClient = New-Object System.Net.Mail.SmtpClient( $smtpServer , $smtpServerPort )
$smtpClient.EnableSsl = $smtpEnableSSL

$smtpClient.Send($emailMessage)


#$emailMessage.Bcc 
