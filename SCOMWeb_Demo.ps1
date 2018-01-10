# SCOMweb.ps1
# Usage:
#	q - Creates new monitor, copies to SCOMSERVER and runs import script
#	e - Opens existing monitor, then saves to SCOMSERVER and runs import script
#	p - Imports 1 monitor to Master XML file, copies to appropriate production server and runs import script
#	u - Copies master XML file to QA or appropriate Prod server and runs import script
# Created by: Mike McGrail

Function fun_GetFileName{
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.initialDirectory = "C:\temp\"
    $OpenFileDialog.filter = "XML (*.xml)| *.xml"
    $OpenFileDialog.ShowDialog() | Out-Null
    $OpenFileDialog.filename
    If ($openFileDialog.filename -eq "") { Exit }													#Exit if no file is selected
}

Function fun_testXML {
    param (     
		[Parameter(ValueFromPipeline=$true, Mandatory=$true)] 
		[string] $XmlFile,  
		[Parameter(Mandatory=$true)] 
		[string] $SchemaFile, 
		[scriptblock] $ValidationEventHandler = { $args[1].Exception | Out-File C:\temp\SCOM_error.txt } 
    ) 

    $xmlTest = New-Object System.Xml.XmlDocument 
    $schemaReader = New-Object System.Xml.XmlTextReader $SchemaFile 
    $schema = [System.Xml.Schema.XmlSchema]::Read($schemaReader, $ValidationEventHandler) 
    $xmlTest.Schemas.Add($schema) | Out-Null
    $xmlTest.Load($XmlFile)
    $xmlTest.Validate($ValidationEventHandler)
    If (Test-Path "C:\temp\SCOM_error.txt"){
        $popUpError = Get-Content C:\temp\SCOM_error.txt
        $popUp = (New-Object -ComObject Wscript.Shell).Popup("The selected XML file is invalid.`n`nDetails: $popUpError`n`nClick OK to exit.",0,"Invalid XML",16)
        Remove-Item C:\temp\SCOM_error.txt
        Exit
    }
}

Function fun_MonScheduler ($monScheduleFunction,$monScheduleCounter,$monStart,$monEnd,$monDays) {
    If ($monScheduleFunction -eq "add") {															#If adding a schedule, create array and determine DaysOfWeekMask based on boxes checked
        If ($monSundayBox.Checked -eq $true) { $monDays += 1 }
	    If ($monMondayBox.Checked -eq $true) { $monDays += 2 }
	    If ($monTuesdayBox.Checked -eq $true) { $monDays += 4 }
	    If ($monWednesdayBox.Checked -eq $true) { $monDays += 8 }
	    If ($monThursdayBox.Checked -eq $true) { $monDays += 16 }
	    If ($monFridayBox.Checked -eq $true) { $monDays += 32 }
	    If ($monSaturdayBox.Checked -eq $true) { $monDays += 64 }
    }
    If ($monScheduleFunction -eq "add" -or "import") {												#If adding or importing schedule, create array and write to temp file
        If ($monScheduleCounter -eq 1) {
            If (Test-Path C:\temp\scomweb_schedule.tmp) { Remove-Item C:\temp\scomweb_schedule.tmp }#Delete temp file, if it exists, to write first schedule entry
        }
        $monScheduleArray = @()
        $monObject = New-Object PSObject
        $monObject | Add-Member -MemberType NoteProperty -Name "Number" -Value $monScheduleCounter
        $monObject | Add-Member -MemberType NoteProperty -Name "Start" -Value $monStart
        $monObject | Add-Member -MemberType NoteProperty -Name "End" -Value $monEnd
        $monObject | Add-Member -MemberType NoteProperty -Name "Days" -Value $monDays
        $monScheduleArray += $monObject
        $monScheduleArray | Export-Csv -NoTypeInformation C:\temp\scomweb_schedule.tmp -Append   
    }
    If ($monScheduleFunction -eq "subtract") {														#If removing schedule, import temp contents to array, clear temp file, rewrite wanted lines to temp file
        $monScheduleArray = Import-Csv C:\temp\scomweb_schedule.tmp | Where-Object {$_.Number -lt ($monScheduleCounter-1)}
        Clear-Content C:\temp\scomweb_schedule.tmp
        $monScheduleArray | ConvertTo-Csv -NoTypeInformation | Set-Content -Path C:\temp\scomweb_schedule.tmp
    }
}

Function fun_DaysConverter ($theMask) {											#Function to check day boxes to match schedule days
    $monSaturdayBox.Checked = $false											#First, uncheck all day boxes
	$monFridayBox.Checked = $false
	$monThursdayBox.Checked = $false
	$monWednesdayBox.Checked = $false
	$monTuesdayBox.Checked = $false
	$monMondayBox.Checked = $false
	$monSundayBox.Checked = $false

	$theMask = [Convert]::ToString($theMask,2).PadLeft(7,'0')					#Convert mask to binary
	If ($theMask.SubString(0,1) -eq "1") { $monSaturdayBox.Checked = $true }	#Check day boxes matching each binary 1
	If ($theMask.SubString(1,1) -eq "1") { $monFridayBox.Checked = $true }
	If ($theMask.SubString(2,1) -eq "1") { $monThursdayBox.Checked = $true }
	If ($theMask.SubString(3,1) -eq "1") { $monWednesdayBox.Checked = $true }
	If ($theMask.SubString(4,1) -eq "1") { $monTuesdayBox.Checked = $true }
	If ($theMask.SubString(5,1) -eq "1") { $monMondayBox.Checked = $true }
	If ($theMask.SubString(6,1) -eq "1") { $monSundayBox.Checked = $true }
}

Function fun_RemoveTempFile {
    If (Test-Path C:\temp\scomweb_schedule.tmp) { Remove-Item C:\temp\scomweb_schedule.tmp }	#Remove temp schedule file if it exists
    If (Test-Path C:\temp\SCOMweb_LogTime.txt) { Remove-Item C:\temp\SCOMweb_LogTime.txt }
    If (Test-Path C:\temp\SCOMweb_$LogTime.xml) { Remove-Item C:\temp\SCOMweb_$LogTime.xml }
}

Function fun_TFS ($TFS_param) {
    . "$PSScriptRoot\Resources\tfs_command.ps1"
    Try {
        Set-Location "C:\SCM\SCOM\SCOM 2016\Web Monitoring XML Files" -ErrorAction Stop
        Invoke-Command -ScriptBlock { & $tfs_command "get" "/recursive" "C:\SCM\SCOM\SCOM 2016\Web Monitoring XML Files" } | Out-Null	#TFS Get latest SCOMURL files
    }
    Catch {
        $popUp = (New-Object -ComObject Wscript.Shell).Popup("TFS Error encountered.`n`nPlease ensure TFS MON\T000065 is mapped to C:\SCM.`n`nClick OK to exit.",0,"File Unavailable",16)
        fun_RemoveTempFile
        Exit
    }
	
	If ($TFS_param -ieq "q" -or $TFS_param -ieq "e") {														#If QA, $environment is passed as q or e
	    $i = 0
	    Do {
		    $i++
		    $tfsResult = Invoke-Command -ScriptBlock { & $tfs_command "status" "QA_Master$i.xml" "/user:$userID" } -ArgumentList $i,$userID		#Loop through QA_Master1-3.xml to see if user has file checked out
		    If ( $tfsResult -match "! edit " ) { Return "QA_Master$i.xml" }																		#Return that file
	    } until ( $i -eq 3 )
        If ($i -eq 3 ) {																												#If user does not have any checked out, counter reaches max
            $i = 0
		    Do {
		        $i++
		        $tfsResult = Invoke-Command -ScriptBlock { & $tfs_command "status" "QA_Master$i.xml" "/user:*" } -ArgumentList $i   	#Loop again through QA_Master1-3.xml...
		        If ( $tfsResult -ieq "There are no pending changes." ) {
			        Invoke-Command -ScriptBlock { & $tfs_command "checkout" "/lock:checkout" "QA_Master$i.xml" } -ArgumentList $i   	#...and check out first file avialable
			        Break
		        }
		        Else {
			        If ($i -eq 3 ) {																									#If counter reaches max with no available files, show popup and exit script
				        $popUp = (New-Object -ComObject Wscript.Shell).Popup("All QA files are currently checked out of TFS.`n`nMonitor saved in C:\temp. Click OK to exit.",0,"No Available Files",16)
                        fun_RemoveTempFile
		    	        Exit
			        }
			    }
            } until ( $i -eq 3 )
        }
    }
    ElseIf ($TFS_param -ieq "undo_pending") {
        Invoke-Command -ScriptBlock { & $tfs_command "undo" "$XMLFile" } -ArgumentList $XMLFile											#Undo checkout if errors are encountered
    }
    Else {																																#If production, $XMLFile is passed for one of 3 servers																								
		$tfsResult = Invoke-Command -ScriptBlock { & $tfs_command "status" "$XMLFile" "/user:$userID" } -ArgumentList $XMLFile,$userID	#Determine if user has $XMLFile checkout out of TFS
		If ( $tfsResult -match "! edit" ) { Return "$XMLFile" }
		Else {
            $tfsResult = Invoke-Command -ScriptBlock { & $tfs_command "status" "$XMLFile" "/user:*" } -ArgumentList $XMLFile			#If not, determine if file is available
            If ( $tfsResult -ieq "There are no pending changes." ) {
                Invoke-Command -ScriptBlock { & $tfs_command "checkout" "/lock:checkout" "$XMLFile" } -ArgumentList $XMLFile			#Check out if available
            }
            Else {
			    $popUp = (New-Object -ComObject Wscript.Shell).Popup("$XMLFile is currently checked out of TFS.`n`nMonitor saved in C:\temp. Click OK to exit.",0,"File Unavailable",16)
                fun_RemoveTempFile																										#If file is not available, show popup and exit script
			    Exit
    		}
        }
    }
}

Function fun_monitorXML ($xml,$monitorXMLFunction) {
	$monNumberCounter = [int]$monNumberLabel.Text
    If (Test-Path C:\temp\SCOMweb_LogTime.txt) { $LogTime = Get-Content C:\temp\SCOMweb_LogTime.txt }
    Else {
		$LogTime = Get-Date -Format "MM-dd_hh-mm-ss" | Out-File C:\temp\SCOMweb_LogTime.txt
		$LogTime = Get-Content C:\temp\SCOMweb_LogTime.txt
    }
    $xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$monNumberCounter]") | % { $_.ParentNode.RemoveChild($_) }

	If ($monitorXMLFunction -eq "Add" -or $monitorXMLFunction -eq "OK") {
	    $monitorError = $null         		#Verify required information, alert if missing anything
	    If ($monBAPDomainBox.Text.Length -eq 0) { $monitorError += "`nBAP Domain is required" }
	    If ($monBAPBox.Text.Length -eq 0) { $monitorError += "`nBAP is required" }
	    If ($monTAPBox.Text.Length -eq 0) { $monitorError += "`nTAP is required" } 
	    If ($monDomainBox.Text.Length -eq 0) { $monitorError += "`nServer Domain is required" }
	    If ($monAuthenticationBox.Text.Length -eq 0) { $monitorError += "`nAuthentication Type is required" }
	    If ($monUserBox.Text.Length -eq 0) { $monitorError += "`nUsername is required" }
	    If ($monPasswordBox.Text.Length -eq 0) { $monitorError += "`nPassword is required" }
	    If ($monNameBox.Text.Length -eq 0) { $monitorError += "`nMonitor Name is required" }
	    If ($monIntervalBox.Text.Length -eq 0) { $monitorError += "`nPoll Interval is required" }
	    If ($monRetriesBox.Text.Length -eq 0) { $monitorError += "`nRetry Count is required" }
	    If ($monServerBox.Text.Length -eq 0) { $monitorError += "`nServer Name is required" }
	    If ($monF5Box.Text.Length -eq 0) { $monitorError += "`nF5 Correlation is required" }
	    If ($monCountBox.Text.Length -eq 0) { $monitorError += "`nError Count is required" }
	    If ($monURLBox.Text.Length -eq 0) { $monitorError += "`nURL is required" }
        If ($xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[@Name='$($monNameBox.Text.ToString())']")) { $monitorError += "`nMonitor name already exists" }
	
        If ($monitorError -ne $null) {
            (New-Object -ComObject Wscript.Shell).Popup("$monitorError",0,"Error Creating Monitor",0x30)
		    Return
	    }
	    If ($monNumberCounter -eq 1) {	#Remove and recreate Domain/BAP/TAP for new XML file
            If ($xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group[@Name='$($monBAPDomainBox.Text.ToString())']")) {
                $xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group[@Name='$($monBAPDomainBox.Text.ToString())']") | % { $_.ParentNode.RemoveChild($_) }
            }
		    $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration").AppendChild($xml.CreateElement("Group"))
		    $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group").AppendChild($xml.CreateElement("Group"))
		    $TAP = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group").AppendChild($xml.CreateElement("Group"))		
		    $xml.WebApplicationMonitoringConfiguration.Group.SetAttribute('Name',$monBAPDomainBox.Text.ToString())
		    $xml.WebApplicationMonitoringConfiguration.Group.Group.SetAttribute('Name',$monBAPBox.Text.ToString())
		    $TAP.SetAttribute('Name',$monTAPBox.Text.ToString())
	    }
		
	    #Create Elements
	    $newMonitor = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group").AppendChild($xml.CreateElement("Monitor"))
	    $newMonitor.AppendChild($xml.CreateElement("Application"))	
	    $newMonitor.AppendChild($xml.CreateElement("StatusCodeCriterias"))
	    $newMonitor.SelectSingleNode("StatusCodeCriterias").AppendChild($xml.CreateElement("StatusCodeCriteria"))
	    $newMonitor.SelectSingleNode("StatusCodeCriterias/StatusCodeCriteria").AppendChild($xml.CreateElement("Operator"))
	    $newMonitor.SelectSingleNode("StatusCodeCriterias/StatusCodeCriteria").AppendChild($xml.CreateElement("Value"))		
	    $newMonitor.AppendChild($xml.CreateElement("ServerName"))
	    $newMonitor.AppendChild($xml.CreateElement("F5Correlation"))
	    $newMonitor.AppendChild($xml.CreateElement("FailureCountThreshold"))
	    $newMonitor.AppendChild($xml.CreateElement("FailureTimeWindow"))
	    $newMonitor.AppendChild($xml.CreateElement("IgnoreInvalidCerts"))
	    $newMonitor.AppendChild($xml.CreateElement("URL"))
	    $newMonitor.AppendChild($xml.CreateElement("ContentMatchCriteria"))
	    $newMonitor.AppendChild($xml.CreateElement("ErrorContentMatchCriteria"))
	    $newMonitor.AppendChild($xml.CreateElement("IgnoreMessageCriteria"))

	    #Set Element values
	    $newMonitor.SetAttribute('Name',$monNameBox.Text.ToString())
	    $newMonitor.SetAttribute('Interval',$monIntervalBox.Text.ToString())
	    $newMonitor.SetAttribute('Authentication',$monAuthenticationBox.Text.ToString())
	    $newMonitor.SetAttribute('CredentialDomain',$monDomainBox.Text.ToString())
	    $newMonitor.SetAttribute('CredentialUserName',$monUserBox.Text.ToString())
	    $newMonitor.SetAttribute('CredentialPassword',$monPasswordBox.Text.ToString())
	    $newMonitor.SetAttribute('RetryCount',$monRetriesBox.Text.ToString())
	    $newMonitor.SetAttribute('RequestTimeout',"120")
	    $newMonitor.StatusCodeCriterias.StatusCodeCriteria.Operator = "Less"
	    $newMonitor.StatusCodeCriterias.StatusCodeCriteria.Value = "300"
	    $newMonitor.Application = $monTAPBox.Text.ToString()
	    $newMonitor.ServerName = $monServerBox.Text.ToString()
	    $newMonitor.F5Correlation = $monF5Box.Text.ToString()
	    $newMonitor.FailureCountThreshold = $monCountBox.Text.ToString()
	    $newMonitor.FailureTimeWindow = ([int]$monIntervalBox.Text * [int]$monCountBox.Text).ToString()
	    $newMonitor.IgnoreInvalidCerts = "true"
	    $newMonitor.URL = $monURLBox.Text.ToString()
	    $newMonitor.IgnoreMessageCriteria = "(?i)Could not establish trust relationship*"

		If ($monContentBox.ForeColor -eq "Black") { $newMonitor.ContentMatchCriteria = $monContentBox.Text.ToString() }            #Add content match, if present
		If ($monContent2Box.ForeColor -eq "Black") { $newMonitor.ErrorContentMatchCriteria = $monContent2Box.Text.ToString() }     #Add error match, if present

		If ($monScheduleBox.Checked -eq $true) {      #If schedule is checked
			If ($monStartTimeBox.ForeColor -eq "Black" -and $monEndTimeBox.ForeColor -eq "Black") {                                #If start and end boxes are completed, call fun_MonSchedule to add on-screen schedule
				$monScheduleCounter = [int]$monScheduleNumberLabel.Text
				fun_MonScheduler ("add")($monScheduleCounter)($monStartTimeBox.Text.ToString())($monEnd = $monEndTimeBox.Text.ToString())(0)
			}
			
			If (Test-Path C:\temp\scomweb_schedule.tmp) {                                                       #If schedule temp file exists, create schedule XML Elements
				$monitorDaily = $newMonitor.AppendChild($xml.CreateElement("Schedule"))
				$monitorDaily.AppendChild($xml.CreateElement("WeeklySchedule"))
				$monitorDaily.SelectSingleNode("WeeklySchedule").AppendChild($xml.CreateElement("Windows"))
				$monitorDaily.AppendChild($xml.CreateElement("ExcludeDates"))
				$monScheduleArray = Import-Csv C:\temp\scomweb_schedule.tmp                                     #Import array from temp file

				ForEach ($i in $monScheduleArray) {                                                             #Loop through array and create schedule Start, End, DaysOfWeekMask Elements
					$monitorDaily = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$monNumberCounter]/Schedule/WeeklySchedule/Windows").AppendChild($xml.CreateElement("Daily"))
					$monitorDaily.AppendChild($xml.CreateElement("Start"))
					$monitorDaily.AppendChild($xml.CreateElement("End"))
					$monitorDaily.AppendChild($xml.CreateElement("DaysOfWeekMask"))
					$monitorDaily.Start = $i.Start
					$monitorDaily.End = $i.End
					$monitorDaily.DaysOfWeekMask = $i.Days
				}
			}
		} #End schedule
	}
    ElseIf ($monitorXMLFunction -eq "Remove") {
        $xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$monNumberCounter]") | % { $_.ParentNode.RemoveChild($_) }
    }
	$xml.Save("C:\temp\SCOMweb_$LogTime.xml")			#Save copy of XML to C:\temp with timestamp in filename
    If ($monitorXMLFunction -ne "OK") { fun_updateDisplay ($xml)($monitorXMLFunction) }
    Else  {
        $OKButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $objForm.Close()
        $LogTime = Get-Content C:\temp\SCOMweb_LogTime.txt
	    If ($environment -ieq 'q' -or $environment -ieq 'e') {								#If environment is 'q' for new QA or 'e' for modify existing QA monitor
	        $SCOMServer = "SCOMSERVER"
		    $fun_TFS = fun_TFS ($environment)				#Call fun_TFS, which will exit if all files are checked out.  If file is available, proceed with copy/import to QA
		    $userQACred = Get-Credential -UserName HSZQA\$userID -Message "Please enter your HSZQA credentials"

            New-PSDrive -Name SCOMQA -PSProvider FileSystem -Root \\$SCOMServer.HSZQA.com\D$ -Credential $userQACred
            Try {
                Copy-Item -Path C:\temp\SCOMweb_$LogTime.xml -Destination SCOMQA:\\SCOMPATH\$fun_TFS -Force -ErrorAction Stop
		        Invoke-Command { powershell.exe -noprofile -executionpolicy Bypass D:\SCOMPATH\Discovery.ps1 } -ComputerName $SCOMServer -Credential $userQACred -ErrorAction Stop
                $popUp = (New-Object -ComObject Wscript.Shell).Popup("File saved as C:\temp\SCOMweb_$LogTime.xml.`n`nImported $fun_TFS to SCOMSERVER; wait for poll period and check status of monitor.`n`nBe sure to Undo Pending Changes in TFS when done testing.",0,"QA Import Successful",64)
            }
            Catch { $popUp = (New-Object -ComObject Wscript.Shell).Popup("Error importing to QA. Exiting.",0,"QA Import Error",48) }
            Finally { Remove-PSDrive SCOMQA }
	    }
	    Elseif ($environment -ieq "p") {																	#If environment is p for production import
            $SCOMServer = "SCOMPROD50"
		    $xml = [xml](Get-Content "C:\temp\SCOMweb_$LogTime.xml")
		    $monBAParray = @(																				#Create array of Domain/BAP/TAP entries
			    $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group").Name,
			    $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group").Name,
			    $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group").Name
		    )
		    If ($monBAParray[0] -eq $null -or $monBAParray[1] -eq $null -or $monBAParray[2] -eq $null) {	#Ensure XML file is valid
			    $popUp = (New-Object -ComObject Wscript.Shell).Popup("Invalid XML file selected. Exiting.",0,"Invalid XML",16)
			    Exit
		    }

		    $userProdCred = Get-Credential -UserName HSZ\$userID -Message "Please enter your HSZ credentials"
		    New-PSDrive -Name SCOMProd -PSProvider FileSystem -Root \\$SCOMServer.HSZ.com\D$ -Credential $userProdCred
		    $BAPcounter = 0
		    ForEach ($BAPentry in $monBAParray) {															#Loop through BAP array; match at beginning of line (denoted by ^) followed by ", URLWebApplication"
			    $MasterGroupList = Select-String -Path SCOMProd:\SCOMPATH\MasterGroupList.txt -Pattern "^$BAPentry, URLWebApplication"
			    If ($MasterGroupList) {
				    $MasterGroupList = $MasterGroupList.Line
				    $XMLFile = $MasterGroupList.Substring($MasterGroupList.IndexOf(", ")+2)
				    Break
			    }
			    $BAPcounter++
		    }
		    If ($BAPcounter -eq 3) {																		#If no Domain/BAP/TAP match, prompt create entry or add to Misc.
			    $popUp = (New-Object -ComObject Wscript.Shell).Popup("Domain/BAP/TAP not found.`n`nClick YES to create new entry, or NO to add to Miscellaneous",0,"No Available Files",51)
			    If ($popUp -eq 6) {																			#If Yes is returned...
				    $masterCount = Import-Csv SCOMProd:\SCOMPATH\MasterMonitorCount.txt -Header "mcFile","mcCount","mcDate" | Where-Object {$_.mcFile -match "^URLWebApplicationSCOMPROD5.A.xml.*" }
				    $masterCount = $masterCount | Sort { [int]$_.mcCount }									#...read MasterMonitorCount.txt to find server with fewest monitors
				    $XMLFile = $masterCount[0].mcFile.ToString()
			    }
			    Elseif ($popUp -eq 7) {																		#If No is returned, add to Misc. on SCOMPROD50
				    $XMLFile = "URLWebApplicationSCOMPROD50A.xml"
				    $monBAParray[2] = "Misc"
			    }
                Elseif ($popUp -eq 2) {
                    fun_RemoveTempFile
                    Exit
                }																							#If Cancel is returned, exit
		    }
		    Remove-PSDrive SCOMProd
		    $fun_TFS = fun_TFS ($XMLFile)																	#Call fun_TFS, which will exit if $XMLFile is unavailable.  If file is available, proceed
		    $masterXML = [xml](Get-Content "C:\SCM\SCOM\SCOM 2016\Web Monitoring XML Files\$XMLFile")
		    $newGroup = $null
		    $newGroup = $masterXML.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group[@Name='$($monBAParray[2])']")
		    If ($newGroup -eq $null) {																		#If Domain is not present, create it
			    $newGroup = $masterXML.SelectSingleNode("//WebApplicationMonitoringConfiguration").AppendChild($masterXML.CreateElement("Group"))
			    $newGroup.SetAttribute('Name',$monBAParray[2])
		    }
		    $newGroup = $masterXML.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group[@Name='$($monBAParray[1])']")
		    If ($newGroup -eq $null) {																		#If BAP is not present, create it
			    $newGroup = $masterXML.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group[@Name='$($monBAParray[2])']").AppendChild($masterXML.CreateElement("Group"))
			    $newGroup.SetAttribute('Name',$monBAParray[1])
		    }
		    $newGroup = $masterXML.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group[@Name='$($monBAParray[0])']")
		    If ($newGroup -eq $null) {																		#If TAP is not present, create it
			    $newGroup = $masterXML.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group[@Name='$($monBAParray[1])']").AppendChild($masterXML.CreateElement("Group"))
			    $newGroup.SetAttribute('Name',$monBAParray[0])
		    }
		    $newGroup = $masterXML.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group[@Name='$($monBAParray[0])']")
		    ForEach ($XMLNode in $xml.DocumentElement.Group.Group.Group.ChildNodes) {						#Add monitor elements to TAP
			    $newGroup.AppendChild($masterXML.ImportNode($XMLNode, $true))
		    }
            $masterXML.Save("C:\SCM\SCOM\SCOM 2016\Web Monitoring XML Files\$XMLFile")
            $SCOMServer = $XMLFile.Substring(17,8)
            $SCOMProdNumber = "C:\SCM\SCOM\SCOM 2016\Web Monitoring XML Files\$XMLFile".Substring(70,2)
		    New-PSDrive -Name SCOMProd -PSProvider FileSystem -Root \\$SCOMServer.HSZ.com\D$ -Credential $userProdCred
            Try {
                Move-Item -Path SCOMPROD:\\SCOMPATH\$XMLFile -Destination SCOMPROD:\\SCOMPATH\$XMLFile.bak -Force
                Copy-Item -Path "C:\SCM\SCOM\SCOM 2016\Web Monitoring XML Files\$XMLFile" -Destination SCOMProd:\SCOMPATH\$XMLFile -Force -ErrorAction Stop
                Invoke-Command { param ($SCOMProdNumber) powershell.exe -noprofile -executionpolicy Bypass D:\SCOMPATH\Discovery$SCOMProdNumber.ps1 } -ComputerName $SCOMServer -ArgumentList $SCOMProdNumber -Credential $userProdCred
                Invoke-Command { schtasks /Run /TN "Master Groups File Creation"} -ComputerName $SCOMServer -Credential $userPRODCred					#Must run scheduled task because ReadFile4.ps1 does not work when run remotely
                Remove-Item "C:\temp\SCOMweb_$LogTime.xml"
                $popUp = (New-Object -ComObject Wscript.Shell).Popup("Imported $XMLFile to $SCOMServer.`n`nBe sure to add comments and check file into TFS.",0,"Prod Import Successful",64)
            }
            Catch {																							#If errors are encountered, undo checkout of master file and show popup error
                fun_TFS ("undo_pending")
                $popUp = (New-Object -ComObject Wscript.Shell).Popup("Error importing to Production. Exiting.",0,"Production Import Error",48)
            }
            Finally { Remove-PSDrive SCOMProd }
	    } #END PROD
        If (Test-Path C:\temp\scomweb_schedule.tmp) { Remove-Item C:\temp\scomweb_schedule.tmp }	#Remove temp schedule file if it exists
        If (Test-Path C:\temp\SCOMweb_LogTime.txt) { Remove-Item C:\temp\SCOMweb_LogTime.txt }
    }
}

Function fun_updateDisplay ($xml,$monitorXMLFunction) {
	$monBAPDomainBox.Text = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group").Name
	$monBAPBox.Text = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group").Name
	$monTAPBox.Text = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group").Name
	
	$countMonitors = $xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor").Count

	$monDetails = $xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$countMonitors]")
	$monAuthenticationBox.Text = $monDetails.Authentication
	$monDomainBox.Text = $monDetails.CredentialDomain
	$monUserBox.Text = $monDetails.CredentialUserName
	$monPasswordBox.Text = $monDetails.CredentialPassword
	$monNameBox.Text = $monDetails.Name
	$monIntervalBox.Text = $monDetails.Interval
	$monRetriesBox.Text = $monDetails.RetryCount
	$monServerBox.Text = $monDetails.ServerName
	$monF5Box.Text = $monDetails.F5Correlation
	$monCountBox.Text = $monDetails.FailureCountThreshold
	$monURLBox.Text = $monDetails.URL

	If ($monDetails.ContentMatchCriteria -ne "") {
        $monContentBox.ForeColor = "Black"
	    $monContentBox.Text = $monDetails.ContentMatchCriteria
    }
    Else {
        $monContentBox.Text = "(?i)text for case-insensitive"
        $monContentBox.ForeColor = "Gray"
    }
	If ($monDetails.ErrorContentMatchCriteria -ne "") {
        $monContent2Box.ForeColor = "Black"
	    $monContent2Box.Text = $monDetails.ErrorContentMatchCriteria
    }
    Else {
        $monContent2Box.Text = "(?i)text for case-insensitive"
        $monContent2Box.ForeColor = "Gray"
    }

	$countSchedules = $xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$countMonitors]/Schedule/WeeklySchedule/Windows/Daily").Count
	If ($countSchedules -gt 0) {                                                  #If schedules are present, show fields on form and display last schedule
		$monScheduleBox.Checked = $true
		$monScheduleMinus.Enabled = $true
		$monScheduleNumberLabel.Text = $countSchedules
		$monStartTimeBox.ForeColor = "Black"
		$monEndTimeBox.ForeColor = "Black"
		$monStartTimeBox.Text = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$countMonitors]/Schedule/WeeklySchedule/Windows/Daily[$countSchedules]").Start
		$monEndTimeBox.Text = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$countMonitors]/Schedule/WeeklySchedule/Windows/Daily[$countSchedules]").End
		
		$theMask = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$countMonitors]/Schedule/WeeklySchedule/Windows/Daily[$countSchedules]").DaysOfWeekMask
        fun_DaysConverter ($theMask)
	
		For ($i=1; $i -le $countSchedules-1; $i++) {                              #Loop through schedules and call fun_MonScheduler to write schedules (except last one, which is displayed instead) to temp file
			$monStart = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$countMonitors]/Schedule/WeeklySchedule/Windows/Daily[$i]").Start
			$monEnd = $xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group/Monitor[$countMonitors]/Schedule/WeeklySchedule/Windows/Daily[$i]").End
			$monDays = [int]$xml.SelectSingleNode("//WebApplicationMonitoringConfiguration/Group/Group/Group[$countMonitors]/Monitor/Schedule/WeeklySchedule/Windows/Daily[$i]").DaysOfWeekMask
			fun_MonScheduler ("import")($i)($monStart)($monEnd)($monDays)
		}
	}
    Else {
        $monScheduleBox.Checked = $false
    }

    If ($monitorXMLFunction -eq "Add") {
        $monNumberLabel.Text = [int]$monNumberLabel.Text + 1
	    $monBAPDomainBox.Enabled = $false
	    $monBAPBox.Enabled = $false
	    $monTAPBox.Enabled = $false
        $monNumberMinus.Enabled = $true
    }
    ElseIf ($monitorXMLFunction -eq "Remove") {
        $monNumberLabel.Text = [int]$monNumberLabel.Text - 1
        If ($countMonitors -eq 1) {
            $monNumberMinus.Enabled = $false
		    $monBAPDomainBox.Enabled = $true
		    $monBAPBox.Enabled = $true
		    $monTAPBox.Enabled = $true
	    }
    }
    ElseIf ($monitorXMLFunction -eq "Import" ) {
        $monNumberLabel.Text = $countMonitors
        If ($countMonitors -gt 1) {
            $monBAPDomainBox.Enabled = $false
            $monBAPBox.Enabled = $false
            $monTAPBox.Enabled = $false
            $monNumberMinus.Enabled = $true
        }
    }
}

###################################### MAIN APPLICATION ######################################
$userID = [Environment]::UserName

$FirstTitle = "SCOM Web Monitoring"															#Prompt for function
$FirstInfo = "Select Function"
$FirstOptions = [System.Management.Automation.Host.ChoiceDescription[]] @("&New ", "&Modify QA Monitor", "&Prod. Import", "Master File &Update")
[int]$defaultchoice = 0
$FirstOpt =  $host.UI.PromptForChoice($FirstTitle,$FirstInfo,$FirstOptions,$defaultchoice)
switch($FirstOpt)
{
    0 { $environment = "q" }
    1 { $environment = "e" }
    2 { $environment = "p" }
    3 { $environment = "u" }
}

If ($environment -ieq "u") {																#If Master Update is selected, attempt to copy/import then exit script

    $inputfile = fun_GetFileName
	Try { $xml = [xml](Get-Content $inputfile) }													#Verify XML is valid and check against schema
	Catch {
		$popUp = (New-Object -ComObject Wscript.Shell).Popup("The selected XML file is invalid.`n`nClick OK to exit.",0,"Invalid XML",16)
		Exit
	}
	fun_testXML -XmlFile $inputfile -SchemaFile '\\server08\\WebConfig.xsd'

    $XMLFile = Get-ChildItem $inputfile | select -expand basename
    $XMLFile += ".xml"											
    If (($inputfile.Substring(0,6) -eq "C:\SCM") -and ($XMLFile -like "URLWebApplicationSCOMPROD5*A.xml")) {	#If Master XML file is selected, determine production server from filename
        $fun_TFS = fun_TFS ($XMLFile)
        $SCOMServer = $inputfile.Substring(64,8)
        $SCOMProdNumber = $inputfile.Substring(70,2)
        $userProdCred = Get-Credential -UserName HSZ\$userID -Message "Please enter your HSZ credentials"

        New-PSDrive -Name SCOMProd -PSProvider FileSystem -Root \\$SCOMServer.HSZ.com\D$ -Credential $userProdCred
        Try {
            Move-Item -Path SCOMProd:\SCOMPATH\$fun_TFS -Destination SCOMProd:\SCOMPATH\$fun_TFS.bak -Force -ErrorAction Stop
            Copy-Item -Path $inputfile -Destination SCOMProd:\SCOMPATH\$fun_TFS -Force -ErrorAction Stop
		    Invoke-Command { param ($SCOMProdNumber) powershell.exe -noprofile -executionpolicy Bypass D:\SCOMPATH\OnDemandDiscovery_P$SCOMProdNumber.ps1 } -ComputerName $SCOMServer -ArgumentList $SCOMProdNumber -Credential $userProdCred
            $popUp = (New-Object -ComObject Wscript.Shell).Popup("$fun_TFS to production on $SCOMServer.`n`nBe sure to check changes into TFS.",0,"Production Import Successful",64)
        }
        Catch { $popUp = (New-Object -ComObject Wscript.Shell).Popup("Error importing $fun_TFS to $SCOMServer. Exiting.",0,"Production Import Error",48) }
        Finally { Remove-PSDrive SCOMProd }
    }
    Else {																					#If file is not production
        If ($XMLFile -like "QA_Master*.xml") { $fun_TFS = fun_TFS ($XMLFile) }				#If QA_Master file is selected, call fun_TFS with the filename
        Else { $fun_TFS = fun_TFS ("e") }													#If other file is selected, call fun_TFS with "e" to check any available QA file

        $SCOMServer = "SCOMSERVER"
        $userQACred = Get-Credential -UserName HSZQA\$userID -Message "Please enter your HSZQA credentials"

        New-PSDrive -Name SCOMQA -PSProvider FileSystem -Root \\$SCOMServer.HSZQA.com\D$ -Credential $userQACred
        Try {
            Copy-Item -Path $inputfile -Destination SCOMQA:\\SCOMPATH\$fun_TFS -Force -ErrorAction Stop
		    Invoke-Command { powershell.exe -noprofile -executionpolicy Bypass D:\SCOMPATH\OnDemandDiscovery_Q50.ps1 } -ComputerName $SCOMServer -Credential $userQACred -ErrorAction Stop
            $popUp = (New-Object -ComObject Wscript.Shell).Popup("Imported $fun_TFS to SCOMSERVER.`n`nBe sure to Undo Pending Changes in TFS when done testing.",0,"QA Import Successful",64)
        }
        Catch { $popUp = (New-Object -ComObject Wscript.Shell).Popup("Error importing $fun_TFS to QA. Exiting.",0,"QA Import Error",48) }
        Finally { Remove-PSDrive SCOMQA }
    }
    fun_RemoveTempFile
    Exit
}

###################################### GUI FORM ######################################
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")					#GUI Form for all functions except Master Update
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
$objForm = New-Object System.Windows.Forms.Form
$objForm.Text = "SCOM URL Monitor"
$objForm.Size = New-Object System.Drawing.Size(620,665) 
$objForm.StartPosition = "CenterScreen"
$helpFont = New-Object System.Drawing.Font("Arial",8,[System.Drawing.FontStyle]::Italic)

$monBAPEntryLabel = New-Object System.Windows.Forms.Label
$monBAPEntryLabel.Location = New-Object System.Drawing.Size(10,20) 
$monBAPEntryLabel.Size = New-Object System.Drawing.Size(132,20) 
$monBAPEntryLabel.Text = "BAP ENTRY  -  reference"
$objForm.Controls.Add($monBAPEntryLabel)

$monBAPEntryLinkLabel = New-Object System.Windows.Forms.LinkLabel
$monBAPEntryLinkLabel.Location = New-Object System.Drawing.Size(139,20) 
$monBAPEntryLinkLabel.Size = New-Object System.Drawing.Size(100,20) 
$monBAPEntryLinkLabel.Text = "http://bap"
$monBAPEntryLinkLabel.LinkColor = "BLUE"
$monBapEntryLinkLabel.add_Click({[system.Diagnostics.Process]::start("http://bap")}) 
$objForm.Controls.Add($monBAPEntryLinkLabel)

$monBAPDomainLabel = New-Object System.Windows.Forms.Label
$monBAPDomainLabel.Location = New-Object System.Drawing.Size(20,45) 
$monBAPDomainLabel.Size = New-Object System.Drawing.Size(120,20) 
$monBAPDomainLabel.Text = "Domain (Level 1):"
$objForm.Controls.Add($monBAPDomainLabel) 

$monBAPDomainBox = New-Object System.Windows.Forms.TextBox 
$monBAPDomainBox.Location = New-Object System.Drawing.Size(140,45) 
$monBAPDomainBox.Size = New-Object System.Drawing.Size(140,20) 
$objForm.Controls.Add($monBAPDomainBox)

$monBAPLabel = New-Object System.Windows.Forms.Label
$monBAPLabel.Location = New-Object System.Drawing.Size(20,70) 
$monBAPLabel.Size = New-Object System.Drawing.Size(120,20) 
$monBAPLabel.Text = "BAP (Level 2):"
$objForm.Controls.Add($monBAPLabel) 

$monBAPBox = New-Object System.Windows.Forms.TextBox 
$monBAPBox.Location = New-Object System.Drawing.Size(140,70) 
$monBAPBox.Size = New-Object System.Drawing.Size(140,20) 
$objForm.Controls.Add($monBAPBox)

$monTAPLabel = New-Object System.Windows.Forms.Label
$monTAPLabel.Location = New-Object System.Drawing.Size(20,95) 
$monTAPLabel.Size = New-Object System.Drawing.Size(120,20) 
$monTAPLabel.Text = "TAP (Level 3):"
$objForm.Controls.Add($monTAPLabel) 

$monTAPBox = New-Object System.Windows.Forms.TextBox 
$monTAPBox.Location = New-Object System.Drawing.Size(140,95) 
$monTAPBox.Size = New-Object System.Drawing.Size(140,20) 
$objForm.Controls.Add($monTAPBox)

$monSecurityLabel = New-Object System.Windows.Forms.Label
$monSecurityLabel.Location = New-Object System.Drawing.Size(310,20) 
$monSecurityLabel.Size = New-Object System.Drawing.Size(120,20) 
$monSecurityLabel.Text = "SECURITY"
$objForm.Controls.Add($monSecurityLabel)

$monAuthenticationLabel = New-Object System.Windows.Forms.Label
$monAuthenticationLabel.Location = New-Object System.Drawing.Size(320,45) 
$monAuthenticationLabel.Size = New-Object System.Drawing.Size(120,20) 
$monAuthenticationLabel.Text = "Authentication:"
$objForm.Controls.Add($monAuthenticationLabel) 

$monAuthentication=@("Negotiate","Basic","NTLM","Digest","None")
$monAuthenticationBox = New-Object System.Windows.Forms.ComboBox 
$monAuthenticationBox.Location = New-Object System.Drawing.Size(440,45) 
$monAuthenticationBox.Size = New-Object System.Drawing.Size(140,20) 
$monAuthenticationBox.DropDownHeight = 70
$monAuthenticationBox.SelectedItem = 0
$monAuthenticationBox.Text = "Negotiate"
$objForm.Controls.Add($monAuthenticationBox)
ForEach ($monAuth in $monAuthentication) { $monAuthenticationBox.Items.Add($monAuth) }

$monDomainLabel = New-Object System.Windows.Forms.Label
$monDomainLabel.Location = New-Object System.Drawing.Size(320,70) 
$monDomainLabel.Size = New-Object System.Drawing.Size(120,20) 
$monDomainLabel.Text = "Server Domain:"
$objForm.Controls.Add($monDomainLabel) 

$monDomain=@("PRIMARY","HSZ","DMZ")
$monDomainBox = New-Object System.Windows.Forms.ComboBox 
$monDomainBox.Location = New-Object System.Drawing.Size(440,70) 
$monDomainBox.Size = New-Object System.Drawing.Size(140,20) 
$monDomainBox.DropDownHeight = 70
$objForm.Controls.Add($monDomainBox)
ForEach ($monDom in $monDomain) { $monDomainBox.Items.Add($monDom) }
$monDomainBox.Add_SelectedIndexChanged({                             #Populate username and password based on selected Domain
	If ($monDomainBox.Text -eq "PRIMARY") { 
		$monUserBox.Text = "PRIMARYID"; $monPasswordBox.Text = "*****"
	}
	ElseIf ($monDomainBox.Text -eq "HSZ") {
		$monUserBox.Text = "HSZID"; $monPasswordBox.Text = "*****"
	}
	ElseIf ($monDomainBox.Text -eq "DMZ") {
		$monUserBox.Text = "DMZID"; $monPasswordBox.Text = "*****"
	}
})

$monUserLabel = New-Object System.Windows.Forms.Label
$monUserLabel.Location = New-Object System.Drawing.Size(320,95)
$monUserLabel.Size = New-Object System.Drawing.Size(120,20)
$monUserLabel.Text = "Username:"
$objForm.Controls.Add($monUserLabel) 

$monUserBox = New-Object System.Windows.Forms.TextBox
$monUserBox.Location = New-Object System.Drawing.Size(440,95)
$monUserBox.Size = New-Object System.Drawing.Size(140,20)
$objForm.Controls.Add($monUserBox)

$monPasswordLabel = New-Object System.Windows.Forms.Label
$monPasswordLabel.Location = New-Object System.Drawing.Size(320,120)
$monPasswordLabel.Size = New-Object System.Drawing.Size(120,20)
$monPasswordLabel.Text = "Password:"
$objForm.Controls.Add($monPasswordLabel) 

$monPasswordBox = New-Object System.Windows.Forms.TextBox
$monPasswordBox.PasswordChar = "●"
$monPasswordBox.Location = New-Object System.Drawing.Size(440,120)
$monPasswordBox.Size = New-Object System.Drawing.Size(140,20)
$objForm.Controls.Add($monPasswordBox)

$monDetailsLabel = New-Object System.Windows.Forms.Label
$monDetailsLabel.Location = New-Object System.Drawing.Size(10,145) 
$monDetailsLabel.Size = New-Object System.Drawing.Size(120,20) 
$monDetailsLabel.Text = "MONITOR DETAILS"
$objForm.Controls.Add($monDetailsLabel) 

$monNameLabel = New-Object System.Windows.Forms.Label
$monNameLabel.Location = New-Object System.Drawing.Size(20,170) 
$monNameLabel.Size = New-Object System.Drawing.Size(120,20) 
$monNameLabel.Text = "Monitor Name:"
$objForm.Controls.Add($monNameLabel) 

$monNameBox = New-Object System.Windows.Forms.TextBox 
$monNameBox.Location = New-Object System.Drawing.Size(140,170) 
$monNameBox.Size = New-Object System.Drawing.Size(140,20) 
$objForm.Controls.Add($monNameBox)

$monIntervalLabel = New-Object System.Windows.Forms.Label
$monIntervalLabel.Location = New-Object System.Drawing.Size(20,195) 
$monIntervalLabel.Size = New-Object System.Drawing.Size(120,20) 
$monIntervalLabel.Text = "Poll Interval (seconds):"
$objForm.Controls.Add($monIntervalLabel) 

$monIntervalOptions=@("300","600","1200")
$monIntervalBox = New-Object System.Windows.Forms.ComboBox
$monIntervalBox.Location = New-Object System.Drawing.Size(140,195) 
$monIntervalBox.Size = New-Object System.Drawing.Size(140,20)
$monIntervalBox.DropDownHeight = 70
$objForm.Controls.Add($monIntervalBox)
ForEach ($monIntOpt in $monIntervalOptions) { $monIntervalBox.Items.Add($monIntOpt) }

$monIntervalHelpLabel = New-Object System.Windows.Forms.Label
$monIntervalHelpLabel.Location = New-Object System.Drawing.Size(290,195) 
$monIntervalHelpLabel.Size = New-Object System.Drawing.Size(235,20) 
$monIntervalHelpLabel.Text = "300 is 5 mins., 600 is 10 mins., 1200 is 20 mins"
$monIntervalHelpLabel.Font = $helpFont
$objForm.Controls.Add($monIntervalHelpLabel) 

$monRetriesLabel = New-Object System.Windows.Forms.Label
$monRetriesLabel.Location = New-Object System.Drawing.Size(20,220) 
$monRetriesLabel.Size = New-Object System.Drawing.Size(120,20) 
$monRetriesLabel.Text = "Retry Count:"
$objForm.Controls.Add($monRetriesLabel) 

$monRetriesBox = New-Object System.Windows.Forms.TextBox 
$monRetriesBox.Location = New-Object System.Drawing.Size(140,220) 
$monRetriesBox.Size = New-Object System.Drawing.Size(140,20)
$monRetriesBox.Text = "2"
$objForm.Controls.Add($monRetriesBox)

$monRetriesHelpLabel = New-Object System.Windows.Forms.Label
$monRetriesHelpLabel.Location = New-Object System.Drawing.Size(290,220) 
$monRetriesHelpLabel.Size = New-Object System.Drawing.Size(220,20) 
$monRetriesHelpLabel.Text = "# immediate retries before failure (default 2)"
$monRetriesHelpLabel.Font = $helpFont
$objForm.Controls.Add($monRetriesHelpLabel) 

$monServerLabel = New-Object System.Windows.Forms.Label
$monServerLabel.Location = New-Object System.Drawing.Size(20,245) 
$monServerLabel.Size = New-Object System.Drawing.Size(120,20) 
$monServerLabel.Text = "Server Name:"
$objForm.Controls.Add($monServerLabel) 

$monServerBox = New-Object System.Windows.Forms.TextBox 
$monServerBox.Location = New-Object System.Drawing.Size(140,245) 
$monServerBox.Size = New-Object System.Drawing.Size(140,20) 
$objForm.Controls.Add($monServerBox)

$monF5Label = New-Object System.Windows.Forms.Label
$monF5Label.Location = New-Object System.Drawing.Size(20,270) 
$monF5Label.Size = New-Object System.Drawing.Size(120,20) 
$monF5Label.Text = "F5 Correlation:"
$objForm.Controls.Add($monF5Label) 

$monF5Correlation=@("No","Pull")
$monF5Box = New-Object System.Windows.Forms.ComboBox 
$monF5Box.Location = New-Object System.Drawing.Size(140,270) 
$monF5Box.Size = New-Object System.Drawing.Size(140,20) 
$monF5Box.DropDownHeight = 70
$objForm.Controls.Add($monF5Box)
ForEach ($monF5 in $monF5Correlation) { $monF5Box.Items.Add($monF5) }

$monCountLabel = New-Object System.Windows.Forms.Label
$monCountLabel.Location = New-Object System.Drawing.Size(20,295) 
$monCountLabel.Size = New-Object System.Drawing.Size(120,20) 
$monCountLabel.Text = "Error on Count:"
$objForm.Controls.Add($monCountLabel) 

$monCountOptions =@("2","3")
$monCountBox = New-Object System.Windows.Forms.ComboBox 
$monCountBox.Location = New-Object System.Drawing.Size(140,295) 
$monCountBox.Size = New-Object System.Drawing.Size(140,20) 
$monCountBox.DropDownHeight = 70
$objForm.Controls.Add($monCountBox)
ForEach ($monCntOpt in $monCountOptions) { $monCountBox.Items.Add($monCntOpt) }

$monCountHelpLabel = New-Object System.Windows.Forms.Label
$monCountHelpLabel.Location = New-Object System.Drawing.Size(290,295) 
$monCountHelpLabel.Size = New-Object System.Drawing.Size(215,20) 
$monCountHelpLabel.Text = "# of consecutive failures to generate alert"
$monCountHelpLabel.Font = $helpFont
$objForm.Controls.Add($monCountHelpLabel) 

$monURLLabel = New-Object System.Windows.Forms.Label
$monURLLabel.Location = New-Object System.Drawing.Size(20,320) 
$monURLLabel.Size = New-Object System.Drawing.Size(120,20) 
$monURLLabel.Text = "URL:"
$objForm.Controls.Add($monURLLabel) 

$monURLBox = New-Object System.Windows.Forms.TextBox 
$monURLBox.Location = New-Object System.Drawing.Size(140,320) 
$monURLBox.Size = New-Object System.Drawing.Size(440,20) 
$objForm.Controls.Add($monURLBox)

$monOptionsLabel = New-Object System.Windows.Forms.Label
$monOptionsLabel.Location = New-Object System.Drawing.Size(10,370) 
$monOptionsLabel.Size = New-Object System.Drawing.Size(240,20) 
$monOptionsLabel.Text = "ADDITIONAL OPTIONS"
$objForm.Controls.Add($monOptionsLabel) 

$monContentLabel = New-Object System.Windows.Forms.Label
$monContentLabel.Location = New-Object System.Drawing.Size(20,395) 
$monContentLabel.Size = New-Object System.Drawing.Size(120,20) 
$monContentLabel.Text = "Content Match:"
$objForm.Controls.Add($monContentLabel) 

$monContentBox = New-Object System.Windows.Forms.TextBox 
$monContentBox.Location = New-Object System.Drawing.Size(140,395) 
$monContentBox.Size = New-Object System.Drawing.Size(140,20) 
$monContentBox.Text = "(?i)text for case-insensitive"
$monContentBox.ForeColor = "Gray"
$monContentBox.Add_GotFocus({                                 #Clear help text on focus
	If ($monContentBox.ForeColor -eq "Gray") {
		$monContentBox.Text = ""
		$monContentBox.ForeColor = "Black"
	}
})
$monContentBox.Add_LostFocus({                                #Replace help text upon exiting if empty
	If ($monContentBox.Text.Length -eq 0) { 
		$monContentBox.Text = "(?i)text for case-insensitive"
		$monContentBox.ForeColor = "Gray"
	}    
	})
$objForm.Controls.Add($monContentBox)

$monContentHelpLabel = New-Object System.Windows.Forms.Label  #Content Match
$monContentHelpLabel.Location = New-Object System.Drawing.Size(290,395) 
$monContentHelpLabel.Size = New-Object System.Drawing.Size(215,20) 
$monContentHelpLabel.Text = "Error if not matched"
$monContentHelpLabel.Font = $helpFont
$objForm.Controls.Add($monContentHelpLabel) 

$monContent2Label = New-Object System.Windows.Forms.Label     #Error Content Match
$monContent2Label.Location = New-Object System.Drawing.Size(20,420) 
$monContent2Label.Size = New-Object System.Drawing.Size(120,20) 
$monContent2Label.Text = "Error if Matched:"
$objForm.Controls.Add($monContent2Label) 

$monContent2Box = New-Object System.Windows.Forms.TextBox 
$monContent2Box.Location = New-Object System.Drawing.Size(140,420) 
$monContent2Box.Size = New-Object System.Drawing.Size(140,20)
$monContent2Box.Text = "(?i)text for case-insensitive"
$monContent2Box.ForeColor = "Gray"
$monContent2Box.Add_GotFocus({                                #Clear help text on focus
	If ($monContent2Box.ForeColor -eq "Gray") {
		$monContent2Box.Text = ""
		$monContent2Box.ForeColor = "Black"
	}
})
$monContent2Box.Add_LostFocus({                               #Replace help text upon exiting if empty
	If ($monContent2Box.Text.Length -eq 0) {
		$monContent2Box.Text = "(?i)text for case-insensitive"
		$monContent2Box.ForeColor = "Gray"
	}    
})
$objForm.Controls.Add($monContent2Box)

$monContent2HelpLabel = New-Object System.Windows.Forms.Label
$monContent2HelpLabel.Location = New-Object System.Drawing.Size(290,420) 
$monContent2HelpLabel.Size = New-Object System.Drawing.Size(215,20) 
$monContent2HelpLabel.Text = "Error if content *is* matched"
$monContent2HelpLabel.Font = $helpFont
$objForm.Controls.Add($monContent2HelpLabel) 

$monScheduleBox = New-Object System.Windows.Forms.CheckBox 
$monScheduleBox.Location = New-Object System.Drawing.Size(20,455) 
$monScheduleBox.Size = New-Object System.Drawing.Size(110,20)
$monScheduleBox.Checked = $false
$monScheduleBox.Text = "Schedule"
$objForm.Controls.Add($monScheduleBox)

$scheduleGroupBox = New-Object System.Windows.Forms.GroupBox
$scheduleGroupBox.Location = New-Object System.Drawing.Size(130,445)
$scheduleGroupBox.Size = New-Object System.Drawing.Size(455,85)
$scheduleGroupBox.Text = ""
$scheduleGroupBox.Visible = $false
$monScheduleBox.Add_CheckStateChanged({	                        #Show or hide schedule fields if the schedule option is changed
	If ($monScheduleBox.Checked -eq $true) {
		$scheduleGroupBox.Visible = $true
		$monScheduleCounter = 0
		$monScheduleNumberLabel.Text = [int]$monScheduleCounter + 1
		$monScheduleMinus.Enabled = $false
	}
	Else {
		$scheduleGroupBox.Visible = $false
	}
})
$objForm.Controls.Add($scheduleGroupBox)

#Schedule
$monScheduleMinus = New-Object System.Windows.Forms.Button
$monScheduleMinus.Location = New-Object System.Drawing.Point(10,10)
$monScheduleMinus.Size = New-Object System.Drawing.Size(20,20)
$monScheduleMinus.Text = "-"
$monScheduleMinus.add_Click({
	$monScheduleCounter = [int]$monScheduleNumberLabel.Text
	If ($monScheduleCounter -eq 2) { $monScheduleMinus.Enabled = $false }
	$monScheduleNumberLabel.Text = $monScheduleCounter - 1
	$monStartTimeBox.ForeColor = "Black"
	$monEndTimeBox.ForeColor = "Black"

	$monScheduleArray = Import-Csv C:\temp\scomweb_schedule.tmp | Where-Object {$_.Number -eq ($monScheduleCounter-1)}
	$monStartTimeBox.Text = $monScheduleArray.Start
	$monEndTimeBox.Text = $monScheduleArray.End
	fun_MonScheduler ("subtract")($monScheduleCounter)($monStartTimeBox.Text.ToString())($monEndTimeBox.Text.ToString())(0)
    fun_DaysConverter ($monScheduleArray.Days)
})
$scheduleGroupBox.Controls.Add($monScheduleMinus)

$monScheduleLabel = New-Object System.Windows.Forms.Label
$monScheduleLabel.Location = New-Object System.Drawing.Size(60,13)
$monScheduleLabel.Size = New-Object System.Drawing.Size(55,20)
$monScheduleLabel.Text = "Schedule:"
$scheduleGroupBox.Controls.Add($monScheduleLabel) 

$monScheduleNumberLabel = New-Object System.Windows.Forms.Label
$monScheduleNumberLabel.Location = New-Object System.Drawing.Size(115,13)
$monScheduleNumberLabel.Size = New-Object System.Drawing.Size(20,20)
$scheduleGroupBox.Controls.Add($monScheduleNumberLabel)

$monSchedulePlus = New-Object System.Windows.Forms.Button
$monSchedulePlus.Location = New-Object System.Drawing.Point(150,10)
$monSchedulePlus.Size = New-Object System.Drawing.Size(20,20)
$monSchedulePlus.Text = "+"
$monSchedulePlus.add_Click({
	If ($monStartTimeBox.ForeColor -eq "Black" -and $monEndTimeBox.ForeColor -eq "Black") {
		$monScheduleCounter = [int]$monScheduleNumberLabel.Text
		fun_MonScheduler ("add")($monScheduleCounter)($monStartTimeBox.Text.ToString())($monEndTimeBox.Text.ToString())(0)
		$monScheduleNumberLabel.Text = $monScheduleCounter + 1
		$monScheduleMinus.Enabled = $true
		$monStartTimeBox.ForeColor = "Gray"
		$monEndTimeBox.ForeColor = "Gray"
	}
})
$scheduleGroupBox.Controls.Add($monSchedulePlus)

$monStartTimeLabel = New-Object System.Windows.Forms.Label
$monStartTimeLabel.Location = New-Object System.Drawing.Size(10,35)
$monStartTimeLabel.Size = New-Object System.Drawing.Size(75,20)
$monStartTimeLabel.Text = "Start Time:"
$scheduleGroupBox.Controls.Add($monStartTimeLabel) 

$monStartTimeBox = New-Object System.Windows.Forms.TextBox 
$monStartTimeBox.Location = New-Object System.Drawing.Size(100,35)
$monStartTimeBox.Size = New-Object System.Drawing.Size(50,20)
$monStartTimeBox.Text = "00:00"
$monStartTimeBox.ForeColor = "Gray"
$monStartTimeBox.Add_GotFocus({                                #Clear help text on focus
	If ($monStartTimeBox.ForeColor -eq "Gray") {
		$monStartTimeBox.Text = ""
		$monStartTimeBox.ForeColor = "Black"
	}
})
$monStartTimeBox.Add_LostFocus({                               #Replace help text upon exiting if empty
	If ($monStartTimeBox.Text.Length -eq 0) { 
		$monStartTimeBox.Text = "00:00"
		$monStartTimeBox.ForeColor = "Gray"
	}
})
$scheduleGroupBox.Controls.Add($monStartTimeBox)

$monEndTimeLabel = New-Object System.Windows.Forms.Label
$monEndTimeLabel.Location = New-Object System.Drawing.Size(200,35)
$monEndTimeLabel.Size = New-Object System.Drawing.Size(75,20)
$monEndTimeLabel.Text = "End Time:"
$scheduleGroupBox.Controls.Add($monEndTimeLabel)

$monEndTimeBox = New-Object System.Windows.Forms.TextBox
$monEndTimeBox.Location = New-Object System.Drawing.Size(300,35)
$monEndTimeBox.Size = New-Object System.Drawing.Size(50,20)
$monEndTimeBox.Text = "23:59"
$monEndTimeBox.ForeColor = "Gray"
$monEndTimeBox.Add_GotFocus({
	If ($monEndTimeBox.ForeColor -eq "Gray") {                 #Clear help text on focus
		$monEndTimeBox.Text = ""
		$monEndTimeBox.ForeColor = "Black"
	}
})
$monEndTimeBox.Add_LostFocus({
	If ($monEndTimeBox.Text.Length -eq 0) {                    #Replace help text upon exiting if empty
		$monEndTimeBox.Text = "23:59"
		$monEndTimeBox.ForeColor = "Gray"
	}    
	})
$scheduleGroupBox.Controls.Add($monEndTimeBox)

$monDaysLabel = New-Object System.Windows.Forms.Label
$monDaysLabel.Location = New-Object System.Drawing.Size(10,60)
$monDaysLabel.Size = New-Object System.Drawing.Size(75,20)
$monDaysLabel.Text = "Days:"
$scheduleGroupBox.Controls.Add($monDaysLabel) 

$monSundayBox = New-Object System.Windows.Forms.CheckBox 
$monSundayBox.Location = New-Object System.Drawing.Size(100,60) 
$monSundayBox.Size = New-Object System.Drawing.Size(50,20)
$monSundayBox.Checked = $false
$monSundayBox.Text = "Sun"
$scheduleGroupBox.Controls.Add($monSundayBox)

$monMondayBox = New-Object System.Windows.Forms.CheckBox 
$monMondayBox.Location = New-Object System.Drawing.Size(150,60) 
$monMondayBox.Size = New-Object System.Drawing.Size(50,20)
$monMondayBox.Checked = $false
$monMondayBox.Text = "Mon"
$scheduleGroupBox.Controls.Add($monMondayBox)

$monTuesdayBox = New-Object System.Windows.Forms.CheckBox 
$monTuesdayBox.Location = New-Object System.Drawing.Size(200,60) 
$monTuesdayBox.Size = New-Object System.Drawing.Size(50,20)
$monTuesdayBox.Checked = $false
$monTuesdayBox.Text = "Tue"
$scheduleGroupBox.Controls.Add($monTuesdayBox)

$monWednesdayBox = New-Object System.Windows.Forms.CheckBox 
$monWednesdayBox.Location = New-Object System.Drawing.Size(250,60) 
$monWednesdayBox.Size = New-Object System.Drawing.Size(50,20)
$monWednesdayBox.Checked = $false
$monWednesdayBox.Text = "Wed"
$scheduleGroupBox.Controls.Add($monWednesdayBox)

$monThursdayBox = New-Object System.Windows.Forms.CheckBox 
$monThursdayBox.Location = New-Object System.Drawing.Size(300,60) 
$monThursdayBox.Size = New-Object System.Drawing.Size(50,20)
$monThursdayBox.Checked = $false
$monThursdayBox.Text = "Thu"
$scheduleGroupBox.Controls.Add($monThursdayBox)

$monFridayBox = New-Object System.Windows.Forms.CheckBox 
$monFridayBox.Location = New-Object System.Drawing.Size(350,60) 
$monFridayBox.Size = New-Object System.Drawing.Size(50,20)
$monFridayBox.Checked = $false
$monFridayBox.Text = "Fri"
$scheduleGroupBox.Controls.Add($monFridayBox)

$monSaturdayBox = New-Object System.Windows.Forms.CheckBox 
$monSaturdayBox.Location = New-Object System.Drawing.Size(400,60) 
$monSaturdayBox.Size = New-Object System.Drawing.Size(50,20)
$monSaturdayBox.Checked = $false
$monSaturdayBox.Text = "Sat"
$scheduleGroupBox.Controls.Add($monSaturdayBox)

$monEnvironmentLabel = New-Object System.Windows.Forms.Label
$monEnvironmentLabel.Location = New-Object System.Drawing.Size(20,595) 
$monEnvironmentLabel.Size = New-Object System.Drawing.Size(45,23) 
$monEnvironmentLabel.TextAlign = "MiddleCenter"
$monEnvironmentLabel.ForeColor = "White"
If ($environment -ieq "p") {
    $monEnvironmentLabel.Text = "Prod"
    $monEnvironmentLabel.BackColor = "#006699"
}
Else {
    $monEnvironmentLabel.Text = "QA"
    $monEnvironmentLabel.BackColor = "#CC6600"
}
$objForm.Controls.Add($monEnvironmentLabel)

$monNumberMinus = New-Object System.Windows.Forms.Button
$monNumberMinus.Location = New-Object System.Drawing.Point(140,595)
$monNumberMinus.Size = New-Object System.Drawing.Size(20,20)
$monNumberMinus.Text = "-"
$monNumberMinus.Enabled = $false
$monNumberMinus.add_Click({
    fun_monitorXML($xml)("Remove")
})
$objForm.Controls.Add($monNumberMinus)

$monLabel = New-Object System.Windows.Forms.Label
$monLabel.Location = New-Object System.Drawing.Size(190,598)
$monLabel.Size = New-Object System.Drawing.Size(55,20)
$monLabel.Text = "Monitor:"
$objForm.Controls.Add($monLabel) 

$monNumberLabel = New-Object System.Windows.Forms.Label
$monNumberLabel.Location = New-Object System.Drawing.Size(245,598)
$monNumberLabel.Size = New-Object System.Drawing.Size(20,20)
$monNumberLabel.Text = "1"
$objForm.Controls.Add($monNumberLabel)

$monNumberPlus = New-Object System.Windows.Forms.Button
$monNumberPlus.Location = New-Object System.Drawing.Point(280,595)
$monNumberPlus.Size = New-Object System.Drawing.Size(20,20)
$monNumberPlus.Text = "+"
If ($environment -ieq "p") { $monNumberPlus.Enabled = $false }
$monNumberPlus.add_Click({
    fun_monitorXML($xml)("Add")

})
$objForm.Controls.Add($monNumberPlus)

$OKButton = New-Object System.Windows.Forms.Button
$OKButton.Location = New-Object System.Drawing.Point(425,595)
$OKButton.Size = New-Object System.Drawing.Size(75,23)
$OKButton.Text = "OK"
$OKButton.add_Click({
    fun_monitorXML($xml)("OK")
})
$objform.AcceptButton = $OKButton
$objform.Controls.Add($OKButton)

$CancelButton = New-Object System.Windows.Forms.Button
$CancelButton.Location = New-Object System.Drawing.Point(505,595)
$CancelButton.Size = New-Object System.Drawing.Size(75,23)
$CancelButton.Text = "Cancel"
$CancelButton.add_Click({
    If (Test-Path C:\temp\SCOMweb_LogTime.txt) {
        $LogTime = Get-Content C:\temp\SCOMweb_LogTime.txt
        If (Test-Path "C:\temp\SCOMweb_$LogTime.xml") { Remove-Item "C:\temp\SCOMweb_$LogTime.xml" }
    }
    fun_RemoveTempFile
})
$CancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
$objform.CancelButton = $CancelButton
$objform.Controls.Add($CancelButton)

If ($environment -ieq "q") { $xml = [xml](Get-Content "C:\SCM\SCOM\SCOM 2016\Web Monitoring XML Files\QA_Master2.xml") }	
ElseIf ($environment -ieq "e" -or $environment -ieq "p") {								#If opening existing monitor, prompt for file and import fields
	$inputfile = fun_GetFileName
	Try { $xml = [xml](Get-Content $inputfile) }										#Verify XML is valid and check against schema
	Catch {
		$popUp = (New-Object -ComObject Wscript.Shell).Popup("The selected XML file is invalid.`n`nClick OK to exit.",0,"Invalid XML",16)
		Exit
	}
	fun_testXML -XmlFile $inputfile -SchemaFile '\\server08\WebConfig.xsd'

	If (($xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group").Count -gt 1) -or ($xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group/Group").Count -gt 1) -or ($xml.SelectNodes("//WebApplicationMonitoringConfiguration/Group/Group/Group").Count -gt 1)) {
        $popUp = (New-Object -ComObject Wscript.Shell).Popup("Only 1 Domain/BAP/TAP at a time allowed. Exiting.",0,"BAP Limit",16)
		Exit
	}
    fun_updateDisplay ($xml)("Import")
}

#Activate Form
$objForm.Topmost = $False
$objForm.Add_Shown({$objForm.Activate()})
$newMonitor = $objForm.ShowDialog()