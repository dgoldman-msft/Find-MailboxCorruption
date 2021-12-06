[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param(
    [PSCustomObject]
    $batch,

    [switch]
    $ShowAllTables
)

# Save bound parameters
$parameters = $PSBoundParameters
[System.Collections.ArrayList]$resultTable = @()
$LogPath = "c:\temp"
$BatchReport = "BatchReport.log"
$CleanMailboxesReport = "CleanMailboxesReport.log"
$MailboxFailureLog = "MailboxRepairRequestFailures.log"
$ConnectionFailureLog = "ConnectionFailures.log"

try {
    # Implicit remoting is used because we are running in a background process
    $credentials = New-Object System.Management.Automation.PSCredential ('Domain\Account', (ConvertTo-SecureString 'Password' -AsPlainText -Force))
    $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri http://Exchsrv1/powershell -Credential $credentials -Authentication Kerberos -ErrorAction Stop
    Import-PSSession -Session $session -AllowClobber
}
catch {
    Out-File -FilePath (Join-Path -Path $LogPath -ChildPath $ConnectionFailureLog) -InputObject $_ -Encoding utf8 -Append
    return
}

foreach ($mailbox in $batch) {
    $fixes = 0
    $mailboxIsClean = $false
    $mailboxIsDirty = $false
    $LogToWrite = $($mailbox.Alias) + ".csv"
    $FileName = (Join-Path -Path $LogPath -ChildPath $LogToWrite)

    try {
        # Need to check if this is a scaler array
        if ($repairResult = Get-MailboxRepairRequest -Mailbox $mailbox.alias -ErrorAction Stop) {
            # for each result we need to loop through each one of the tables in the mailbox
            foreach ($result in $repairResult) {
                $table = [PSCustomObject]@{
                    Mailbox          = $mailbox.DisplayName
                    CorruptionsFixed = $result.CorruptionsFixed
                    CreationTime     = $result.CreationTime
                    ErrorCode        = $result.ErrorCode
                    FinishTime       = $result.FinishTime
                    DetectOnly       = $result.DetectOnly
                    Source           = $result.Source
                    Tasks            = $result.Tasks[0]
                }
                $null = $resultTable.add($table)
            }

            # Process the results and look to see if the mailbox is clean or dirty
            foreach ($tableResult in $resultTable) {
                if ($tableResult.CorruptionsFixed -gt 0) {
                    $fixes ++
                    $mailboxIsDirty = $true
                }
                else { $mailboxIsClean = $true }
            }

            if ($parameters.ContainsKey('ShowAllTables')) {
                [PSCustomObject]$resultTable | Export-Csv -Path $FileName -Append -NoTypeInformation -ErrorAction Stop
            }

            # Just print corrupted tables
            if (($fixes -gt 0) -and (-NOT ($parameters.ContainsKey('ShowAllTables'))) -and $mailboxIsDirty) {
                [PSCustomObject]$resultTable | Export-Csv -Path $FileName -Append -NoTypeInformation -ErrorAction Stop
            }

            # mailbox is clean
            if (($mailboxIsClean) -and (-NOT($mailboxIsDirty))) {
                $date = "[{0:MM/dd/yy} {0:HH:mm:ss}] -" -f (Get-Date)
                Out-File -FilePath (Join-Path -Path $LogPath -ChildPath $CleanMailboxesReport) -InputObject "$date Mailbox: $($mailbox.Alias) - No Corruption found!" -Append -ErrorAction Stop
            }
        }
        else {
            $date = "[{0:MM/dd/yy} {0:HH:mm:ss}] -" -f (Get-Date)
            Out-File -FilePath (Join-Path -Path $LogPath -ChildPath $BatchReport) -InputObject "$date No batch found for mailbox: $($mailbox.Alias)" -Append -ErrorAction Stop
        }
    }
    catch {
        Out-File -FilePath (Join-Path -Path $LogPath -ChildPath $MailboxFailureLog) -InputObject $_ -Encoding utf8 -Append
        return
    }
}

Get-PSSession | Remove-PSSession