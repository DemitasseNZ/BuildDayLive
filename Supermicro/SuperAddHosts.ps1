# Script to add add ESX servers to vCenter and do initial configuration
#
#
# Version 0.9
#
#
if (Test-Path C:\PSFunctions.ps1) {
	. "C:\PSFunctions.ps1"
} else {
	Write-BuildLog "PSFunctions.ps1 not found. Please copy all PowerShell files from B:\Automate to C:\ and rerun AddHosts.ps1"
	Read-Host "Press <Enter> to exit"	
	exit
}

$a = (Get-Host).UI.RawUI
$b = $a.WindowSize
$b.Height = $a.MaxWindowSize.Height -1 
$a.WindowSize = $b
Write-BuildLog "Building Primary Site"
$HostPrefix = "host"
$DCName = "Lab"
$ClusterName = "Super"
$SubNet = "199"
$SRM = $False
$StartHost = 3

for ($i=$StartHost;$i -le 6; $i++) {
    $vmhost = "$HostPrefix$i.lab.local"
    $ping = new-object System.Net.NetworkInformation.Ping
    $Reply = $ping.send($vmhost)
    if ($Reply.status –eq "Success") {
		$MaxHosts = $i
    } else {
		$i =10
	}
}
If (!($MaxHosts -ge 2)){
	Write-Host "Couldn't find first two hosts to build, need host1 & host2 built before running this script"
	Read-Host "Build the hosts & rerun this script"
	Exit
}
Write-BuildLog " "
If (!(Test-Path "B:\*")) { Net use B: \\nas\Build}
if (Test-Path "B:\Automate\automate.ini") {
	Write-BuildLog "Determining automate.ini settings."  
	$AdminPWD = ((Select-String -SimpleMatch "Adminpwd=" -Path "B:\Automate\automate.ini").line).substring(9)
} else {
	Write-BuildLog "Unable to find B:\Automate\automate.ini. Where did it go?" 
}
$null = Set-PowerCLIConfiguration -InvalidCertificateAction ignore -confirm:$false
for ($i=$StartHost;$i -le $MaxHosts; $i++) {

    $Num = $i +10
    $VMHost = $HostPrefix
    $VMHost += $i
    $VMHost += ".lab.local"
	try {
		$Connect = Connect-VIServer $VMHost -user root -password $AdminPWD
	}
	catch {
		Write-BuildLog "Unable to connect to ESXi server. Exiting."  
		Read-Host "Press <Enter> to exit" 
		exit
	}
    $VMotionIP = "172.16.$SubNet."
    $VMotionIP += $Num
    $IPStoreIP = "172.17.$SubNet."
    $IPStoreIP += $Num
    Write-BuildLog $VMHost 
  	$VMHostObj = Get-VMHost $VMHost
	if (($vmhostObj.ExtensionData.Config.Product.FullName.Contains("ESXi")) -and ((get-VmHostNtpServer $VMhostobj) -ne "192.168.199.4")) {
		# These services aren't relevant on ESX Classic, only ESXi
		$null = Add-VMHostNtpServer -NtpServer "192.168.199.4" -VMHost $VMhost
		$ntp = Get-VMHostService -VMHost $VMhost | Where {$_.Key -eq "ntpd"}
		$null = Set-VMHostService $ntp -Policy "On"
		$SSH = Get-VMHostService -VMHost $VMhost | Where {$_.Key -eq "TSM-SSH"}
		$null = Set-VMHostService $SSH -Policy "On"
		$TSM = Get-VMHostService -VMHost $VMhost | Where {$_.Key -eq "TSM"}
		$null = Set-VMHostService $TSM -Policy "On"
		if ($vmhostObj.version.split(".")[0] -ne "4") {
			if ($PCLIVerNum -ge 51) {
				$null = Get-AdvancedSetting -Entity $VMHostObj -Name "UserVars.SuppressShellWarning" | Set-AdvancedSetting -Value "1" -confirm:$false
			} else {
				$null = Set-VMHostAdvancedConfiguration -vmhost $VMhost -Name "UserVars.SuppressShellWarning" -Value 1
			}
		}
	}
	$DSName = $VMHost.split('.')[0]
	$DSName += "_Local"
	$sharableIds = Get-ShareableDatastore | Foreach {$_.ID } 
	$null = Get-Datastore -vmhost $vmhost | Where {$sharableIds -notcontains $_.ID } | Set-DataStore -Name $DSName
	$switch = Get-VirtualSwitch -vmHost $vmHostobj 
	if($switch -isnot [system.array]) {
		Write-BuildLog " Configuring network." 
		$null = New-VirtualPortGroup -Name Net900 -VirtualSwitch $switch -VLanId 900
		$null = New-VirtualPortGroup -Name Net901 -VirtualSwitch $switch -VLanId 901
		$null = New-VirtualPortGroup -Name Net902 -VirtualSwitch $switch -VLanId 902
		$null = New-VirtualPortGroup -Name Net903 -VirtualSwitch $switch -VLanId 903
		$null = New-VirtualPortGroup -Name Net904 -VirtualSwitch $switch -VLanId 904
		$null = New-VirtualPortGroup -Name Net905 -VirtualSwitch $switch -VLanId 905
		$null = New-VirtualPortGroup -Name Net906 -VirtualSwitch $switch -VLanId 906
		$null = New-VirtualPortGroup -Name Net907 -VirtualSwitch $switch -VLanId 907
		$null = New-VirtualPortGroup -Name Net908 -VirtualSwitch $switch -VLanId 908
		$null = New-VirtualPortGroup -Name Net909 -VirtualSwitch $switch -VLanId 909
		$null = New-VirtualPortGroup -Name Servers -VirtualSwitch $switch
		$null = New-VirtualPortGroup -Name Workstations -VirtualSwitch $switch
		$null = set-VirtualSwitch $switch -mtu 9000 -confirm:$false 
		$null = Get-AdvancedSetting -Entity $vmHostobj -Name Net.FollowHardwareMac | Set-AdvancedSetting -Value "1" -confirm:$false
		$pg = Get-VirtualPortGroup -name "Management Network"
		$policy = Get-NicTeamingPolicy $pg
		$null = Set-NicTeamingPolicy $policy -InheritFailoverOrder:$True
		$myVMHostNetworkAdapter = Get-VMHostNetworkAdapter -Physical -Name vmnic1
		$null = Add-VirtualSwitchPhysicalNetworkAdapter -VirtualSwitch $switch -VMHostPhysicalNic $myVMHostNetworkAdapter -confirm:$false
		$pg = New-VirtualPortGroup -Name vMotion -VirtualSwitch $switch -VLanId 16
		$null = New-VMHostNetworkAdapter -VMHost $vmhost -Portgroup vMotion -Mtu 9000 -VirtualSwitch $switch -IP $VMotionIP -SubnetMask "255.255.255.0" -vMotionEnabled:$true -ManagementTrafficEnabled:$True
		$pg = New-VirtualPortGroup -Name IPStore -VirtualSwitch $switch  -VLanId 17
		$null = New-VMHostNetworkAdapter -VMHost $vmhost -Portgroup IPStore -Mtu 9000 -VirtualSwitch $switch -IP $IPStoreIP -SubnetMask "255.255.255.0" -VsanTrafficEnabled:$true 
		$null = Get-VMHostStorage $VMHost | Set-VMHostStorage -SoftwareIScsiEnabled $true
		Start-Sleep -Seconds 30
		Write-BuildLog " Add NFS datastores" 
		$null = New-Datastore -nfs -VMhost $vmhost -Name NFS01 -NFSHost "192.168.199.7" -Path "/mnt/LABVOL/NFS01"
		$null = New-Datastore -nfs -VMhost $vmhost -Name NFS02 -NFSHost "192.168.199.7" -Path "/mnt/LABVOL/NFS02"
		$null = remove-datastore -VMhost $vmhost -datastore remote-install-location -confirm:$false
		Write-BuildLog " Configuring iSCSI" 
		$MyIQN = "iqn.1998-01.com.vmware:" + $VMHost.split('.')[0]
		$null = Get-VMHostHba -VMhost $vmhost -Type iScsi | Set-VMHostHBA -IScsiName $MyIQN 
		$null = Get-VMHostHba -VMhost $vmhost -Type iScsi | New-IScsiHbaTarget -Address 192.168.199.7 -Type Send
		$null = Get-VMHostStorage $VMHost -RescanAllHba
	}
	Restart-VMHost $VMHost -RunAsync -force -confirm:$false
	Disconnect-viserver -force -confirm:$false
}
Read-Host "Wait until the last server has come up"
# Exit before doing vCenter
#Exit
# Deploy vCenter here
Write-BuildLog "Connect to vCenter; this takes a while and may show a warning in yellow"  

try {
	$VCServer = "vc.lab.local"
	$Connect = Connect-VIServer $VCServer -user administrator@vsphere.local  -password LetMe1n?
}
catch {
	Write-BuildLog "Unable to connect to vCenter. Exiting."  
	Read-Host "Press <Enter> to exit" 
	exit
}
Write-BuildLog "Create cluster" 
if ((Get-Cluster | where {$_.Name -eq $ClusterName}) -eq $null) {
    $Cluster = New-Cluster $ClusterName -DRSEnabled -Location $DCName -DRSAutomationLevel FullyAutomated
} else {
	$Cluster = Get-Cluster | where {$_.Name -eq $ClusterName}
}
for ($i=$StartHost;$i -le $MaxHosts; $i++) {
	$VMHost = $HostPrefix
    $VMHost += $i
    $VMHost += ".lab.local"
    if ((Get-VMHost | where {$_.Name -eq $VMHost}) -eq $null) {
		Write-BuildLog "Adding $vmhost"
        $Null = Add-VMHost $VMhost -user root -password $AdminPWD -Location $ClusterName -force:$true
		Start-Sleep -Seconds 30
		try {
			$null = Get-VMHost $VMHost
		}
		catch {
			Write-BuildLog "Unable to find " $VMHost "; please verify the host is built and rerun the AddHosts script."
			Read-Host "Press <Enter> to exit"
			exit
		}			
        Start-Sleep 5
		While ((Get-VMHost $VMHost).ConnectionState -ne "Connected"){
            Write-BuildLog " "
            Write-BuildLog $VMHost " is not yet connected. Pausing for 5 seconds."
            Write-BuildLog " "
			Start-Sleep 5
			}
		}
		$null = Move-VMhost $VMHost -Destination $ClusterName
	}
#***************

Write-BuildLog "Setting up VSAN cluster" 
$Cluster = Get-Cluster -Name $ClusterName
Read-Host "Enable VSAN before HA is enabled"
#$VSANCluster = $Cluster | Set-Cluster -VsanEnabled:$true -VsanDiskClaimMode Automatic -Confirm:$false
#Start-Sleep -Seconds 120

Write-BuildLog "Setting up HA on cluster since shared storage is configured." 
$null = set-cluster -cluster $Cluster -HAEnabled:$True -HAAdmissionControlEnabled:$True -confirm:$false
$null = New-AdvancedSetting -Entity $cluster -Type ClusterHA -Name 'das.isolationaddress1' -Value "192.168.$SubNet.4" -confirm:$false -force
$null = New-AdvancedSetting -Entity $cluster -Type ClusterHA -Name 'das.usedefaultisolationaddress' -Value false -confirm:$false -force
$spec = New-Object VMware.Vim.ClusterConfigSpecEx
$null = $spec.dasConfig = New-Object VMware.Vim.ClusterDasConfigInfo
$null = $spec.dasConfig.admissionControlPolicy = New-Object VMware.Vim.ClusterFailoverResourcesAdmissionControlPolicy
$null = $spec.dasConfig.admissionControlPolicy.cpuFailoverResourcesPercent = 50
$null = $spec.dasConfig.admissionControlPolicy.memoryFailoverResourcesPercent = 50
$Cluster = Get-View $Cluster
$null = $Cluster.ReconfigureComputeResource_Task($spec, $true)

$null = Disconnect-VIServer -Server * -confirm:$false
if (Test-Path "C:\Program Files\VMware\VMware Tools\VMwareToolboxCmd.exe") {
	Read-Host " Configuration complete, press <Enter> to continue."
}
exit
