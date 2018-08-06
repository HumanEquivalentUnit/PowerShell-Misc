# Proof of concept script to import media from an iPhone, or similar, connected by USB.
# Requires Windows 10.
# Uses Out-GridView for a GUI
# Imports to $HOME\Pictures\dated folder names\ 



# Information and C# source code from 
# https://www.codeproject.com/Articles/996318/Using-the-Windows-Photo-Import-API-Windows-Media-I



# Reference the WinRT types, which cause their assemblies to be loaded, 
# and makes them available for use.

Add-Type -AssemblyName System.Runtime.WindowsRuntime

$null = [Windows.Foundation.IAsyncOperation`1,             Windows.Foundation,   ContentType=WindowsRuntime]
$null = [Windows.Media.Import.PhotoImportManager,          Windows.Media.Import, ContentType=WindowsRuntime]
$null = [Windows.Foundation.IAsyncOperationWithProgress`2, Windows.Foundation,   ContentType=WindowsRuntime]



# Code to use WinRT Async methods in PowerShell..
# from Ben N.
# https://fleexlab.blogspot.com/2018/02/using-winrts-iasyncoperation-in.html

# This code works for an Async method call which returns an IAsyncOperation<T>
$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | 
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and 
                    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]

Function Await($WinRtTask, $ResultType)
{
    $asTask = $asTaskGeneric.MakeGenericMethod($ResultType)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}



# Async search for connected devices
$sources = Await (
                [Windows.Media.Import.PhotoImportManager]::FindAllSourcesAsync()
                ) (
                [System.Collections.Generic.IReadOnlyList[Windows.Media.Import.PhotoImportSource]]
                )



# Present the available devices in a basic GUI using Out-GridView, for user to choose one
$selectedSource = $sources | 
                    Out-GridView -OutputMode Single -Title 'Choose device to import from'


if (-not $selectedSource)
{
    throw "no devices found, or no device selected"
}

# Start an import session for the device
$importSession = $selectedSource.CreateImportSession()


# CopyPaste / edit of the previous async code, edited to work for
# methods which return IAsyncOperationWithProgress<T, T>
# No doubt these could be merged into a single function, but .. proof of concept.
$asTaskGeneric2 = ([System.WindowsRuntimeSystemExtensions].GetMethods() | 
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and 
                    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperationWithProgress`2' })[0]

Function Await2($WinRtTask, $ResultType1, $ResultType2)
{
    $asTask = $asTaskGeneric2.MakeGenericMethod($ResultType1, $ResultType2)
    $netTask = $asTask.Invoke($null, @($WinRtTask))
    $netTask.Wait(-1) | Out-Null
    $netTask.Result
}


# Find images and pictures available for import.
# Note that ::SelectNone makes none of them selected for import by default
# Other options are ::SelectAll (all of them)
# and ::SelectNew, where this API keeps track of which ones were imported before
# (1M history) and selects only unseen ones for import
$items = Await2 (
            $importSession.FindItemsAsync(
                [Windows.Media.Import.PhotoImportContentTypeFilter]::ImagesAndVideos, 
                [Windows.Media.Import.PhotoImportItemSelectionMode]::SelectNone)
                ) (
                [Windows.Media.Import.PhotoImportFindItemsResult]
                ) (
                [uint32]
                )


Write-Verbose "Found -$($items.PhotosCount)- items"


# Present a basic, text only, list of found media available to import, using Out-GridView
# Use ctrl-click to select some
$items.FoundItems | 
    Sort-Object -Property Date -Descending | 
    Out-GridView -OutputMode Multiple -Title 'Choose items to import' | 
    ForEach-Object { $_.IsSelected = $true }


Write-Verbose "-$($items.SelectedPhotosCount)- items selected ($($items.SelectedPhotosSizeInBytes/1Mb)Mb)"


if (($items.FoundItems | Where-Object {$_.IsSelected}).Count -eq 0)
{
    throw "no items found, or no items selected for import"
}

# Run the import and wait for it to finish
$importResult = Await2 (
                    $items.ImportItemsAsync()
                    ) (
                    [Windows.Media.Import.PhotoImportImportItemsResult]
                    ) (
                    [Windows.Media.Import.PhotoImportProgress]
                    )


# Show the result (result success/fail, 
#    number of photos/videos and size in bytes are the main interesting bits)
$importResult