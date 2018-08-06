using namespace System.Drawing
using namespace System.Windows.Forms

Add-Type –AssemblyName System.Drawing
Add-Type –AssemblyName System.Windows.Forms

<#
.Synopsis
    Convert text to image
.DESCRIPTION
    Takes text input from the pipeline or as a parameter, and makes an image of it.

.EXAMPLE
    Import-Module .\StringToPng.psm1
    "sample text" | Export-StringToPng -Path output.png

.EXAMPLE
    get-childitem c:\ | Export-StringToPng -path output.png

.EXAMPLE
    get-process | format-table -AutoSize | Out-String | Export-StringToPng -path output.png

#>

function Export-StringToPng
{
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true,
                    Position=0)]
        [string[]]$InputObject,

        # Path where output image should be saved
        [string]$Path,

        # Clipboard support,
        [switch]$ToClipboard
    )

    begin
    {
        # can render multiple lines, so $lines exists to gather
        # all input from the pipeline into one collection
        [Collections.Generic.List[String]]$lines = @()
    }
    Process
    {
        # each incoming string from the pipeline, works even
        # if it's a multiline-string. If it's an array of string
        # this implicitly joins them using $OFS
        $null = $lines.Add($InputObject)
    }

    End
    {
        # join the array of lines into a string, so the 
        # drawing routines can render the multiline string directly
        # without us looping over them or calculating line offsets, etc.
        [string]$lines = $lines -join "`n"


        # placeholder 1x1 pixel bitmap, will be used to measure the line
        # size, before re-creating it big enough for all the text
        [Bitmap]$bmpImage = [Bitmap]::new(1, 1)


        # Create the Font, using any available MonoSpace font
        # hardcoded size and style, because it's easy
        [Font]$font = [Font]::new([FontFamily]::GenericMonospace, 12, [FontStyle]::Regular, [GraphicsUnit]::Pixel)


        # Create a graphics object and measure the text's width and height,
        # in the chosen font, with the chosen style.
        [Graphics]$Graphics = [Graphics]::FromImage($BmpImage)
        [int]$width  = $Graphics.MeasureString($lines, $Font).Width
        [int]$height = $Graphics.MeasureString($lines, $Font).Height


        # Recreate the bmpImage big enough for the text.
        # and recreate the Graphics context from the new bitmap
        $BmpImage = [Bitmap]::new($width, $height)
        $Graphics = [Graphics]::FromImage($BmpImage)


        # Set Background color, and font drawing styles
        # hard coded because early version, it's easy
        $Graphics.Clear([Color]::Black)
        $Graphics.SmoothingMode = [Drawing2D.SmoothingMode]::Default
        $Graphics.TextRenderingHint = [Text.TextRenderingHint]::SystemDefault
        $brushColour = [SolidBrush]::new([Color]::FromArgb(200, 200, 200))


        # Render the text onto the image
        $Graphics.DrawString($lines, $Font, $brushColour, 0, 0)

        $Graphics.Flush()


        if ($Path)
        {
            # Export image to file
            [System.IO.Directory]::SetCurrentDirectory(((Get-Location -PSProvider FileSystem).ProviderPath))
            $Path = [System.IO.Path]::GetFullPath($Path)
            $bmpImage.Save($Path, [Imaging.ImageFormat]::Png)
        }

        if ($ToClipboard)
        {
            [Windows.Forms.Clipboard]::SetImage($bmpImage)
        }

        if (-not $ToClipboard -and -not $Path)
        {
            Write-Warning -Message "No output chosen. Use parameter -LiteralPath 'out.png' , or -ToClipboard , or both"
        }
    }

}
