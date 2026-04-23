# Prompt for domain credentials
$cred = Get-Credential -Message "Enter domain credentials"

# Set your domain name
$domain = "replace_with_domain"

# Set the desired OU
$ouPath = "OU=laptops,OU=Computers,DC=replace_with_domain,DC=ac,DC=uk"

try {
    Write-Host "Attempting to join the domain..." -ForegroundColor Cyan

    # Attempt domain join - this line suppresses the warning message, creating less confusion
    Add-Computer -DomainName $domain -OUPath $ouPath -Credential $cred -ErrorAction Stop -WarningAction SilentlyContinue | Out-Null

    # If you prefer to keep the warning message by PowerShell, replace with the below command
    #Add-Computer -DomainName $domain -OUPath $ouPath -Credential $cred -ErrorAction Stop

    Write-Host "`nSuccessfully joined the domain." -ForegroundColor Green
    Write-Host "The system will restart in 10 seconds..."
    Write-Host "Press ENTER to restart immediately."

    $stopWatch = [Diagnostics.Stopwatch]::StartNew()

    while ($stopWatch.Elapsed.TotalSeconds -lt 10) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq "Enter") {
                break
            }
        }
        Start-Sleep -Milliseconds 200
    }

    Restart-Computer -Force
}
catch {
    Write-Host "`nFailed to join the domain. Please check your credentials, network connection or Laptop name" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    Read-Host "Press ENTER to exit"
}
