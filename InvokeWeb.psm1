#Requires -Version 2
###############################################################################
## Copyright (c) 2013 by Joel Bennett, all rights reserved.
## Free for use under MS-PL, MS-RL, GPL 2, or BSD license. Your choice. 
###############################################################################
## InvokeWeb.psm1 defines a subset of the Invoke-WebRequest functionality
## On PowerShell 3 and up we'll just use the built-in Invoke-WebRequest
if(!(Get-Command Invoke-WebReques[t])) {

# FULL # BEGIN FULL: Don't include this in the installer script
$PoshCodeModuleRoot = Get-Variable PSScriptRoot -ErrorAction SilentlyContinue | ForEach-Object { $_.Value }
if(!$PoshCodeModuleRoot) {
  $PoshCodeModuleRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

. $PoshCodeModuleRoot\Constants.ps1
# FULL # END FULL

Add-Type -AssemblyName "System.Web"

function Format-Dictionary {
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()]
        [Collections.IDictionary]$Content,

        [String]$Prefix = ""
    )
    end {
        if(!$Content -or $Content.Count -eq 0) {
            Write-Error "Empty Dictionary not allowed"
            return
        }
    
        $stringBuilder = new-object Text.StringBuilder $Prefix
        foreach($key in $Content.Keys)
        {
            $null = if ($stringBuilder.Length) { $stringBuilder.Append("&") }

            $eKey = [Web.HttpUtility]::UrlEncode($key)
            $eValue = if(!$Content.$key) { "" } else { [Web.HttpUtility]::UrlEncode($Content.$key) }
            $null = $stringBuilder.AppendFormat("{0}={1}", $eKey, $eValue)
        }
        $stringBuilder.ToString()
    }
}

function Set-RequestContent {
    param(
        [Parameter(Mandatory=$true)][ValidateNotNull()]
        [Net.WebRequest]$request,

        [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()]
        $content,

        $Encoding = "ISO-8859-1"
    )
    end {
        [byte[]]$bytes = if($content -is [byte[]]) { $content } else {
            $Encoder = [Text.Encoding]::GetEncoding($Encoding)
            $bytes = $Encoder.GetBytes($content)
        }

        if ($request.ContentLength -ne 0) {
          $request.ContentLength = $bytes.Length
        }
        $stream = $request.GetRequestStream()
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush()
        return $request.ContentLength;
    }
}

function Invoke-WebRequest {
    <#
          .Synopsis
            Downloads a file or page from the web, or sends web API posts/requests
          .Description
            Creates an HttpWebRequest to download a web file or post data. This is a restricted 
          .Example
            Invoke-Web http://PoshCode.org/PoshCode.psm1
          
            Downloads the latest version of the PoshCode module to the current directory
          .Example
            Invoke-Web http://PoshCode.org/PoshCode.psm1 ~\Documents\WindowsPowerShell\Modules\PoshCode\
          
            Downloads the latest version of the PoshCode module to the default PoshCode module directory...
          .Example
            $RssItems = @(([xml](Invoke-WebRequest http://poshcode.org/api/)).rss.channel.GetElementsByTagName("item"))
          
            Returns the most recent items from the PoshCode.org RSS feed
    #>
    [CmdletBinding(DefaultParameterSetName="NoSession")]
    param(
          #  The URL of the file/page to download
          [Parameter(Mandatory=$true,Position=0)]
          [System.Uri][Alias("Url")]$Uri, # = (Read-Host "The URL to download")

          [Object]$Body,

          [Hashtable]$Headers,

          [int]$TimeoutSec,

          # Specifies the method used for the web request. Valid values are Default, Delete, Get, Head, Options, Post, Put, and Trace. Default value is Get.
          [ValidateSet("Default", "Get", "Head", "Post", "Put", "Delete", "Trace", "Options", "Merge", "Patch")]
          [String]$Method = "Get",

          #  Sends the results to the specified output file. Enter a path and file name. If you omit the path, the default is the current location.
          #  By default, Invoke-WebRequest returns the results to the pipeline. To send the results to a file and to the pipeline, use the Passthru parameter.
          [Parameter()]
          [Alias("OutPath")]
          [string]$OutFile,

          #  Text to include at the front of the UserAgent string
          [string]$UserAgent = "Mozilla/5.0 (Windows NT; Windows NT $([Environment]::OSVersion.Version.ToString(2)); $PSUICulture) WindowsPowerShell/$($PSVersionTable.PSVersion.ToString(2)); PoshCode/4.0; http://PoshCode.org",

          #  Specifies the client certificate that is used for a secure web request. Enter a variable that contains a certificate or a command or expression that gets the certificate.
          #  To find a certificate, use Get-PfxCertificate or use the Get-ChildItem cmdlet in the Certificate (Cert:) drive. If the certificate is not valid or does not have sufficient authority, the command fails.
          [System.Security.Cryptography.X509Certificates.X509Certificate[]]
          $Certificate,

          [String]$ContentType,

          #  Specifies a user account that has permission to send the request. The default is the current user.
          #  Type a user name, such as "User01" or "Domain01\User01", or enter a PSCredential object, such as one generated by the Get-Credential cmdlet.
          [System.Management.Automation.PSCredential]
          [System.Management.Automation.Credential()]
          [Alias("")]$Credential = [System.Management.Automation.PSCredential]::Empty,

          # Specifies that Authorization: Basic should always be sent. Requires $Credential to be set, and should only be used with https
          [ValidateScript({if(!($Credential -or $WebSession)){ throw "ForceBasicAuth requires the Credential parameter be set"} else { $true }})]
          [switch]$ForceBasicAuth,

          # Uses a proxy server for the request, rather than connecting directly to the Internet resource. Enter the URI of a network proxy server.
          # Note: if you have a default proxy configured in your internet settings, there is no need to set it here.
          [Uri]$Proxy,

          #  Pass the default credentials to the Proxy
          [switch]$ProxyUseDefaultCredentials,

          #  Pass the default credentials
          [switch]$UseDefaultCredentials,

          #  Pass specific credentials to the Proxy
          [System.Management.Automation.PSCredential]
          [System.Management.Automation.Credential()]
          $ProxyCredential= [System.Management.Automation.PSCredential]::Empty    
    )
    process {
        $EAP,$ErrorActionPreference = $ErrorActionPreference, "Stop"
        $uriBuilder = New-Object UriBuilder $uri
        Write-Verbose "Web Request: $Uri"
        if($Body -and ($Method -eq "Get")) {
            Write-Verbose "UriBuilder: $uriBuilder"
            $uriBuilder.Query = if($uriBuilder.Query -and $uriBuilder.Query.Length -ge 1) {
                Format-Dictionary $Body -Prefix $uriBuilder.Query.Substring(1)
            } else { 
                Format-Dictionary $Body
            }
            $uri = $uriBuilder.Uri
            $Body = $null
        }
        Write-Verbose "Web Request: $Uri"
        $request = [System.Net.HttpWebRequest]::Create($Uri)
        $request.Method = $Method
        if($Headers -and $Headers.Count -gt 0) {
            foreach($key in $Headers.Keys) {
                $request.Headers[$key] = $Headers[$key]
            }
        }
        if($TimeOutSec -gt 0) {
            $request.Timeout = if($TimeOutSec -gt 2147483) { [Int]::MaxValue } else { $TimeOutSec * 1000 }
        }

        if($ForceBasicAuth) {
            if(!$request.Credentials) {
                throw "ForceBasicAuth requires Credentials!"
            }
            if(!$Headers -or !$Headers.ContainsKey('Authorization')) {
                $request.Headers.Add('Authorization', 'Basic ' + [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($request.Credentials.UserName+":"+$request.Credentials.Password )))
            }
        }

        if($DebugPreference -ne "SilentlyContinue") {
            Set-Variable WebRequest -Scope 2 -Value $request
        }
        $ErrorActionPreference = $EAP

        # And override session values with user values if they provided any
        $request.UserAgent = $UserAgent

        # Authentication normally uses EITHER credentials or certificates, but what do I know ...
        if($Certificate) {
            $request.ClientCertificates.AddRange($Certificate)
        }
        if($UseDefaultCredentials) {
            $request.UseDefaultCredentials = $true
        } elseif($Credential -ne [System.Management.Automation.PSCredential]::Empty) {
            $request.Credentials = $Credential.GetNetworkCredential()
        }

        # You don't have to specify a proxy to specify proxy credentials (maybe your default proxy takes creds)
        if($Proxy) { $request.Proxy = New-Object System.Net.WebProxy $Proxy }
        if($request.Proxy -ne $null) {
            if($ProxyUseDefaultCredentials) {
                $request.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
            } elseif($ProxyCredentials -ne [System.Management.Automation.PSCredential]::Empty) {
                $request.Proxy.Credentials = $ProxyCredentials
            }
        }

        $request.ContentType = if($ContentType) { $contentType } elseif("Post" -eq $Method) { "application/x-www-form-urlencoded" }
        if($Body) {
            if ($body -as [Collections.IDictionary] -and "Post" -eq $Method)
            {
                $content = Format-Dictionary $body
                Set-RequestContent $request $content
            }
            elseif ($body -is [Xml.XmlNode])
            {
                $splat = @{ content = $body.OuterXml }
                if($doc = $body -as [Xml.XmlDocument]) {
                    if($decl = $doc.FirstChild -as [Xml.XmlDeclaration]) {
                        $splat.encoding = $decl.Encoding
                    }
                }
                Set-RequestContent $request @splat
            }
            elseif ($body -is [IO.Stream])
            {
                throw "Stream as content not implemented yet"
            }
            elseif ($body -is [byte[]])
            {
                Set-RequestContent $request $content
            }
            else {
                Set-RequestContent $request ([System.Management.Automation.LanguagePrimitives]::ConvertTo($body, [string], [IFormatProvider]::InvariantCulture))
            }
        }

        try {
            $response = $request.GetResponse();
            if($DebugPreference -ne "SilentlyContinue") {
                Set-Variable WebResponse -Scope 2 -Value $response
            }
        } catch [System.Net.WebException] { 
            Write-Error $_.Exception -Category ResourceUnavailable
            return
        } catch { # Extra catch just in case, I can't remember what might fall here
            Write-Error $_.Exception -Category NotImplemented
            return
        }
   
        Write-Verbose "Retrieved $($Response.ResponseUri): $($Response.StatusCode)"
        if((Test-Path variable:response) -and $response.StatusCode -eq 200) {
            Write-Verbose "OutFile: $OutFile"

            # Magics to figure out a file location based on the response
            if($OutFile) {
                $EAP,$ErrorActionPreference = $ErrorActionPreference, "Stop"          
                # When you need to convert a path that might not exist yet ...
                $OutFile = New-Item -Path $OutFile -Type File -Force | Convert-Path
                $ErrorActionPreference = $EAP
            }

            if(!$OutFile) {
                $Headers = @{}
                foreach($h in $response.Headers){ $Headers.$h = $response.GetResponseHeader($h) }
                $Result = @{
                    BaseResponse = $response
                    Headers = $Headers
                    RawContentStream = New-Object System.IO.MemoryStream $response.ContentLength
                    RawContentLength = $response.ContentLength
                    Content = $null
                    StatusCode = [int]$response.StatusCode
                    StatusDescription = $response.StatusDescription
                }
                if($response.CharacterSet) {
                    $encoding = [System.Text.Encoding]::GetEncoding( $response.CharacterSet )
                    $Result.Content = ""
                } else {
                    $encoding = $null
                    $Result.Content = New-Object 'byte[]' $response.ContentLength
                }
            }
   
            try {
                [int]$goal = $response.ContentLength
                $reader = $response.GetResponseStream()
                $ms = 

                if($OutFile) {
                    try {
                        $writer = New-Object System.IO.FileStream $OutFile, "Create"
                    } catch { # Catch just in case, lots of things could go wrong ...
                        Write-Error $_.Exception -Category WriteError
                        return
                    }
                }        
                [byte[]]$buffer = new-object byte[] 1mb
                [int]$total = [int]$count = 0
                do {
                    $count = $reader.Read($buffer, 0, $buffer.Length);
                    if($OutFile) {
                        $writer.Write($buffer, 0, $count)
                    } else {
                        $Result.RawContentStream.Write($buffer, 0, $count)
                        if($encoding) {
                            $Result.Content += $encoding.GetString($buffer,0,$count)
                        }
                    }

                    # This is unecessary, but nice to have
                    if(!$quiet) {
                        $total += $count
                        if($goal -gt 0) {
                            Write-Progress -Activity "Downloading $Uri" -Status "Saving $total of $goal" -id 0 -percentComplete (($total/$goal)*100)
                        } else {
                            Write-Progress -Activity "Downloading $Uri" -Status "Saving $total bytes..." -id 0
                        }
                    }
                } while ($count -gt 0)

            } catch [Exception] {
                $PSCmdlet.WriteError( (New-Object System.Management.Automation.ErrorRecord $_.Exception, "Unexpected Exception", "InvalidResult", $_) )
                Write-Error "Could not download package from $Url"
            } finally {
                if(Test-Path variable:Reader) {
                    $Reader.Close()
                    $Reader.Dispose()
                }
                if(Test-Path variable:Writer) {
                    $writer.Flush()
                    $Writer.Close()
                    $Writer.Dispose()
                }
            }

            if(!$Outfile -and !$encoding) {
                [Array]::Copy( $Result.RawContentStream.GetBuffer(), $Result.Content, $response.ContentLength )
            }
        
            Write-Progress -Activity "Finished Downloading $Uri" -Status "Saved $total bytes..." -id 0 -Completed

            # I have a fundamental disagreement with Microsoft about what the output should be
            if($OutFile) {
                Get-Item $OutFile
            } elseif(Test-Path variable:local:Result) {
                $Result = New-Object PSObject -Property $Result
                $Result.PSTypeNames.Insert(0, "Microsoft.PowerShell.Commands.WebResponseObject")
                $Result.PSTypeNames.Insert(0, "Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject")
                return $Result
            }
        }
        if(Test-Path variable:response) {
            $response.Close(); 
            # HttpWebResponse doesn't have Dispose (in .net 2?)
            # $response.Dispose(); 
        }
    }
}

Export-ModuleMember Invoke-WebRequest
}
