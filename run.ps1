using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)
# Write to the Azure Functions log stream.
Write-Host " PowerShell HTTP trigger function processed a request."

$response = $null
$OAuth = @{
    'ApiKey' = $env:TwitterApiKey
    'ApiSecret' = $env:TwitterApiSecret
    'AccessToken' = $env:TwitterAccessToken 
    'AccessTokenSecret' = $env:TwitterAccessTokenSecret
}

if($Request.Body.Resource -eq "media/upload.json")
{
    $ResourceURL = "https://upload.twitter.com/1.1/$($Request.Body.Resource)"
}
else
{
    $ResourceURL = "https://api.twitter.com/1.1/$($Request.Body.Resource)"
}

$Method = $Request.Body.Method.toUpper()
$Parameters = @{}
$jsonObj =  $Request.Body.Parameters
ForEach ($key in $jsonObj.Keys)
{

$keyIndex =  $($jsonObj.Keys).indexOf($key)

if($jsonObj.Keys.Count>1)
{
$keyValue = $($jsonObj.Values)[$keyIndex]
}
else
{
    $keyValue = $jsonObj.Values
}
$Parameters[$key] = $($keyValue -replace 'http.*://',"" -replace ':',"")
}

#HTTP request body json
$PostBody =  $Request.Body.PostBody

function Get-OAuth {

     <#

          .SYNOPSIS

           This function creates the authorization string needed to send a POST or GET message to the Twitter API

 

          .PARAMETER AuthorizationParams

           This hashtable should the following key value pairs

           HttpEndPoint - the twitter resource url [Can be found here: https://dev.twitter.com/rest/public]

           RESTVerb - Either 'GET' or 'POST' depending on the action

           Params - A hashtable containing the rest parameters (key value pairs) associated that method

           OAuthSettings - A hashtable that must contain only the following keys and their values (Generate here: https://dev.twitter.com/oauth)

                       ApiKey

                       ApiSecret

                       AccessToken

                       AccessTokenSecret

          .LINK

           This function evolved from code found in Adam Betram's Get-OAuthAuthorization function in his MyTwitter module.

           The MyTwitter module can be found here: https://gallery.technet.microsoft.com/scriptcenter/Tweet-and-send-Twitter-DMs-8c2d6f0a

           Adam Betram's blogpost here: http://www.adamtheautomator.com/twitter-powershell/ provides a detailed explanation

           about how to generate an access token needed to create the authorization string

 

          .EXAMPLE

            $OAuth = @{'ApiKey' = 'yourapikey'; 'ApiSecret' = 'yourapisecretkey';'AccessToken' = 'yourapiaccesstoken';'AccessTokenSecret' = 'yourapitokensecret'}   

            $Parameters = @{'q'='rumi'}

            $AuthParams = @{}

            $AuthParams.Add('HttpEndPoint', 'https://api.twitter.com/1.1/search/tweets.json')

            $AuthParams.Add('RESTVerb', 'GET')

            $AuthParams.Add('Params', $Parameters)

            $AuthParams.Add('OAuthSettings', $OAuth)

            $AuthorizationString = Get-OAuth -AuthorizationParams $AuthParams

 

         

     #>

    [OutputType('System.Management.Automation.PSCustomObject')]

     Param($AuthorizationParams)

     process{

     try {

         Write-Host "oauth in process "

            ## Generate a random 32-byte string. I'm using the current time (in seconds) and appending 5 chars to the end to get to 32 bytes

            ## Base64 allows for an '=' but Twitter does not.  If this is found, replace it with some alphanumeric character

            $OauthNonce = [System.Convert]::ToBase64String(([System.Text.Encoding]::ASCII.GetBytes("$([System.DateTime]::Now.Ticks.ToString())12345"))).Replace('=', 'g')

            ## Find the total seconds since 1/1/1970 (epoch time)

            $EpochTimeNow = [System.DateTime]::UtcNow - [System.DateTime]::ParseExact("01/01/1970", "dd'/'MM'/'yyyy", $null)

            $OauthTimestamp = [System.Convert]::ToInt64($EpochTimeNow.TotalSeconds).ToString();

            ## Build the signature

            $SignatureBase = "$([System.Uri]::EscapeDataString($AuthorizationParams.HttpEndPoint))&"

            $SignatureParams = @{

                'oauth_consumer_key' = $AuthorizationParams.OAuthSettings.ApiKey;

                'oauth_nonce' = $OauthNonce;

                'oauth_signature_method' = 'HMAC-SHA1';

                'oauth_timestamp' = $OauthTimestamp;

                'oauth_token' = $AuthorizationParams.OAuthSettings.AccessToken;

                'oauth_version' = '1.0';

            }

           

            $AuthorizationParams.Params.Keys | % { $SignatureParams.Add($_ , [System.Net.WebUtility]::UrlEncode($AuthorizationParams.Params.Item($_)).Replace('+','%20'))}

            ## Create a string called $SignatureBase that joins all URL encoded 'Key=Value' elements with a &

            ## Remove the URL encoded & at the end and prepend the necessary 'POST&' verb to the front

            $SignatureParams.GetEnumerator() | sort name | foreach { $SignatureBase += [System.Uri]::EscapeDataString("$($_.Key)=$($_.Value)&") }

            $SignatureBase = $SignatureBase.Substring(0,$SignatureBase.Length-1)

            $SignatureBase = $SignatureBase.Substring(0,$SignatureBase.Length-1)

            $SignatureBase = $SignatureBase.Substring(0,$SignatureBase.Length-1)

            $SignatureBase = $AuthorizationParams.RESTVerb+'&' + $SignatureBase

            

            ## Create the hashed string from the base signature

            $SignatureKey = [System.Uri]::EscapeDataString($AuthorizationParams.OAuthSettings.ApiSecret) + "&" + [System.Uri]::EscapeDataString($AuthorizationParams.OAuthSettings.AccessTokenSecret);

            

            $hmacsha1 = new-object System.Security.Cryptography.HMACSHA1;

            $hmacsha1.Key = [System.Text.Encoding]::ASCII.GetBytes($SignatureKey);

            $OauthSignature = [System.Convert]::ToBase64String($hmacsha1.ComputeHash([System.Text.Encoding]::ASCII.GetBytes($SignatureBase)));

            

            ## Build the authorization headers using most of the signature headers elements.  This is joining all of the 'Key=Value' elements again

            ## and only URL encoding the Values this time while including non-URL encoded double quotes around each value

            $AuthorizationParams = $SignatureParams

            $AuthorizationParams.Add('oauth_signature', $OauthSignature)

        

            

            $AuthorizationString = 'OAuth '

            $AuthorizationParams.GetEnumerator() | sort name | foreach { $AuthorizationString += $_.Key + '="' + [System.Uri]::EscapeDataString($_.Value) + '", ' }

            $AuthorizationString = $AuthorizationString.TrimEnd(', ')

            Write-Verbose "Using authorization string '$AuthorizationString'"           

            $AuthorizationString

 

        }

        catch {

            Write-Error $_.Exception.Message

        }

 

     }

 

}

 

function Invoke-TwitterRestMethod{

<#

          .SYNOPSIS

           This function sends a POST or GET message to the Twitter API and returns the JSON response.

 

          .PARAMETER ResourceURL

           The desired twitter resource url [REST APIs can be found here: https://dev.twitter.com/rest/public]

          

          .PARAMETER RestVerb

           Either 'GET' or 'POST' depending on the resource URL

 

           .PARAMETER  Parameters

           A hashtable containing the rest parameters (key value pairs) associated that resource url. Pass empty hash if no paramters needed.

 

           .PARAMETER OAuthSettings

           A hashtable that must contain only the following keys and their values (Generate here: https://dev.twitter.com/oauth)

                       ApiKey

                       ApiSecret

                       AccessToken

                       AccessTokenSecret

 

           .EXAMPLE

            $OAuth = @{'ApiKey' = 'yourapikey'; 'ApiSecret' = 'yourapisecretkey';'AccessToken' = 'yourapiaccesstoken';'AccessTokenSecret' = 'yourapitokensecret'}

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/mentions_timeline.json' -RestVerb 'GET' -Parameters @{} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/user_timeline.json' -RestVerb 'GET' -Parameters @{'count' = '1'} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/home_timeline.json' -RestVerb 'GET' -Parameters @{'count' = '1'} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/retweets_of_me.json' -RestVerb 'GET' -Parameters @{} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/search/tweets.json' -RestVerb 'GET' -Parameters @{'q'='powershell';'count' = '1'}} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/account/settings.json' -RestVerb 'POST' -Parameters @{'lang'='tr'} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/retweets/509457288717819904.json' -RestVerb 'GET' -Parameters @{} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/show.json' -RestVerb 'GET' -Parameters @{'id'='123'} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/destroy/240854986559455234.json' -RestVerb 'GET' -Parameters @{} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/update.json' -RestVerb 'POST' -Parameters @{'status'='@FollowBot'} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/direct_messages.json' -RestVerb 'GET' -Parameters @{} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/direct_messages/destroy.json' -RestVerb 'POST' -Parameters @{'id' = '559298305029844992'} -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/direct_messages/new.json' -RestVerb 'POST' -Parameters @{'text' = 'hello, there'; 'screen_name' = 'ruminaterumi' } -OAuthSettings $OAuth

            $mediaId = Invoke-TwitterMEdiaUpload -MediaFilePath 'C:\Books\pic.png' -ResourceURL 'https://upload.twitter.com/1.1/media/upload.json' -OAuthSettings $OAuth

            Invoke-TwitterRestMethod -ResourceURL 'https://api.twitter.com/1.1/statuses/update.json' -RestVerb 'POST' -Parameters @{'status'='FollowBot'; 'media_ids' = $mediaId } -OAuthSettings $OAuth

 

     #>

         [CmdletBinding()]

         [OutputType('System.Management.Automation.PSCustomObject')]

         Param(

                [Parameter(Mandatory)]

                [string]$ResourceURL,

                [Parameter(Mandatory)]

                [string]$RestVerb,

                [Parameter(Mandatory)]

                $Parameters,
                [Parameter(Mandatory)]

                $PostBody,

                [Parameter(Mandatory)]

                $OAuthSettings

                )


          process{

              try{

                    $AuthParams = @{}

                    $AuthParams.Add('HttpEndPoint', $ResourceURL)

                    $AuthParams.Add('RESTVerb', $RestVerb)

                    $AuthParams.Add('Params', $Parameters)

                    $AuthParams.Add('OAuthSettings', $OAuthSettings)

                    $AuthorizationString = Get-OAuth -AuthorizationParams $AuthParams

                    $HTTPEndpoint= $ResourceURL

                    if($Parameters.Count -gt 0)

                    {
                        
                    #Write-Host "test 3"
                        $HTTPEndpoint = $HTTPEndpoint + '?'

                        $Parameters.Keys | % { $HTTPEndpoint = $HTTPEndpoint + $_  +'='+ [System.Net.WebUtility]::UrlEncode($Parameters.Item($_)).Replace('+','%20') + '&'}
                   
                        $HTTPEndpoint = $HTTPEndpoint.Substring(0,$HTTPEndpoint.Length-1)
                    #$HTTPEndpoint = 'https://api.twitter.com/1.1/search/tweets.json?count=1&q=that_API_guy'
                   
                    }

                    Invoke-RestMethod -URI $HTTPEndpoint -Method $RestVerb -Body $PostBody -Headers @{ 'Authorization' = $AuthorizationString } -ContentType "application/json"

                  }

                  catch{

                    Write-Error $_.Exception.Message

                  }

            }

}

function Invoke-TwitterMediaUpload{

<#
          .SYNOPSIS
           This function uploads a media file to twitter and returns the media file id. 

          .PARAMETER ResourceURL
           The desired twitter media upload resource url For API 1.1 https://upload.twitter.com/1.1/media/upload.json [REST APIs can be found here: https://dev.twitter.com/rest/public]
           
          .PARAMETER MediaFilePath 
          Local path of media

          .PARAMETER OAuthSettings 
           A hashtable that must contain only the following keys and their values (Generate here: https://dev.twitter.com/oauth)
                       ApiKey 
                       ApiSecret 
		               AccessToken
	                   AccessTokenSecret
          .LINK
          This function evolved from the following blog post https://devcentral.f5.com/articles/introducing-poshtwitpic-ndash-use-powershell-to-post-your-images-to-twitter-via-twitpic
#>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)][string]$media,
        #[parameter(Mandatory)][System.IO.FileInfo] $MediaFilePath,
        [parameter(Mandatory)] [System.URI] $ResourceURL,
        [Parameter(Mandatory)]$OAuthSettings
    )

    process{
  
     try{
           $Parameters = @{}
           $AuthParams = @{}
           $AuthParams.Add('HttpEndPoint', $ResourceURL)
           $AuthParams.Add('RESTVerb', "POST")
           $AuthParams.Add('Params', $Parameters)
           $AuthParams.Add('OAuthSettings', $o)
           $AuthorizationString = Get-OAuth -AuthorizationParams $AuthParams
           $boundary = [System.Guid]::NewGuid().ToString();
           $header = "--{0}" -f $boundary;
           $footer = "--{0}--" -f $boundary;
         #  [System.Text.StringBuilder]$contents = New-Object System.Text.StringBuilder
          # [void]$contents.AppendLine($header);
         #  $bytes = [System.IO.File]::ReadAllBytes($MediaFilePath)
           #$enc = [System.Text.Encoding]::GetEncoding("iso-8859-1")
         #  $filedata = $enc.GetString($bytes)
         <# $contentTypeMap = @{
                    ".jpg"  = "image/jpeg";
                    ".jpeg" = "image/jpeg";
                    ".gif"  = "image/gif";
                    ".png"  = "image/png";
                 }#>
          # $fileContentType = $contentTypeMap[$MediaFilePath.Extension.ToLower()]
          # $fileHeader = "Content-Disposition: file; name=""{0}""; filename=""{1}""" -f "media", $file.Name  
          # [void]$contents.AppendLine($fileHeader)
          # [void]$contents.AppendLine("Content-Type: {0}" -f $fileContentType)
          # [void]$contents.AppendLine()
          # [void]$contents.AppendLine($fileData)
           #[void]$contents.AppendLine($footer)
          # $z =  $contents.ToString()
           $response = Invoke-RestMethod -Uri $ResourceURL -Body $media -Method Post -Headers @{ 'Authorization' = $AuthorizationString } -ContentType "multipart/form-data; boundary=`"$boundary`""
           $response.media_id
    }
    catch [System.Net.WebException] {
        Write-Error( "FAILED to reach '$URL': $_" )
        $_
        throw $_
    }
    }
}

<#if($Request.Body.Resource -eq "media/upload.json")
{
$mediaId = Invoke-TwitterMediaUpload -media $media -ResourceURL 'https://upload.twitter.com/1.1/media/upload.json' -OAuthSettings $OAuth  
}#>

$Tweet = Invoke-TwitterRestMethod -ResourceURL $ResourceURL -RestVerb $Method -Parameters $Parameters -OAuthSettings $OAuth -PostBody $PostBody

$response = $Tweet | ConvertTo-Json -depth 5 | Out-String

#$response | Out-File -Encoding Ascii -FilePath $Response

$status = [HttpStatusCode]::OK

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
StatusCode = $status
Body = $response
}) 
Write-Output $Parameters
Write-Host $Parameters
Write-Output "http message response '$response'"

Write-Output "http trigger completed: $(get-date)"
