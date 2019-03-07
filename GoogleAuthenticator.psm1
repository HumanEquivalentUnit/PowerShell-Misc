using namespace System

$Script:Base32Charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567'

<#
.Synopsis
  Generate an 80-bit key, BASE32 encoded, secret
  and a URL to Google Charts which will show it as a QR code.
  The QR code can be used with the Google Authenticator app

.Example
  PS C:\> New-GoogleAuthenticatorSecret

  Secret           QrCodeUri                                                                                          
  ------           ---------                                                                                          
  5WYYADYB5DK2BIOV http://chart.apis.google[..]

.Example
  PS C:\> New-GoogleAuthenticatorSecret -Online
  # *web browser opens*

.Example
  # Take a secret code from a real website,
  # but put your own text around it to show in the app

  PS C:\> New-GoogleAuthenticatorSecret -UseThisSecretCode HP44SIFI2GFDZHT6 -Name "me@example.com" -Issuer "My bank 💎" -Online | fl *


  Secret    : HP44SIFI2GFDZHT6
  KeyUri    : otpauth://totp/me%40example.com?secret=HP44SIFI2GFDZHT6&issuer=My%20bank%20%F0%9F%92%8E
  QrCodeUri : https://chart.apis.google.com/chart?cht=qr&chs=200x200&chl=otpauth%3A%2F%2Ftotp%2Fme%25[..]

  # web browser opens, and you can scan your bank code into the app, with new text around it.

#>
function New-GoogleAuthenticatorSecret
{
    [CmdletBinding()]
    Param(
        # Secret length in bytes, must be a multiple of 5 bits for neat BASE32 encoding
        [int]
        [ValidateScript({($_ * 8) % 5 -eq 0})]
        $SecretLength = 10,

        # Use an existing secret code, don't generate one, just wrap it with new text
        [string]
        $UseThisSecretCode = '',
        
        # Launches a web browser to show a QR Code
        [switch]
        $Online = $false,


        # Name is text that will appear under the entry in Google Authenticator app, e.g. a login name
        [string] $Name = 'Example Website:alice@example.com',


        # Issuer is text that will appear over the entry in Google Authenticator app
        [string]
        $Issuer = 'Example Corp 😃'
    )


    # if there's a secret provided then use it, otherwise we need to generate one
    if ($PSBoundParameters.ContainsKey('UseThisSecretCode')) {
    
        $Base32Secret = $UseThisSecretCode
    
    } else {

        # Generate random bytes for the secret
        $byteArrayForSecret = [byte[]]::new($SecretLength)
        [Security.Cryptography.RNGCryptoServiceProvider]::new().GetBytes($byteArrayForSecret, 0, $SecretLength)
    

        # BASE32 encode the bytes
        # 5 bits per character doesn't align with 8-bits per byte input,
        # and needs careful code to take some bits from separate bytes.
        # Because we're in a scripting language let's dodge that work.
        # Instead, convert the bytes to a 10100011 style string:
        $byteArrayAsBinaryString = -join $byteArrayForSecret.ForEach{
            [Convert]::ToString($_, 2).PadLeft(8, '0')
        }


        # then use regex to get groups of 5 bits 
        # -> conver those to integer 
        # -> lookup that as an index into the BASE32 character set 
        # -> result string
        $Base32Secret = [regex]::Replace($byteArrayAsBinaryString, '.{5}', {
            param($Match)
            $Script:Base32Charset[[Convert]::ToInt32($Match.Value, 2)]
        })
    }

    # Generate the URI which needs to go to the Google Authenticator App.
    # URI escape each component so the name and issuer can have punctiation characters.
    $otpUri = "otpauth://totp/{0}?secret={1}&issuer={2}" -f @(
                [Uri]::EscapeDataString($Name),
                $Base32Secret
                [Uri]::EscapeDataString($Issuer)
              )


    # Double-encode because we're going to embed this into a Google Charts URI,
    # and these need to still be encoded in the QR code after Charts webserver has decoded once.
    $encodedUri = [Uri]::EscapeDataString($otpUri)


    # Tidy output, with a link to Google Chart API to make a QR code
    $keyDetails = [PSCustomObject]@{
        Secret = $Base32Secret
        KeyUri = $otpUri
        QrCodeUri = "https://chart.apis.google.com/chart?cht=qr&chs=200x200&chl=${encodedUri}"
    }


    # Online switch references Get-Help -Online and launches a system WebBrowser.
    if ($Online) {
        Start-Process $keyDetails.QrCodeUri
    }


    $keyDetails
}

<#
.Synopsis
  Takes a Google Authenticator secret like 5WYYADYB5DK2BIOV
  and generates the PIN code for it
.Example
  PS C:\>Get-GoogleAuthenticatorPin -Secret 5WYYADYB5DK2BIOV

  372 251
#>
function Get-GoogleAuthenticatorPin
{
    [CmdletBinding()]
    Param
    (
        # BASE32 encoded Secret e.g. 5WYYADYB5DK2BIOV
        [Parameter(Mandatory=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [string]
        $Secret,

        # OTP time window in seconds
        $TimeWindow = 30
    )


    # Convert the secret from BASE32 to a byte array
    # via a BigInteger so we can use its bit-shifting support,
    # instead of having to handle byte boundaries in code.
    $bigInteger = [Numerics.BigInteger]::Zero
    foreach ($char in ($secret.ToUpper() -replace '[^A-Z2-7]').GetEnumerator()) {
        $bigInteger = ($bigInteger -shl 5) -bor ($Script:Base32Charset.IndexOf($char))
    }

    [byte[]]$secretAsBytes = $bigInteger.ToByteArray()
    

    # BigInteger sometimes adds a 0 byte to the end,
    # if the positive number could be mistaken as a two's complement negative number.
    # If it happens, we need to remove it.
    if ($secretAsBytes[-1] -eq 0) {
        $secretAsBytes = $secretAsBytes[0..($secretAsBytes.Count - 2)]
    }


    # BigInteger stores bytes in Little-Endian order, 
    # but we need them in Big-Endian order.
    [array]::Reverse($secretAsBytes)
    

    # Unix epoch time in UTC and divide by the window time,
    # so the PIN won't change for that many seconds
    $epochTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    
    # Convert the time to a big-endian byte array
    $timeBytes = [BitConverter]::GetBytes([int64][math]::Floor($epochTime / $TimeWindow))
    if ([BitConverter]::IsLittleEndian) { 
        [array]::Reverse($timeBytes) 
    }

    # Do the HMAC calculation with the default SHA1
    # Google Authenticator app does support other hash algorithms, this code doesn't
    $hmacGen = [Security.Cryptography.HMACSHA1]::new($secretAsBytes)
    $hash = $hmacGen.ComputeHash($timeBytes)


    # The hash value is SHA1 size but we want a 6 digit PIN
    # the TOTP protocol has a calculation to do that
    #
    # Google Authenticator app may support other PIN lengths, this code doesn't
    
    # take half the last byte
    $offset = $hash[$hash.Length-1] -band 0xF

    # use it as an index into the hash bytes and take 4 bytes from there, #
    # big-endian needed
    $fourBytes = $hash[$offset..($offset+3)]
    if ([BitConverter]::IsLittleEndian) {
        [array]::Reverse($fourBytes)
    }

    # Remove the most significant bit
    $num = [BitConverter]::ToInt32($fourBytes, 0) -band 0x7FFFFFFF
    
    # remainder of dividing by 1M
    # pad to 6 digits with leading zero(s)
    # and put a space for nice readability
    $PIN = ($num % 1000000).ToString().PadLeft(6, '0').Insert(3, ' ')

    [PSCustomObject]@{
        'PIN Code' = $PIN
        'Seconds Remaining' = ($TimeWindow - ($epochTime % $TimeWindow))
    }
}
