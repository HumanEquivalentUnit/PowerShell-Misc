# Two functions to encode text into lossless images, and read it back out
# dot source or import this, then run them


using namespace System.Drawing

<#
.DESCRIPTION
    Edits an image, to hide text inside it by slightly changing colours.

    In this version, it edits the Red channel of each pixel, modifying it by 1 part in 256,
    requiring 8 image pixels per byte of input text. Denser formats are possible, but make
    more significantly visible changes in the image.
    
    Technique is called steganography, and it must be done with a lossless image format.
    (e.g. bmp or maybe png). 
    
    Lossy formats like jpg and gif change image content themselves, and break the hidden text.

    NB. this technique is only for fun, it's well known, patterns stand out against image content,
            and it is not any kind of significant security.

    NB. C# or other language is better suited for this; PowerShell is not optimised
        for bit bashing, and GetPixel and SetPixel are slow methods for using heavily.

.EXAMPLE
    Export-StegBmp -Text 'abcd' -SourceImage C:\test\source.bmp -DestinationImage c:\test\hidden.bmp

.EXAMPLE
    Get-ChildItem c:\ | Format-Table | Out-String | Export-StegBmp -SourceImage C:\test\source.bmp -DestinationPath c:\test\hidden.bmp
            
#>
function Export-TextIntoImageHidden
{
    [CmdletBinding()]
    Param
    (
        # Text to write into the image
        [Alias('InputObject')]
        [Parameter(Mandatory=$true,
                    ValueFromPipeline=$true,
                    Position=0)]
        [string[]]$Text,

        # Image to load, and merge text into
        [string]$SourceImage,

        # Filename to write output image to
        [string]$DestinationPath
    )

    begin
    {
        # all input from the pipeline will go into one collection
        [Collections.Generic.List[String]]$lines = @()
    }

    Process
    {
        # store each incoming string from the pipeline; this works even
        # if it's a multiline-string. If it's an array of string
        # this implicitly joins them using $OFS
        $null = $lines.Add($Text)
    }

    End
    {
        # Get the source image content
        [Bitmap]$bmp = [Bitmap]::FromFile($SourceImage)

        
        # Get the source text bytes to encode. We will use the pattern 
        # content length, 0, content
        # so we can work out how much to read out of the image when importing.

        [byte[]]$sourceBytes = [Text.Encoding]::UTF8.GetBytes(($lines -join "`n"))
        
        [byte[]]$bytesToEncode = @([Text.Encoding]::UTF8.GetBytes([string]$sourceBytes.Count)) + @(0) + $sourceBytes


        # Step through the text bytes and image pixels. Each byte breaks into 8 bits, each bit
        # goes into one pixel
        $x = 0
        $y = 0
        $bytesToEncode | ForEach-Object {

            # split byte into 8 bits, shift them right far enough to make them 0 or 1
            ($_ -band 128) -shr 7
            ($_ -band 64 ) -shr 6
            ($_ -band 32 ) -shr 5
            ($_ -band 16 ) -shr 4
            ($_ -band 8  ) -shr 3
            ($_ -band 4  ) -shr 2
            ($_ -band 2  ) -shr 1
            ($_ -band 1  )

        } | foreach-object {


            # map each bit into the Red channel value of a pixel, modifying it only by 1 in 256
            $sourcePixel = $bmp.GetPixel($x, $y)
            
            $replacementPixel = [System.Drawing.Color]::FromArgb(
                    $sourcePixel.A,
                    (($sourcePixel.R -band 254) -bor $_), # merge bit into lowest bit of R
                    $sourcePixel.G,
                    $sourcePixel.B
                )
                
        
            # update the image with the modified pixel                            
            $bmp.SetPixel($x, $y, $replacementPixel)
        
            

            # Move to next pixel, (right right right and wrap at end of row)
            $x++
            if ($x -ge $bmp.Width)
            {
                $y++
                $x = 0 
            }

        }


        # Convert names like .\file1.bmp to a full path, and export image
        [System.IO.Directory]::SetCurrentDirectory(((Get-Location -PSProvider FileSystem).ProviderPath))
        $DestinationPath = [System.IO.Path]::GetFullPath($DestinationPath)
        $bmp.Save($DestinationPath, [Imaging.ImageFormat]::Bmp)

    }

}




<#
.synopsis
    Extract text hidden in image

.DESCRIPTION
    Extract text hidden in image


.EXAMPLE
    Import-TextHiddenInImage -SourceImage .\hidden.bmp
            
#>
function Import-TextHiddenInImage
{
    [CmdletBinding()]

    Param
    (
        # Image to load, and extract text from
        [string]$SourceImage
    )

    End
    {
        
        # Get the source image content, including handling relative paths like .\image.bmp
        [System.IO.Directory]::SetCurrentDirectory(((Get-Location -PSProvider FileSystem).ProviderPath))
        $SourceImage = [System.IO.Path]::GetFullPath($SourceImage)
        [Bitmap]$bmp = [Bitmap]::FromFile($SourceImage)

        $numBytesToRead = -1  # placeholder; will adjust after reading the first few, which include
                                # a value saying how many more to read and a 0 delimiter.


        
        $bitCounter  = 0      # this tracks the incoming bits to where they go in the output byte
        $charCounter = 0      # this tracks the num of chars, so it can stop and not read the entire bmp
        
        [Byte]$byte  = 0      # holds the byte value while we get bits of it at a time



        # read through the image row by row, pixel by pixel, 
        # extracting the lowest bit from the Red channel value and
        # building up 1 byte every 8 pixels

        [system.collections.Generic.list[byte]]$bytes = @()

        for ($y = 0; ($numBytesToRead -ne 0) -and ($y -lt $bmp.Height); $y++)
        {
            for ($x = 0; ($numBytesToRead -ne 0) -and ($x -lt $bmp.Width); $x++)
            {
                $pixel = $bmp.GetPixel($x, $y)

                $value = ($pixel.R -band 1) -shl (7 - $bitCounter)
                $byte = $byte -bor $value
                    
                $bitCounter++


                # after 8 pixels, process one byte
                if ($bitCounter -eq 8)
                {

                    # decrement bytes remaining, either -1, -2, -3 placeholders
                    # or .. 4, 3, 2, 1, 0 how many to go until finishing
                    $numBytesToRead--


                    # store the incoming byte in the collection
                    $null = $bytes.Add($byte)
                    

                    # check if we're reading at the start, looking for the remaining length indicator.
                    # if we hit the 0 value delimiter that marks it
                    if ((0 -eq $byte) -and ($numBytesToRead -lt 0))
                    {

                        # now we know how many bytes to read from here, to get all the content.
                         
                        $numBytesToRead = [int][system.text.encoding]::UTF8.GetString($bytes)
                        
                        # reset the array, so now it will just have output text
                        [system.collections.Generic.list[byte]]$bytes = @()
                    }
                    

                    # new byte, new bitcounter
                    [byte]$byte = 0
                    $bitCounter = 0
                    
                }
            }
        }
            
        # output the text
        [System.Text.encoding]::UTF8.GetString($bytes)
    }

}

 
