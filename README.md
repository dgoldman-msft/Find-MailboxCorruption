# Find-MailboxCorruption

Find corruption in mailbox repair requests.

> EXAMPLE 1: Find-MailboxCorruption -CorruptionReport -ShowAllTables -Verbose

    Runs the script to dump out all information in each mailbox repair request in verbose mode

> EXAMPLE 2: Find-MailboxCorruption -Repair

    Runs the script to kick off a mailbox repair request for mailboxes with the fix options. You must run the script again with the CorruptionReport parameter to verify corruption has been fixed

> EXAMPLE 3: Find-MailboxCorruption -DetectOnly

    Runs the script to kick off a mailbox repair request for mailboxes with the detect only. This is the default

NOTE: Both scripts must reside in the same directory and be executed under Exchange Management Shell. This will only work for Exchange On-Prem
