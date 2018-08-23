<#
.Synopsis
    Decrypts data from SQL Server's ENCRYPTBYPASSPHRASE function.
.DESCRIPTION
    Takes an ecnrypted input from SQL Server's ENCRYPTBYPASSPHRASE function, as hex encoded string,
    and the passphrase which was used to encrypt it.
    Works out whether it was SQL 2017 or previous, and then uses that to decrypt the data.

    Code and information taken from C# example here: https://stackoverflow.com/a/51794958
.EXAMPLE

    In SQL Server:

        SELECT CONVERT(VARCHAR(max), EncryptByPassPhrase('passphrase', 'Hello World!'), 2)
               
    In PowerShell:

        .\ConvertFrom-SqlEncryptByPassphrase.ps1 -CipherText '0x0200000031D747C49DA6063CF28DF7EEC10A61517300AC7687E9E8DF65BD7E3E46565D974EF23614B935B31200B9FE0D2BF8A65F' -Passphrase 'passphrase'
#>
param([string] $CipherText, [string] $Passphrase)

# Encode password as UTF16-LE bytes, and unencode the Base64 input.
[byte[]]$passphraseBytes = [System.Text.Encoding]::Unicode.GetBytes($Passphrase)
# [byte[]]$CipherTextBytes = [System.Convert]::FromBase64String($CipherText) # from when I was working with Base64 input.

$CipherTextBytes = foreach ($pair in ($CipherText -replace '^0x' -split '(..)' -ne ''))
{
    [System.Convert]::ToByte($pair, 16)
}

# Use the first byte of the encrypted data to decide on the SQL Server version,
# and therefore the encryption method used
# 1 for older SQL Server, SHA1 hashing + 3DES 128 encryption
# 2 for SQL Server 2017, SHA256 hashing + AES 256 encryption
$EncryptByPassphraseVersion = $CipherTextBytes[0]
    
if ($EncryptByPassphraseVersion -eq 1)
{
    $hashAlgo      = [System.Security.Cryptography.SHA1]::Create()
    $cryptoAlgo    = [System.Security.Cryptography.TripleDES]::Create()
    $cryptoAlgo.IV = $CipherTextBytes[4..11]
    $encrypted     = $CipherTextBytes[12..($CipherTextBytes.Length-1)]
    $keySize       = 16
}
elseif ($EncryptByPassphraseVersion -eq 2)
{
    $hashAlgo      = [System.Security.Cryptography.SHA256]::Create()
    $cryptoAlgo    = [System.Security.Cryptography.Aes]::Create()
    $cryptoAlgo.IV = $CipherTextBytes[4..19]
    $encrypted     = $CipherTextBytes[20..($CipherTextBytes.Length-1)]
    $keySize       = 32
}
else
{
    Write-Error -Message 'Unsupported encryption / or SQL version / or cannot find SQL version / etc.'
}


# Common padding and encryption mode 
$cryptoAlgo.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7
$cryptoAlgo.Mode    = [System.Security.Cryptography.CipherMode]::CBC


# Hash variable length passprase to get fixed size data, then use (part of) that as the decryption key.
# TransformFinalBlock returns a copy of the input data, which we don't need.
# (use of 'TransformFinalBlock' instead of 'TransformBlock', because that needs buffers to copy from/to)
[void]$hashAlgo.TransformFinalBlock($passphraseBytes, 0, $passphraseBytes.Length)
$cryptoAlgo.Key = $hashAlgo.Hash[0..($keySize-1)]


# Decrypt the data
$decryptedBytes = $cryptoAlgo.CreateDecryptor().TransformFinalBlock($encrypted, 0, $encrypted.Length)
$decryptLength = [System.BitConverter]::ToInt16($decryptedBytes, 6)


# Validation check, I guess
[UInt32] $magic = [BitConverter]::ToUInt32($decryptedBytes, 0)
if ($magic -ne [uint32]'0xbaadf00d')
{
    Write-Error -Message 'Magic number check failed; decrypt failed'
}


# Skip 8 bytes because reasons (??)
# make a guess whether it's UTF-8 or UCS2-LE encoded text, and decode it.
[byte[]] $decryptedData = $decryptedBytes[8..($decryptedBytes.Length - 1)]

if ([array]::IndexOf($decryptedData, [byte]0) -ne -1)
{ 
    [System.Text.Encoding]::Unicode.GetString($decryptedData)
} 
else
{
    [System.Text.Encoding]::UTF8.GetString($decryptedData)
}
