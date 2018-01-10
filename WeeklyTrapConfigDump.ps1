# WeeklyTrapConfigDump.ps1
# Usage: Dump OpenView incident configs to D:\temp, extract pertinent information into a .CSV
# Created by: Mike McGrail

# Create temp files and final CSV file
$tmpTagFile = "D:\temp\weeklyTrapConfigDump.tag"
$tmpTxtFile = "D:\temp\weeklyTrapConfigText.txt"
$CsvFile = "D:\temp\weeklyTrapConfig.csv"

# Delete files if they already exist
If ((Test-Path $tmpTagFile) -eq $true) { Remove-Item $tmpTagFile }
If ((Test-Path $tmpTxtFile) -eq $true) { Remove-Item $tmpTxtFile }
If ((Test-Path $CsvFile) -eq $true) { Remove-Item $CsvFile }

# nnmincidentcfgdump.ovpl. Use -oid .* to eliminate traps that do not contain an OID.
Invoke-Command -ScriptBlock { & cmd /c "nnmincidentcfgdump.ovpl -dump $tmpTagFile -type SnmpTrapConfig" }

# Add headers to CSV
$outPutter = "Name,OID,Enabled,Actionable,Command,Last Log,"

# Add proper line breaks to .tag (\r\n is needed to parse properly, then remove extra line breaks and trim whitespace from beginning of each line
(Get-Content $tmpTagFile | Out-String) -replace "`n", "`r`n" | Out-File $tmpTxtFile
$trapList = Get-Content $tmpTxtFile | ? { $_ -ne "" } | % { $_.TrimStart() }

# Set a nameCounter to only capture first Name line (and ignore others such as Correlation Names)
$nameCounter = 0
ForEach ($i in $trapList) {
    If (($i -cmatch '\*Name ') -and ($nameCounter -eq 0)) {
        $outPutter += "`n" + (($i -Split ('Name '))[1]) + ","
        #Set an enableCounter to ignore unwanted lines (such as Dedup Enable)
        $enableCounter = 0
        #Set a commandCounter to ignore unwanted lines (such as CommandType)
        $commandCounter = 0
        $nameCounter++
    }
    ElseIf ($i -cmatch '\*Oid ') {
        $outPutter += $i.split(' ')[1] + ","
    }
    ElseIf (($i -cmatch '\-Enable ') -and ($enableCounter -eq 0)) {
        # First Enable line of each trap is TRUE/FALSE of SNMP Trap enabled
        $outPutter += $i.split(' ')[1] + ","
        $enableCounter++
    }
    ElseIf (($i -cmatch '\-Enable ') -and ($enableCounter -eq 1)) {
        # Second Enable line of each trap is TRUE/FALSE of action enabled
        $outPutter += $i.split(' ')[1] + ","
        $enableCounter++
    }
    ElseIf (($i -cmatch '\-Command.*pl ') -and ($commandCounter -eq 0)) {
        $command = ($i -Split ('-Command '))[1] -replace ",","(COMMA)"
        $outPutter += $command + ","
        # Determine if log file exists and get LastWriteTime, "none" if file does not exist
        $logName = ($command -Split (" "))[0] -replace ".pl",".log"
        If ((Test-Path $env:NnmDataDir\$logName) -eq $false) { $outPutter += "none," }
        Else { $outPutter += (((Get-Item -Path $env:NnmDataDir\$logName).LastWriteTime).ToString() -replace ",","(COMMA)") + "," }
        $commandCounter++
    }
    ElseIf (($i -cmatch '\-Command.*pl ') -and ($commandCounter -gt 0 )) {
        # Several traps call multiple .pl scripts, add blank cells to keep CSV columns intact
        $outPutter += " , , , "
        $commandCounter++
    }
    # Reset Name counter at *ConfigurationType (which is the first line of each trap config)
    ElseIf ($i -cmatch '\*ConfigurationType=SnmpTrapConfig') { $nameCounter = 0 }
}
# Output to CSV
$outPutter | Set-Content $CsvFile