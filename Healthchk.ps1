############################# 1.  Server Hostname ##############################

$HostName = hostname
$result = @()
#################################################################################

############################# 2.  OS & Service Pack Level #######################

$Win32_OS = Get-WmiObject Win32_OperatingSystem
$OSName = $Win32_OS.caption
$ServicePack = $Win32_OS.servicepackmajorversion
$osarc = (get-wmiobject win32_computersystem).systemtype
$osversion = $Win32_OS.Version + " Build " +$Win32_OS.BuildNumber
$OSArchitecture = [IntPtr]::Size

#################################################################################

############################# 3. NMI Registry ######################################

if (Get-ItemProperty -path "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl" -ErrorAction SilentlyContinue |% {$_.NMICrashDump -eq '1'})
{$NMI = "Yes"}
else
{$NMI = "No"}


#################################################################################

############################## 4. Ram and PageFile ##############################

$RAM = Get-WMIObject -class Win32_PhysicalMemory | Measure-Object -Property capacity -Sum | select @{N="TotalRAM"; E={[math]::round(($_.Sum / 1GB),2)}} | select -ExpandProperty TotalRAM

$Page1 = Get-WmiObject -Class Win32_PageFileSetting | Select -expandProperty maximumsize
$pageresult1 =  ($page1 | Measure-Object -sum).sum / 1KB

$page = @()
$Allpagefile = Get-WmiObject -Class Win32_PageFileSetting | Select Name,@{Label='Size';Expression={$_.MaximumSize/1024}}
$Allpagefile | %{$page += $_.name +" - "+ "{0:N2}"-f $_.size}
$pagefileout = ($page -join " ; ")

#################################################################################

############################ 5. Eventlog Archive tool ###########################

if (schtasks.exe /query /fo csv | ConvertFrom-Csv | Where-Object { ($_.TaskName -like '*Winlogmgr*') -or ($_.TaskName -like "*Event*")})
{$log = "Yes"}
else
{$log = "No"}

#################################################################################

############################ 6. Anitvirus Version ###############################

If ($OSArchitecture -eq 4)
{
$Mcafee = Get-ItemProperty -path "HKLM:\SOFTWARE\McAfee\DesktopProtection" -ErrorAction SilentlyContinue |% {$_.szProductVer}
$Mcafee1 = Get-ItemProperty -path "HKLM:\SOFTWARE\McAfee\AVEngine" -ErrorAction SilentlyContinue |% {$_.AVDatDate}
$Mcafee2 = Get-ItemProperty -path "HKLM:\SOFTWARE\McAfee\AVEngine" -ErrorAction SilentlyContinue |% {$_.AVDatVersion}

}

If ($OSArchitecture -eq 8)
{
$Mcafee = Get-ItemProperty -path "HKLM:\SOFTWARE\Wow6432node\McAfee\DesktopProtection" -ErrorAction SilentlyContinue |% {$_.szProductVer}
$Mcafee1 = Get-ItemProperty -path "HKLM:\SOFTWARE\Wow6432node\McAfee\AVEngine" -ErrorAction SilentlyContinue |% {$_.AVDatDate}
$Mcafee2 = Get-ItemProperty -path "HKLM:\SOFTWARE\Wow6432node\McAfee\AVEngine" -ErrorAction SilentlyContinue |% {$_.AVDatVersion}
}

$Mcafeeout = $Mcafee + $Mcafee1 + $Mcafee2

$Symantec = Get-ItemProperty -path "HKLM:\SOFTWARE\Symantec\Symantec Endpoint Protection\CurrentVersion" -ErrorAction SilentlyContinue |% {$_.ProductVersion} 
$Symantec1 = Get-ItemProperty -path "HKLM:\SOFTWARE\Symantec\Symantec Endpoint Protection\CurrentVersion\public-opstate" -ErrorAction SilentlyContinue |% {$_.LatestVirusDefsDate} 
$SymantecResult = $Symantec + " - " +$Symantec1

$avresult = $Mcafeeout + $SymantecResult


###################################################################################

############################### 7. VM tools version ###############################

If (Test-Path 'C:\Program Files\VMware\VMware Tools\VMwareToolboxCmd.exe')
{
$vmware = &'C:\Program Files\VMware\VMware Tools\VMwareToolboxCmd.exe' -v
}
else
{
$vmware = ""
}

#####################################################################################

############################### 8. SCM Client ######################################

$SCMCLT = "*SCM Client*"
$svcscm = Get-Service -displayname $SCMCLT -ErrorAction SilentlyContinue
if (-not $svcscm)
{
$SCM = "No"
}
else
{$SCM = "Yes"
} 

#######################################################################################

############################### 9. UAC ###############################################

if (Get-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -ErrorAction SilentlyContinue |% {$_.enablelua -eq '1'})
{
$UAC = "Yes"
}
else
{
$UAC = "No"
}

########################################################################################



#######################################################################################

########################## Role / MS package installtion permission####################

If ($OS -notlike "*2008 R2*" -and  $OS -Like "*2008*")
{ 
 $Roles = icacls %windir%\serviceprofiles\networkservice\appdata\roaming\microsoft\softwarelicensing /grant "BUILTIN\Administrators:(OI)(CI)(F)" "NT AUTHORITY\SYSTEM:(OI)(CI)(F)" "NT Service\slsvc:(OI)(CI)(R,W,D)"
}
If ($OS -like "*2008 R2*" -and $OSArchitecture -eq 8)
{
 $Roles = icacls %windir%\ServiceProfiles\NetworkService\AppData\Roaming\Microsoft\SoftwareProtectionPlatform /grant "BUILTIN\Administrators:(OI)(CI)(F)" "NT AUTHORITY\SYSTEM:(OI)(CI)(F)" "NETWORK SERVICE:(OI)(CI)(F)"
}
If ($OS -like "*2003*")
{
$Roles = "Not Applicable"
}

########################################################################################

################################## Memory and CPU ########################################
$CPU_AVG = Get-WmiObject Win32_processor | Measure-Object -Property loadpercentage -Average | foreach{$_.average}
if ( $CPU_AVG -gt 80 )
{
	$CPU="CPU Utilization in Red with $CPU_AVG %"
}
else
{
	$CPU="CPU Utilization in Green"
}
$Memory_PC = Get-WmiObject Win32_operatingsystem | foreach{((($_.TotalVisibleMemorySize - $_.FreePhysicalMemory)*100)/$_.TotalVisibleMemorySize) }
if ( $Memory_PC -le 80 ){
        $Memory="Memory Utilization in Green."
}
elseif ( $Memory_PC -gt 80 -and $Memory_PC -le 90 ){
        $Memory="Memory Utilization in Amber with $Memory_PC%."
}
else {
        $Memory="Memory Utilization in Red with $Memory_PC%."
}

############################################################################################

################################# Backup Details ##########################################
$cmdfile = "cd `"C:\Program Files\Tivoli\TSM\baclient\`"
.\dsmc.exe q files > c:\temp\tsmlog.txt
.\dsmc.exe q f -optfile=`"dsm_day.opt`" >> c:\temp\tsmlog.txt"

$cmdfile > "C:\temp\TSM_Backup.bat"
$MyPath1 = "C:\temp\TSM_Backup.bat"
$MyFile1 = Get-Content $MyPath1
$Utf8NoBomEncoding1 = New-Object System.Text.UTF8Encoding($False)
[System.IO.File]::WriteAllLines($MyPath1, $MyFile1, $Utf8NoBomEncoding1)
start -WindowStyle Minimized -Wait "C:\temp\TSM_Backup.bat"


$tsmlog = Get-Content C:\temp\TSMlog.txt -encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -like '*Client Version*'} | select-object -last 1
Remove-Item C:\temp\TSMlog.txt -Force -ErrorAction SilentlyContinue
Remove-Item C:\temp\TSM_Backup.bat -Force -ErrorAction SilentlyContinue

if($tsmlog -like $null){
$tsmlog = Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* | Where {($_.DisplayName -eq "IBM Tivoli Storage Manager Client")}  |  Select-Object -expand  DisplayVersion
}
##############################################################################################

#####################LSI Version #############################################################

$LsIDriverVersion = Get-WmiObject Win32_PnPSignedDriver| Where{$_.devicename -like "*lsi*"} | select devicename, driverversion -First 1
$LSIName = $LsIDriverVersion.devicename
$LsIVersion = $LsIDriverVersion.driverversion

##############################################################################################

$Details = @{
Hostname = $Hostname
OSName = $OSName
ServicePack = $ServicePack
OSArchitecture = $osarc
OSVersion = $osversion
NMIRegistry = $NMI
RAM = $RAM
TotalPageFile = $pageresult1
PageFilePath = $pagefileout
EventLogArchiveTool = $log
AntivirusVersion = $avresult
VMToolsVersion = $vmware
SCMService = $SCM 
UAC = $UAC
TSMVersion = $tsmlog
RolesInstalltionPermission = $Roles
CPUinPercent = $cpu
MemoryinPercent = $memory
LSIName = $LSIName
LSIVersion = $LsIVersion
}

$results += New-Object PSObject -Property $Details 

$results | Select Hostname, OSName, OSArchitecture, ServicePack, OSVersion, NMIRegistry, RAM, TotalPageFile, PageFilePath, EventLogArchiveTool, AntivirusVersion, VMToolsVersion, SCMService, UAC, TSMVersion, RolesInstalltionPermission, CPUinPercent, MemoryinPercent,LSIName,LSIVersion | Export-Csv "C:\temp\$Hostname-HealthChk.csv" -Encoding UTF8 -NoTypeInformation
