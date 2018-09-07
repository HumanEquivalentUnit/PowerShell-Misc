<#
.Synopsis
   Get Reddit posts for a user, as JSON files
.DESCRIPTION
   Uses the PushShift.io API to download all Reddit comments by a user, per day.
   Starting at today, and walking backwards one day at a time, until the API returns no data.
   Output is files, one per day, containing Reddit JSON content.
.EXAMPLE
   PS C:\test\> ipmo Get-RedditPostsByUser.ps1
   
   PS C:\test\> Get-RedditPostsByUser 'some-person' -Path 'c:\users\me\downloads\redditdump\'
   
   PS C:\test\> Get-Content -Raw *.json | ConvertFrom-Json | Select-Object -ExpandProperty Data
.INPUTS
#>
[CmdletBinding()]
Param
(
    # Reddit Username
    [Parameter(Mandatory=$true, 
                ValueFromPipeline=$true,
                Position=0,
                HelpMessage='Reddit username, without the /r/ part')]
    [ValidateNotNullOrEmpty()]
    [string[]]
    $Username,


    # Date to work backwards from
    [Parameter(HelpMessage='Date to work backwards from')]
    [ValidateNotNull()]
    [DateTime]
    $MostRecentDate = [datetime]::UtcNow.AddDays(1),


    # Path to save the JSON files to
    [Parameter(HelpMessage='Path to save the JSON files to')]
    [ValidateScript({
        Test-Path -Path $_
    })]
    [string]
    $Path = (Get-Location).Path,


    # Rate limit requests to the PushShift API, for politeness
    [Parameter(HelpMessage='Rate limit requests to the PushShift API, for politeness')]
    [ValidatePattern("[a-z]*")]
    [uint32]
    $SecondsBetweenRequests = 3,


    # If a web request fails, how many times should it be retries before quitting?
    [Parameter(HelpMessage='If a web request fails, how many times should it be retries before quitting?')]
    [uint32]
    $MaxRetries = 3
)

Begin
{
    $UsersToProcess = [System.Collections.Generic.List[string]]::new()
    $retryCount = 0

    # no point checking before this date
    $RedditBeginDate = Get-Date -Year 2005 -Month 6 -Day 23

}
Process
{
    foreach ($user in $Username)
    {
        $UsersToProcess.Add($user)
    }
}
End
{
    foreach ($user in $UsersToProcess)
    {
        Do {

            if ($retryCount -gt $MaxRetries)
            {
                throw "Too many web request failures. Stopping at date $($MostRecentDate.ToString('yyyy-MM-dd'))"   
            }

            # Build API query dates. 
            $LateDate = Get-Date -Year $MostRecentDate.Year -Month $MostRecentDate.Month -Day $MostRecentDate.Day
            $MostRecentDate = $MostRecentDate.AddDays(-1)
            $EarlyDate = Get-Date -Year $MostRecentDate.Year -Month $MostRecentDate.Month -Day $MostRecentDate.Day


            # Convert dates to Unix Timestamps
            $before = [Math]::Truncate((Get-Date -Date $LateDate -UFormat %s))
            $after  = [Math]::Truncate((Get-Date -Date $EarlyDate -UFormat %s))
            $url = "https://api.pushshift.io/reddit/search/comment/?author=$user&sort=desc&sort_type=created_utc&after=$after&before=$before&size=1000"

            $outputFilename = Join-Path -Path $Path -ChildPath ($MostRecentDate.ToString('yyyy-MM-dd')+'.json')
            if ((Test-Path -Path $outputFilename))
            {
                Write-Warning -Message "File already exists for this date, skipping API request. ($outputFilename)"
            }
            else
            {
                # Query the URL and return the Reddit posts
                # Once the date goes back far enough, the API will return no data, that looks like a JSON response { "data": [] }
                # I want the raw JSON to a file, so 
                try
                {
                    $webResponse = Invoke-WebRequest -Uri $url -ErrorAction Stop
                } catch
                {
                    Write-Warning -Message "Web request failed, retrying (count: $retryCount). `n Exception: $($Error[-1])"
                    $retryCount++
                    $MostRecentDate = $MostRecentDate.AddDays(1)
                }

            
                $webResponse.Content | Set-Content -Path $outputFilename -Verbose


                # Polite delay, to avoid hammering the free API at PushShift.io with a lot of web requests
                Start-Sleep -Seconds $SecondsBetweenRequests

            }
        # Can we have a better end condition than this?
        # We can't check the API content to see when it is empty, as the user might have not posted on that day.
        # We can't check Reddit for the user account to see when it was created, as it may have been deleted and no longer exist.
        } while ($MostRecentDate -gt $RedditBeginDate)

    }
}
