function Find-MailboxCorruption {
    <#
    .SYNOPSIS
        Display information about current mailbox repair requests.

    .DESCRIPTION
        Display information about current mailbox repair requests. Also kick off repair requests if needed

    .PARAMETER Batch
        Pass in one or a few mailboxes for evaluation

    .PARAMETER CorruptionReport
        Output all mailboxes that have corruption in them

    .PARAMETER DetectOnly
        Run in detect only mode. Will not kick off a repair request to fix

    .PARAMETER LogPath
        Logging path

    .PARAMETER MailboxRepairRequestLog
        File containing mailbox requests competed

    .PARAMETER MailboxList
        CSV format of mailboxes to be repaired or scanned

    .PARAMETER Repair
        Kick off a new mailbox migration request is repair mode

    .PARAMETER ShowAllTables
        Display all tables of each mailbox repair request

    .EXAMPLE
        Find-MailboxCorruption -CorruptionReport -ShowAllTables -Verbose

        Runs the script to dump out all information in each mailbox repair request in verbose mode

    .EXAMPLE
        Find-MailboxCorruption -Repair

        Runs the script to kick off a mailbox repair request for mailboxes with the fix options. You must run the script again with the CorruptionReport parameter to verify corruption has been fixed

    .EXAMPLE
        Find-MailboxCorruption -DetectOnly

        Runs the script to kick off a mailbox repair request for mailboxes with the detect only. This is the default

    .NOTES
        This must be ran for Exchange on-prem and from with-in the Exchange Management Shell
    #>

    [OutputType('System.String')]
    [CmdletBinding()]
    param (
        [object[]]
        $Batch,

        [switch]
        $CorruptionReport,

        [ValidateSet('AggregateCounts', 'CorruptJunkRule', 'DropAllLazyIndexes', 'FolderACL', 'FolderView', 'ImapId', 'LockedMoveTarget')]
        [string]
        $FixCorruptionType,

        [switch]
        $DetectOnly,

        [string]
        $LogPath = "c:\temp",

        [string]
        $MailboxRepairRequestLog = "MailboxRepairRequestFailures.log",

        [string]
        $MailboxList = "mailboxlist.csv",

        [switch]
        $Repair,

        [switch]
        $ShowAllTables
    )

    begin {
        $parameters = $PSBoundParameters
        Write-Output "Starting process"
        Write-Verbose "Checking for corruption types to scan / fix"
        if($parameters.ContainsKey('FixCorruptionType')) { $BulkCorruptionItemsToFix = $FixCorruptionType }
        else {
            $BulkCorruptionItemsToFix = "MessageId", "MessagePtagCn", "MissingSpecialFolders", "ProvisionedFolder", "ReplState", "RestrictionFolder", "RuleMessageClass", "ScheduledCheck", "SearchFolder", "UniqueMidIndex"
        }
    }

    process {
        if(($parameters.ContainsKey('Repair') -or ($parameters.ContainsKey('DetectOnly') -or ($parameters.ContainsKey('CorruptionReport')))))
        {
            Write-Verbose "Getting mailboxes"
            try {
                if($batch) { $mailboxes = $batch }
                Write-Verbose "Trying to impact $mailboxList"
                $script:mailboxes = Import-Csv -Path $mailboxList -ErrorAction SilentlyContinue
            }
            catch {
                Write-Verbose "$mailboxList not found. Calling Get-Mailbox to retreive mailboxes"
                $mailboxes = Get-Mailbox -ResultSize Unlimited | Select-Object Alias, DisplayName -ErrorAction Stop
            }
        }
        else {
            Write-Verbose "No parameters detected"
            return
        }

        if ($parameters.ContainsKey('Repair')) {
            Write-Verbose "Kicking off New-MailboxRepairRequests for mailboxes in repair mode"
            Write-Verbose "Setting Bulk Corruption types to: $($BulkCorruptionItemsToFix)"

            foreach ($mailbox in $mailboxes) {
                try {
                    New-MailboxRepairRequest -Mailbox $mailbox.Alias -CorruptionType $BulkCorruptionItemsToFix -ErrorAction Stop
                }
                catch {
                    $date = "[{0:MM/dd/yy} {0:HH:mm:ss}] -" -f (Get-Date)
                    Out-File -FilePath (Join-Path -Path $LogPath -ChildPath $MailboxRepairRequestLog) -InputObject "$date $_" -Append -ErrorAction Stop
                    return
                }
            }
            Write-Verbose "New-MailboxRepairRequests for mailboxes in repair mode processed!"
            return
        }

        if ($parameters.ContainsKey('DetectOnly')) {
            Write-Verbose "Kicking off New-MailboxRepairRequests for mailboxes in detect mode - Default mode"
            Write-Verbose "Setting Bulk Corruption types to: $($BulkCorruptionItemsToFix)"
            foreach ($mailbox in $mailboxes) {
                try {
                    New-MailboxRepairRequest -Mailbox $mailbox.Alias -CorruptionType $BulkCorruptionItemsToFix -ErrorAction Stop -DetectOnly
                }
                catch {
                    $date = "[{0:MM/dd/yy} {0:HH:mm:ss}] -" -f (Get-Date)
                    Out-File -FilePath (Join-Path -Path $LogPath -ChildPath $MailboxRepairRequestLog) -InputObject "$date $_" -Append -ErrorAction Stop
                    return
                }
            }
            Write-Verbose "New-MailboxRepairRequests for mailboxes processed!"
            return
        }

        if ($parameters.ContainsKey('CorruptionReport')) {
            # Find all mailboxes and add them to a batch by first letter
            $letters = @('a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')

            foreach ($letter in $letters) {
                if ($batch = $mailboxes | Where-Object Alias -like "$letter*") {
                    Write-Verbose "Batch $($letter) created!"

                    # Fix because you can't pass a switch to a job
                    if ($parameters.ContainsKey('ShowAllTables')) { $showAllTables = $true } else { $showAllTables = $false }

                    Write-Verbose "Starting background job for Batch: $($letter)"
                    $null = Start-Job -Name BatchJob -Scriptblock {
                        $batch = $using:batch
                        $showAllTables = $using:showAllTables
                        c:\temp\Get-CorruptionReport.ps1 -batch $batch -ShowAllTables:$showAllTables
                    }
                }
            }

            Write-Verbose "Waiting for all batch jobs to complete"
            while ($allBatchJobs = Get-Job | Where-Object Name -eq "BatchJob") {
                foreach ($job in $allBatchJobs) {
                    if (($job.State -eq "Completed") -or ($job.State -eq "Failed")) {
                        Write-Verbose "Removing batch job: $($job.Id)"
                        Remove-Job -id $job.id -ErrorAction SilentlyContinue
                    }
                    if ((Get-Job).count -eq 0) { "breaking"; break }
                }
            }
        }
    }

    end {
        Write-Verbose "Process completed!"
    }
}