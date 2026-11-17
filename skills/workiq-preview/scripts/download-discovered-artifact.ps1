#Requires -Version 7.0

[CmdletBinding()]
param(
    [string] $ReferenceUrl,

    [string] $OutFile,

    [string] $AccessToken,

    [ValidateSet('Production', 'Test')]
    [string] $Environment = 'Production',

    [switch] $Overwrite,

    [switch] $NonInteractive,

    [switch] $DeviceCode,

    [switch] $Logout
)

$ErrorActionPreference = 'Stop'
$clientId = 'ba081686-5d24-4bc6-a0d6-d034ecffed87'
$authorizeUrl = 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize'
$tokenUrl = 'https://login.microsoftonline.com/common/oauth2/v2.0/token'
$deviceCodeUrl = 'https://login.microsoftonline.com/common/oauth2/v2.0/devicecode'
$scope = 'api://workiq.svc.cloud.microsoft/.default offline_access openid profile'
$cacheService = 'workiq-artifact-downloader'
$publicOrigin = 'https://workiq.svc.cloud.microsoft'
$testOrigin = 'https://test.workiq.svc.cloud.dev.microsoft'

function Throw-DownloadError {
    param([string] $Code, [string] $Message)

    throw "[$Code] $Message"
}

function Test-ControlCharacter {
    param([string] $Value)

    foreach ($character in $Value.ToCharArray()) {
        if ([char]::IsControl($character)) {
            return $true
        }
    }

    return $false
}

function Resolve-Reference {
    param([string] $Value)

    $uri = $null
    if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref] $uri) -or
        $uri.Scheme -ne 'https' -or
        -not $uri.IsDefaultPort -or
        $uri.UserInfo.Length -ne 0 -or
        $uri.Fragment.Length -ne 0 -or
        (Test-ControlCharacter $Value) -or
        $Value.Contains('\')) {
        Throw-DownloadError 'INVALID_REFERENCE' 'The artifact reference is not a valid HTTPS WorkIQ URL.'
    }

    $origin = $uri.GetLeftPart([UriPartial]::Authority)
    if ($origin -notin @($publicOrigin, $testOrigin)) {
        Throw-DownloadError 'INVALID_REFERENCE' 'The artifact reference origin is not allowed.'
    }

    if ($Value -ne $origin + $uri.PathAndQuery) {
        Throw-DownloadError 'INVALID_REFERENCE' 'The artifact reference contains an alternate URL spelling.'
    }

    $segments = $uri.GetComponents([UriComponents]::Path, [UriFormat]::UriEscaped).Split('/')
    $validRoute =
        ($segments.Count -eq 4 -and
            $segments[0] -eq 'api' -and
            $segments[1] -eq 'catalogs' -and
            $segments[2] -eq 'artifact-references' -and
            -not [string]::IsNullOrWhiteSpace($segments[3])) -or
        ($segments.Count -eq 5 -and
            $segments[0] -eq 'api' -and
            $segments[1] -eq 'catalogs' -and
            -not [string]::IsNullOrWhiteSpace($segments[2]) -and
            $segments[3] -eq 'artifacts' -and
            -not [string]::IsNullOrWhiteSpace($segments[4]))
    if (-not $validRoute) {
        Throw-DownloadError 'INVALID_REFERENCE' 'The artifact reference route is not allowed.'
    }

    foreach ($segment in $segments) {
        if ($segment -in @('.', '..') -or
            $segment.Contains('%2f', [StringComparison]::OrdinalIgnoreCase) -or
            $segment.Contains('%5c', [StringComparison]::OrdinalIgnoreCase)) {
            Throw-DownloadError 'INVALID_REFERENCE' 'The artifact reference contains an invalid path segment.'
        }
    }

    if ($uri.Query.Length -ne 0) {
        $allowedNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $allowedNames.Add('type') | Out-Null
        $allowedNames.Add('version') | Out-Null
        $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($pair in $uri.Query.Substring(1).Split('&')) {
            $separator = $pair.IndexOf('=')
            if ($separator -le 0 -or $separator -eq $pair.Length - 1) {
                Throw-DownloadError 'INVALID_REFERENCE' 'The artifact reference query is invalid.'
            }

            $name = $pair.Substring(0, $separator)
            if (-not $allowedNames.Contains($name) -or -not $names.Add($name)) {
                Throw-DownloadError 'INVALID_REFERENCE' 'The artifact reference query is not allowed.'
            }
        }
    }

    return $uri
}

function Resolve-ServiceReference {
    param([Uri] $Reference)

    if ($Environment -eq 'Test' -and
        $Reference.GetLeftPart([UriPartial]::Authority) -eq $publicOrigin) {
        return [Uri]::new($testOrigin + $Reference.PathAndQuery)
    }

    return $Reference
}

function ConvertTo-Base64Url {
    param([byte[]] $Bytes)

    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Get-CacheBackend {
    if ($IsWindows) {
        return 'WindowsDpapi'
    }
    if ($IsMacOS -and (Test-Path -LiteralPath '/usr/bin/security')) {
        return 'MacOSKeychain'
    }
    if ($IsLinux -and $null -ne (Get-Command secret-tool -ErrorAction SilentlyContinue)) {
        return 'LinuxSecretService'
    }

    return 'None'
}

function Get-WindowsCacheFile {
    $baseDirectory = if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    }
    else {
        $env:LOCALAPPDATA
    }
    return Join-Path (Join-Path $baseDirectory $cacheService) 'auth.dat'
}

function Initialize-MacOSKeychain {
    if ($null -ne ('MacOSKeychainNative' -as [type])) {
        return
    }

    Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class MacOSKeychainNative
{
    private const int Success = 0;
    private const int ItemNotFound = -25300;

    [DllImport("/System/Library/Frameworks/Security.framework/Security")]
    private static extern int SecKeychainFindGenericPassword(
        IntPtr keychainOrArray,
        uint serviceNameLength,
        byte[] serviceName,
        uint accountNameLength,
        byte[] accountName,
        out uint passwordLength,
        out IntPtr passwordData,
        out IntPtr itemRef);

    [DllImport("/System/Library/Frameworks/Security.framework/Security")]
    private static extern int SecKeychainAddGenericPassword(
        IntPtr keychain,
        uint serviceNameLength,
        byte[] serviceName,
        uint accountNameLength,
        byte[] accountName,
        uint passwordLength,
        byte[] passwordData,
        out IntPtr itemRef);

    [DllImport("/System/Library/Frameworks/Security.framework/Security")]
    private static extern int SecKeychainItemModifyAttributesAndData(
        IntPtr itemRef,
        IntPtr attributes,
        uint dataLength,
        byte[] data);

    [DllImport("/System/Library/Frameworks/Security.framework/Security")]
    private static extern int SecKeychainItemDelete(IntPtr itemRef);

    [DllImport("/System/Library/Frameworks/Security.framework/Security")]
    private static extern int SecKeychainItemFreeContent(IntPtr attributes, IntPtr data);

    [DllImport("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")]
    private static extern void CFRelease(IntPtr value);

    public static void Write(string service, string account, string value)
    {
        byte[] serviceBytes = Encoding.UTF8.GetBytes(service);
        byte[] accountBytes = Encoding.UTF8.GetBytes(account);
        byte[] valueBytes = Encoding.UTF8.GetBytes(value);
        IntPtr itemRef = IntPtr.Zero;
        IntPtr existingData = IntPtr.Zero;
        uint existingLength = 0;

        try
        {
            int status = SecKeychainFindGenericPassword(
                IntPtr.Zero,
                (uint)serviceBytes.Length,
                serviceBytes,
                (uint)accountBytes.Length,
                accountBytes,
                out existingLength,
                out existingData,
                out itemRef);

            if (status == Success)
            {
                status = SecKeychainItemModifyAttributesAndData(
                    itemRef,
                    IntPtr.Zero,
                    (uint)valueBytes.Length,
                    valueBytes);
            }
            else if (status == ItemNotFound)
            {
                status = SecKeychainAddGenericPassword(
                    IntPtr.Zero,
                    (uint)serviceBytes.Length,
                    serviceBytes,
                    (uint)accountBytes.Length,
                    accountBytes,
                    (uint)valueBytes.Length,
                    valueBytes,
                    out itemRef);
            }

            if (status != Success)
            {
                throw new InvalidOperationException($"Keychain write failed with status {status}.");
            }
        }
        finally
        {
            if (existingData != IntPtr.Zero)
            {
                SecKeychainItemFreeContent(IntPtr.Zero, existingData);
            }

            if (itemRef != IntPtr.Zero)
            {
                CFRelease(itemRef);
            }

            Array.Clear(valueBytes, 0, valueBytes.Length);
        }
    }

    public static string Read(string service, string account)
    {
        byte[] serviceBytes = Encoding.UTF8.GetBytes(service);
        byte[] accountBytes = Encoding.UTF8.GetBytes(account);
        IntPtr itemRef = IntPtr.Zero;
        IntPtr passwordData = IntPtr.Zero;
        uint passwordLength = 0;

        try
        {
            int status = SecKeychainFindGenericPassword(
                IntPtr.Zero,
                (uint)serviceBytes.Length,
                serviceBytes,
                (uint)accountBytes.Length,
                accountBytes,
                out passwordLength,
                out passwordData,
                out itemRef);
            if (status == ItemNotFound)
            {
                return null;
            }

            if (status != Success)
            {
                throw new InvalidOperationException($"Keychain read failed with status {status}.");
            }

            byte[] valueBytes = new byte[checked((int)passwordLength)];
            try
            {
                Marshal.Copy(passwordData, valueBytes, 0, valueBytes.Length);
                return Encoding.UTF8.GetString(valueBytes);
            }
            finally
            {
                Array.Clear(valueBytes, 0, valueBytes.Length);
            }
        }
        finally
        {
            if (passwordData != IntPtr.Zero)
            {
                SecKeychainItemFreeContent(IntPtr.Zero, passwordData);
            }

            if (itemRef != IntPtr.Zero)
            {
                CFRelease(itemRef);
            }
        }
    }

    public static void Delete(string service, string account)
    {
        byte[] serviceBytes = Encoding.UTF8.GetBytes(service);
        byte[] accountBytes = Encoding.UTF8.GetBytes(account);
        IntPtr itemRef = IntPtr.Zero;
        IntPtr passwordData = IntPtr.Zero;
        uint passwordLength = 0;

        try
        {
            int status = SecKeychainFindGenericPassword(
                IntPtr.Zero,
                (uint)serviceBytes.Length,
                serviceBytes,
                (uint)accountBytes.Length,
                accountBytes,
                out passwordLength,
                out passwordData,
                out itemRef);
            if (status == ItemNotFound)
            {
                return;
            }

            if (status != Success)
            {
                throw new InvalidOperationException($"Keychain lookup failed with status {status}.");
            }

            status = SecKeychainItemDelete(itemRef);
            if (status != Success)
            {
                throw new InvalidOperationException($"Keychain delete failed with status {status}.");
            }
        }
        finally
        {
            if (passwordData != IntPtr.Zero)
            {
                SecKeychainItemFreeContent(IntPtr.Zero, passwordData);
            }

            if (itemRef != IntPtr.Zero)
            {
                CFRelease(itemRef);
            }
        }
    }
}
"@
}

function Save-RefreshToken {
    param([string] $RefreshToken)

    if ([string]::IsNullOrWhiteSpace($RefreshToken)) {
        return
    }

    $cache = [ordered] @{
        refresh_token = $RefreshToken
    } | ConvertTo-Json -Compress

    try {
        switch (Get-CacheBackend) {
            'WindowsDpapi' {
                $authFile = Get-WindowsCacheFile
                $authDirectory = [IO.Path]::GetDirectoryName($authFile)
                if (-not (Test-Path -LiteralPath $authDirectory)) {
                    New-Item -ItemType Directory -Path $authDirectory -Force | Out-Null
                }

                $encrypted = ConvertTo-SecureString $cache -AsPlainText -Force | ConvertFrom-SecureString
                Set-Content -LiteralPath $authFile -Value $encrypted -Encoding ascii
            }
            'MacOSKeychain' {
                Initialize-MacOSKeychain
                [MacOSKeychainNative]::Write($cacheService, [Environment]::UserName, $cache)
            }
            'LinuxSecretService' {
                $secretTool = (Get-Command secret-tool -ErrorAction Stop).Source
                $cache | & $secretTool store --label='WorkIQ artifact downloader' service $cacheService
                if ($LASTEXITCODE -ne 0) {
                    throw 'Secret Service write failed.'
                }
            }
            'None' {
                Write-Verbose 'No supported secure credential store is available; the refresh token was not saved.'
            }
        }
    }
    catch {
        Write-Warning 'The sign-in succeeded, but the refresh token could not be saved in the platform credential store.'
    }
}

function Read-RefreshToken {
    try {
        $cache = switch (Get-CacheBackend) {
            'WindowsDpapi' {
                $authFile = Get-WindowsCacheFile
                if (-not (Test-Path -LiteralPath $authFile)) {
                    return $null
                }

                $secureValue = (Get-Content -LiteralPath $authFile -Raw).Trim() | ConvertTo-SecureString
                $valuePointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureValue)
                try {
                    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($valuePointer)
                }
                finally {
                    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($valuePointer)
                }
            }
            'MacOSKeychain' {
                Initialize-MacOSKeychain
                [MacOSKeychainNative]::Read($cacheService, [Environment]::UserName)
            }
            'LinuxSecretService' {
                $secretTool = (Get-Command secret-tool -ErrorAction Stop).Source
                $value = & $secretTool lookup service $cacheService 2>$null
                if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($value)) {
                    return $null
                }
                $value
            }
            'None' {
                return $null
            }
        }

        return ($cache | ConvertFrom-Json).refresh_token
    }
    catch {
        Write-Verbose 'The cached WorkIQ credential could not be read.'
        return $null
    }
}

function Remove-AuthCache {
    try {
        switch (Get-CacheBackend) {
            'WindowsDpapi' {
                $authFile = Get-WindowsCacheFile
                if (Test-Path -LiteralPath $authFile) {
                    Remove-Item -LiteralPath $authFile -Force
                }
            }
            'MacOSKeychain' {
                Initialize-MacOSKeychain
                [MacOSKeychainNative]::Delete($cacheService, [Environment]::UserName)
            }
            'LinuxSecretService' {
                $secretTool = (Get-Command secret-tool -ErrorAction Stop).Source
                & $secretTool clear service $cacheService 2>$null
                if ($LASTEXITCODE -ne 0) {
                    throw 'Secret Service delete failed.'
                }
            }
        }
    }
    catch {
        Throw-DownloadError 'LOGOUT_FAILED' 'The cached credential could not be removed from the platform credential store.'
    }
}

function Open-SystemBrowser {
    param([string] $Url)

    try {
        if ($IsWindows) {
            Start-Process $Url | Out-Null
            return $true
        }
        if ($IsMacOS) {
            & /usr/bin/open $Url
            return $LASTEXITCODE -eq 0
        }
        if ($IsLinux) {
            $isWsl = -not [string]::IsNullOrWhiteSpace($env:WSL_DISTRO_NAME) -or
                (Test-Path -LiteralPath '/proc/sys/fs/binfmt_misc/WSLInterop')
            if ($isWsl) {
                $wslView = Get-Command wslview -ErrorAction SilentlyContinue
                if ($null -ne $wslView) {
                    & $wslView.Source $Url
                    return $LASTEXITCODE -eq 0
                }

                $windowsShell = Get-Command cmd.exe -ErrorAction SilentlyContinue
                if ($null -ne $windowsShell) {
                    & $windowsShell.Source /c start '""' $Url
                    return $LASTEXITCODE -eq 0
                }
            }

            $xdgOpen = Get-Command xdg-open -ErrorAction SilentlyContinue
            if ($null -ne $xdgOpen) {
                & $xdgOpen.Source $Url
                return $LASTEXITCODE -eq 0
            }
        }
    }
    catch {
        return $false
    }

    return $false
}

function New-TokenResult {
    param([object] $TokenResponse)

    if ([string]::IsNullOrWhiteSpace($TokenResponse.access_token)) {
        Throw-DownloadError 'AUTH_FAILED' 'Microsoft identity did not return an access token.'
    }

    Save-RefreshToken ([string] $TokenResponse.refresh_token)
    return [string] $TokenResponse.access_token
}

function Invoke-BrowserLogin {
    $verifierBytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($verifierBytes)
    $verifier = ConvertTo-Base64Url $verifierBytes
    $challengeBytes = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::ASCII.GetBytes($verifier))
    $challenge = ConvertTo-Base64Url $challengeBytes
    $stateBytes = [byte[]]::new(16)
    [Security.Cryptography.RandomNumberGenerator]::Fill($stateBytes)
    $state = ConvertTo-Base64Url $stateBytes

    $portListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $portListener.Start()
    $port = $portListener.LocalEndpoint.Port
    $portListener.Stop()

    $redirectUrl = "http://localhost:$port/"
    $listener = [Net.HttpListener]::new()
    $listener.Prefixes.Add($redirectUrl)
    try {
        $listener.Start()
        $loginUrl =
            "$authorizeUrl`?client_id=$clientId" +
            '&response_type=code' +
            "&redirect_uri=$([Uri]::EscapeDataString($redirectUrl))" +
            '&response_mode=query' +
            "&scope=$([Uri]::EscapeDataString($scope))" +
            "&state=$state" +
            "&code_challenge=$challenge" +
            '&code_challenge_method=S256' +
            '&prompt=select_account'
        Write-Host 'Opening a browser to sign in to WorkIQ.'
        if (-not (Open-SystemBrowser $loginUrl)) {
            return $null
        }

        $contextTask = $listener.GetContextAsync()
        if (-not $contextTask.Wait([TimeSpan]::FromSeconds(120))) {
            Write-Warning 'The browser callback timed out; switching to device-code sign-in.'
            return $null
        }

        $context = $contextTask.GetAwaiter().GetResult()
        $query = $context.Request.QueryString
        $responseHtml = '<html><body><h3>WorkIQ sign-in complete.</h3>You can close this tab.</body></html>'
        $responseBytes = [Text.Encoding]::UTF8.GetBytes($responseHtml)
        $context.Response.ContentType = 'text/html'
        $context.Response.OutputStream.Write($responseBytes, 0, $responseBytes.Length)
        $context.Response.Close()

        if (-not [string]::IsNullOrWhiteSpace($query['error'])) {
            Throw-DownloadError 'AUTH_FAILED' 'Microsoft identity sign-in was not completed.'
        }
        if ($query['state'] -cne $state) {
            Throw-DownloadError 'AUTH_FAILED' 'Microsoft identity returned an invalid sign-in state.'
        }

        $code = $query['code']
        if ([string]::IsNullOrWhiteSpace($code)) {
            Throw-DownloadError 'AUTH_FAILED' 'Microsoft identity did not return an authorization code.'
        }

        $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -ContentType 'application/x-www-form-urlencoded' -Body @{
            client_id = $clientId
            grant_type = 'authorization_code'
            code = $code
            redirect_uri = $redirectUrl
            code_verifier = $verifier
            scope = $scope
        }
    }
    catch {
        if ($_.Exception.Message.StartsWith('[AUTH_FAILED]', [StringComparison]::Ordinal)) {
            throw
        }

        Write-Warning 'Browser sign-in was unavailable; switching to device-code sign-in.'
        return $null
    }
    finally {
        if ($listener.IsListening) {
            $listener.Stop()
        }
        $listener.Close()
    }

    return New-TokenResult $tokenResponse
}

function Invoke-DeviceCodeLogin {
    try {
        $deviceResponse = Invoke-RestMethod -Method Post -Uri $deviceCodeUrl `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                client_id = $clientId
                scope = $scope
            }
    }
    catch {
        Throw-DownloadError 'AUTH_FAILED' 'Microsoft identity could not start device-code sign-in.'
    }

    Write-Host ([string] $deviceResponse.message)
    $interval = [Math]::Max(1, [int] $deviceResponse.interval)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds([int] $deviceResponse.expires_in)

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds $interval
        try {
            $statusCode = 0
            $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl `
                -ContentType 'application/x-www-form-urlencoded' `
                -SkipHttpErrorCheck `
                -StatusCodeVariable statusCode `
                -Body @{
                    client_id = $clientId
                    grant_type = 'urn:ietf:params:oauth:grant-type:device_code'
                    device_code = $deviceResponse.device_code
                }
        }
        catch {
            Throw-DownloadError 'AUTH_FAILED' 'Microsoft identity could not complete device-code sign-in.'
        }

        if ($statusCode -eq 200) {
            return New-TokenResult $tokenResponse
        }

        switch ([string] $tokenResponse.error) {
            'authorization_pending' {
                continue
            }
            'slow_down' {
                $interval += 5
                continue
            }
            'authorization_declined' {
                Throw-DownloadError 'AUTH_FAILED' 'Device-code sign-in was declined.'
            }
            'expired_token' {
                Throw-DownloadError 'AUTH_FAILED' 'The device code expired before sign-in completed.'
            }
            default {
                Throw-DownloadError 'AUTH_FAILED' 'Device-code sign-in failed.'
            }
        }
    }

    Throw-DownloadError 'AUTH_FAILED' 'The device code expired before sign-in completed.'
}

function Update-TokenSilently {
    param([string] $RefreshToken)

    if ([string]::IsNullOrWhiteSpace($RefreshToken)) {
        return $null
    }

    try {
        $tokenResponse = Invoke-RestMethod -Method Post -Uri $tokenUrl -ContentType 'application/x-www-form-urlencoded' -Body @{
            client_id = $clientId
            grant_type = 'refresh_token'
            refresh_token = $RefreshToken
            scope = $scope
        }
    }
    catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($tokenResponse.refresh_token)) {
        $tokenResponse | Add-Member -NotePropertyName refresh_token -NotePropertyValue $RefreshToken
    }
    return New-TokenResult $tokenResponse
}

function Get-WorkIqToken {
    param([string] $SuppliedToken)

    if (-not [string]::IsNullOrWhiteSpace($SuppliedToken)) {
        return $SuppliedToken
    }
    if (-not [string]::IsNullOrWhiteSpace($env:WORKIQ_ACCESS_TOKEN)) {
        return $env:WORKIQ_ACCESS_TOKEN
    }

    $token = Update-TokenSilently (Read-RefreshToken)
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        return $token
    }

    if ($NonInteractive) {
        Throw-DownloadError 'AUTH_REQUIRED' 'No supplied token or usable cached credential is available in noninteractive mode.'
    }

    if ($DeviceCode) {
        return Invoke-DeviceCodeLogin
    }

    $token = Invoke-BrowserLogin
    if ([string]::IsNullOrWhiteSpace($token)) {
        $token = Invoke-DeviceCodeLogin
    }

    return $token
}

function Resolve-OutputPath {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value) -or (Test-ControlCharacter $Value)) {
        Throw-DownloadError 'NOT_WRITABLE' 'The output path is invalid.'
    }

    $fullPath = [IO.Path]::GetFullPath($Value)
    $parent = [IO.Path]::GetDirectoryName($fullPath)
    if (-not [IO.Directory]::Exists($parent)) {
        Throw-DownloadError 'NOT_WRITABLE' 'The output directory does not exist.'
    }

    for ($current = $parent; -not [string]::IsNullOrWhiteSpace($current); $current = [IO.Path]::GetDirectoryName($current)) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-DownloadError 'NOT_WRITABLE' 'The output path traverses a link.'
        }
    }

    if (Test-Path -LiteralPath $fullPath) {
        $item = Get-Item -LiteralPath $fullPath -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.PSIsContainer) {
            Throw-DownloadError 'NOT_WRITABLE' 'The output path must be a regular file.'
        }
        if (-not $Overwrite) {
            Throw-DownloadError 'TARGET_EXISTS' 'The output file exists. Use -Overwrite or another path.'
        }
    }

    return $fullPath
}

if ($Logout) {
    if (-not [string]::IsNullOrWhiteSpace($ReferenceUrl) -or
        -not [string]::IsNullOrWhiteSpace($OutFile) -or
        -not [string]::IsNullOrWhiteSpace($AccessToken) -or
        $Environment -ne 'Production' -or
        $Overwrite -or
        $NonInteractive -or
        $DeviceCode) {
        Throw-DownloadError 'INVALID_ARGUMENT' 'Use -Logout without download or authentication parameters.'
    }

    Remove-AuthCache
    [ordered] @{
        state = 'logged_out'
        credentialStore = Get-CacheBackend
    } | ConvertTo-Json -Compress
    return
}

if ([string]::IsNullOrWhiteSpace($ReferenceUrl) -or [string]::IsNullOrWhiteSpace($OutFile)) {
    Throw-DownloadError 'INVALID_ARGUMENT' 'ReferenceUrl and OutFile are required for a download.'
}
if ($NonInteractive -and $DeviceCode) {
    Throw-DownloadError 'INVALID_ARGUMENT' 'Device-code sign-in is interactive and cannot be combined with -NonInteractive.'
}

$reference = Resolve-ServiceReference (Resolve-Reference $ReferenceUrl)
$target = Resolve-OutputPath $OutFile
Write-Verbose "Artifact endpoint: $($reference.GetLeftPart([UriPartial]::Authority))"
$token = Get-WorkIqToken $AccessToken
$temporary = [IO.Path]::Combine([IO.Path]::GetDirectoryName($target), ".workiq-artifact-$([Guid]::NewGuid().ToString('N')).tmp")
$handler = [Net.Http.HttpClientHandler]::new()
$handler.AllowAutoRedirect = $false
$handler.AutomaticDecompression = [Net.DecompressionMethods]::None
$client = [Net.Http.HttpClient]::new($handler)
$client.Timeout = [TimeSpan]::FromMinutes(5)

try {
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Get, $reference)
    $request.Headers.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $token)
    if ($reference.GetLeftPart([UriPartial]::Authority) -eq $testOrigin) {
        $request.Headers.Add('X-EndpointId', '2')
    }

    try {
        $response = $client.Send($request, [Net.Http.HttpCompletionOption]::ResponseHeadersRead)
    }
    finally {
        $request.Dispose()
    }

    try {
        if ($response.StatusCode -in @([Net.HttpStatusCode]::Unauthorized, [Net.HttpStatusCode]::Forbidden)) {
            Throw-DownloadError 'AUTH_FAILED' 'WorkIQ rejected the authenticated artifact request.'
        }
        if ($response.StatusCode -eq [Net.HttpStatusCode]::NotFound) {
            Throw-DownloadError 'REFERENCE_EXPIRED' 'The artifact reference is invalid or expired. Run discover again.'
        }
        if (-not $response.IsSuccessStatusCode) {
            Throw-DownloadError 'DOWNLOAD_FAILED' "WorkIQ returned HTTP $([int] $response.StatusCode)."
        }
        if ($response.Headers.Location -or [int] $response.StatusCode -in 300..399) {
            Throw-DownloadError 'DOWNLOAD_FAILED' 'Redirected artifact responses are not allowed.'
        }
        if ($response.Content.Headers.ContentEncoding.Count -ne 0 -or
            $null -eq $response.Content.Headers.ContentLength -or
            $response.Content.Headers.ContentLength -lt 0) {
            Throw-DownloadError 'DOWNLOAD_FAILED' 'The artifact response length could not be verified.'
        }

        [long] $expectedLength = $response.Content.Headers.ContentLength
        $source = $response.Content.ReadAsStream()
        $destination = [IO.FileStream]::new(
            $temporary,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None,
            65536,
            [IO.FileOptions]::SequentialScan)
        try {
            $buffer = [byte[]]::new(65536)
            [long] $written = 0
            while (($count = $source.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if ($written + $count -gt $expectedLength) {
                    Throw-DownloadError 'DOWNLOAD_FAILED' 'The artifact response exceeded its declared length.'
                }
                $destination.Write($buffer, 0, $count)
                $written += $count
            }
            $destination.Flush($true)
        }
        finally {
            $destination.Dispose()
            $source.Dispose()
        }

        if ($written -ne $expectedLength) {
            Throw-DownloadError 'DOWNLOAD_FAILED' 'The artifact response was incomplete.'
        }

        if (Test-Path -LiteralPath $target) {
            $item = Get-Item -LiteralPath $target -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or -not $Overwrite) {
                Throw-DownloadError 'TARGET_EXISTS' 'The output file changed during download.'
            }
        }

        [IO.File]::Move($temporary, $target, [bool] $Overwrite)
        $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
        [ordered] @{
            state = 'completed'
            path = $target
            bytesWritten = $written
            contentType = [string] $response.Content.Headers.ContentType
            sha256 = $hash
        } | ConvertTo-Json -Compress
    }
    finally {
        $response.Dispose()
    }
}
finally {
    $client.Dispose()
    $handler.Dispose()
    if (Test-Path -LiteralPath $temporary) {
        Remove-Item -LiteralPath $temporary -Force
    }
}

# SIG # Begin signature block
# MIInRgYJKoZIhvcNAQcCoIInNzCCJzMCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBoJ/pmNWTlOCwB
# 6ayxQP+KwpDPlo3qeHncX0glAygErKCCDLowggX1MIID3aADAgECAhMzAAACHU0Z
# yE7XD1dIAAAAAAIdMA0GCSqGSIb3DQEBCwUAMFcxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBD
# b2RlIFNpZ25pbmcgUENBIDIwMjQwHhcNMjYwNDE2MTg1OTQzWhcNMjcwNDE1MTg1
# OTQzWjB0MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYD
# VQQDExVNaWNyb3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQDQvewXxx9gZZFC6Ys1WBay8BJ8kGA4JQnH5CMafqOASlTpK9H8
# o5ZXTXt0caVQTNMUPt445wXYD+dFtaKWTwDn1I52oUSrC9vJin1Gsqt+zyKJL5Dg
# 3eQXbQNR61DmMy20GLTIO3SFed9Rfi/ophgCLGFLDR3r0KvHjwMb/jYWS0celV/4
# Lz27LfAekm8v9E5IXaeiXbAUYZKK090n4CVl3JBtbN+9DtI9SNu/yjvozW52/u7R
# X/Ttpa/KDlpuokZ+Zcbvmtd9ur9gFLvZzh41o9MsE/clQtdaFWGvuo6Jua/ntpgk
# ey3E5/vBFe+MJPG6phdnuo6r57ZudCudiI1bAgMBAAGjggGbMIIBlzAOBgNVHQ8B
# Af8EBAMCB4AwHwYDVR0lBBgwFgYKKwYBBAGCN0wIAQYIKwYBBQUHAwMwHQYDVR0O
# BBYEFH6QuMwqcPG0hQlQ6c5jCtTTLrVeMEUGA1UdEQQ+MDykOjA4MR4wHAYDVQQL
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xFjAUBgNVBAUTDTIzMDAxMis1MDc1NTkw
# HwYDVR0jBBgwFoAUf1k/VCHarU/vBeXmo9ctBpQSCDEwYAYDVR0fBFkwVzBVoFOg
# UYZPaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0
# JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNybDBtBggrBgEFBQcBAQRh
# MF8wXQYIKwYBBQUHMAKGUWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMv
# Y2VydHMvTWljcm9zb2Z0JTIwQ29kZSUyMFNpZ25pbmclMjBQQ0ElMjAyMDI0LmNy
# dDAMBgNVHRMBAf8EAjAAMA0GCSqGSIb3DQEBCwUAA4ICAQBKTbYOjzwTG/DXGaz9
# s6+fQeaTtDcFmMY+5UyVFCyj7Pv+5i37qfX8lSL/tBIfYQfWsMuBQlfZurJD6r4H
# VJ2CeH+1fgiq8dcHdVKoZ3Sa2qXoX3cq9iS8cVb06B7+5/XJ7I0OxHH9fDsvJ3T3
# w5V/ZtAIFmLrl+P0CtG+92uzRsn0nTbdFjOkLMLWPLAU3THohKRlSEMgFJpPkm5n
# 5UAZ35xX6FWCrDLsSKb555bTifwa8mJBwdlof0bmfYidH+dxZ1FdDxvLnNl9zeKs
# A4kejaaIqqIPguhwAti5Ql7BlTNoJNwxCvBmqW2MQLnCkYN/VVUsR3V2x/rcTNzo
# Bf/Z/SpROvdaA2ZOOd1uioXJt3tdLQ7vHpqpib0KfWr/FWXW10q38VxfCnRQBqzb
# SuztR7nEMuzX7Ck+B/XaPDXd1qh72+QYyB0Z2VzWmO9zsnb9Uq/dwu8LGeQqnyu6
# 7SDGACvnXii2fb9+US492VTnXSnFKyqwgzUyFMtZK1/sHYTv6bG4TtQUygQxTN+Z
# V+aJIlKO2MqZ7bKrAnOzS9m6NgoTdWOq11bTOZwKlIEV/EhV9SWkDmdpR/hPPT2v
# 6TEj4F8PT/zHjRezIU5c/DGlt/VhY/pK0XkJtEyMmmS1BMtjU/rqBZVMIm3dnxQs
# /TBByr+Cf8Z1r7aifQVQ+WSqzjCCBr0wggSloAMCAQICEzMAAAA5O7Y3Gb8GHWcA
# AAAAADkwDQYJKoZIhvcNAQEMBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDExMB4XDTI0MDgwODIwNTQxOFoXDTM2MDMyMjIyMTMwNFow
# VzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEo
# MCYGA1UEAxMfTWljcm9zb2Z0IENvZGUgU2lnbmluZyBQQ0EgMjAyNDCCAiIwDQYJ
# KoZIhvcNAQEBBQADggIPADCCAgoCggIBANgBnB7jOMeqlRYHNa265v4IY9fH8TKh
# emHfPINe1gpLaV3dhg324WwH06LcHbpnsBukCDNitryo0dtS/EW6I/yEL/bLSY8h
# KpbfQuWusBPr9qazYcDxCW/qnjb5JsI1s8bNOg3bVATvQVL4tcf03aTycsz8QeCd
# M0l/yHRObJ9QqazM1r6VPEOJ7LL+uEEb73w6QCuhs89a1uv1zerOYMnsneRRwCbp
# yW11IcggU0cRKDDq1pjVJzIbIF6+oiXXbReOsgeI8zu1FyQfK0fVkaya8SmVHQ/t
# Of23mZ4W9k0Ri22QW9p3UgSC5OUDktKxxcCmGL6tXLfOGSWHIIV4YrTJTT6PNty5
# REojHJuZHArkF9VnHTERWoTjAzfI3kP+5b4alUdhgAZ7ttOu1bVnXfHaqPYl2rPs
# 20ji03LOVWsh/radgE17es5hL+t6lV0eVHrVhsssROWJuz2MXMCt7iw7lFPG9LXK
# Gjsmonn2gotGdHIuEg5JnJMJVmixd5LRlkmgYRZKzhxSCwyoGIq0PhaA7Y+VPct5
# pCHkijcIIDm0nlkK+0KyepolcqGm0T/GYQRMhHJlGOOmVQop36wUVUYklUy++vDW
# eEgEo4s7hxN6mIbf2MSIQ/iIfMZgJxC69oukMUXCrOC3SkE/xIkgpfl22MM1itkZ
# 35nNXkMolU1lAgMBAAGjggFOMIIBSjAOBgNVHQ8BAf8EBAMCAYYwEAYJKwYBBAGC
# NxUBBAMCAQAwHQYDVR0OBBYEFH9ZP1Qh2q1P7wXl5qPXLQaUEggxMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU
# ci06AjGQQ7kUBU7h6qfHMdEjiTQwWgYDVR0fBFMwUTBPoE2gS4ZJaHR0cDovL2Ny
# bC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNybDBeBggrBgEFBQcBAQRSMFAwTgYIKwYBBQUHMAKGQmh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0MjAx
# MV8yMDExXzAzXzIyLmNydDANBgkqhkiG9w0BAQwFAAOCAgEAFJQfOChP7onn6fLI
# MKrSlN1WYKwDFgAddymOUO3FrM8d7B/W/iQ6DxXsDn7D5W4wMwYeLystcEqfkjz4
# NURRgazyMu5yRzQh4LqjA4tStTcJh1opExo7nn5PuPBYnbu0+THSuVHTe0VTTPVh
# ily/piFrDo3axQ9P4C+Ol5yet+2gTfekICS5xS+cYfSIvgn0JksVBVMYVI5QFu/q
# hnLhsEFEUzG8fvv0hjgkO+lkpV9ty6GkN4vdnd7ya6Q6aR9y34aiM1qmxaxBi6OU
# nyNl6fkuun/diTFnYDLTppOkr/mg5WSfCiDVMNCxtj4wPKC5OmHm1DQIt/MNokbb
# H3UGsFP1QbzsLocuSqLCvH09Io3fDPTmscR9Y75G4qX7RTX8AdBPo0I6OEojf39z
# uFZt0qOHm65YWQE69cZM2ueE1MB05dNNgHK9gTE7zKvK/fg8B2qjW88MT/WF5V5u
# vZGtqa9FSL2RazArA+rDPuf6JGYz4HpgMZHB4S6szWSKYBv0VisCzfxgeU+dquXW
# 9bd0auYlOB58DPcOYKdc3Se94g+xL4pcEhbB54JOgAkwYTu/9dLeH2pDqeJZAABV
# DWRQCaXfO5LgyKwKCLYXpigrZYCjUSBcr+Ve8PFWMhVTQl0v4q8J/AUmQN5W4n10
# 1cY2L4A7GTQG1h32HHAvfQESWP0xghniMIIZ3gIBATBuMFcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jv
# c29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMjQCEzMAAAIdTRnITtcPV0gAAAAAAh0w
# DQYJYIZIAWUDBAIBBQCgga4wGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwHAYK
# KwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZIhvcNAQkEMSIEIBxePxGr
# tBiC9x4pDBir6LHcc4JLoLv4ULzqc30JK67dMEIGCisGAQQBgjcCAQwxNDAyoBSA
# EgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20w
# DQYJKoZIhvcNAQEBBQAEggEAkM6dd3LAELT5x80eQEZiqz5EHVxQF+N10ihvcBH7
# dWWcRYfS6oKKeyrDZGx5mtcUFgd41cf4z45CxJJE6PT/UUZa3vBcMQjrywHv2xVk
# 6ntmpl8JxWnd9a/thtoOBgedhordHXYIyWH7S8ahE/eW4Xo0Iurk56zRpIMR283y
# HaU1vl11+14UY0EHLnM3qGHC10+Cb/IpPDnTDUbTrQAJIwiUJua6Xb87QJY4VMHV
# j051gabRifbIGAXqQ5peVuSB9t4JTVQJViqeF/MyOnWzH/tFsBGLhYRdQF62kNH5
# aPZcEhVs7QQMFlj4cILwtCxFGjm6oY6VWwdW+dFR8OORh6GCF5QwgheQBgorBgEE
# AYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJYIZIAWUD
# BAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYBBAGEWQoD
# ATAxMA0GCWCGSAFlAwQCAQUABCA8VPfh3bPjvmIJAfM1ZvLnS9K2qWL8Y+/KgIT2
# 7PwtpgIGauHwHwnEGBMyMDI2MTEwODEwMTY1OC41MDFaMASAAgH0oIHRpIHOMIHL
# MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVk
# bW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxN
# aWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRT
# UyBFU046OTIwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAiNP2WAkU8/+KwABAAAC
# IzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDAe
# Fw0yNjAyMTkxOTM5NTdaFw0yNzA1MTcxOTM5NTdaMIHLMQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmlj
# YSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTIwMC0wNUUw
# LUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2UwggIi
# MA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCK6Q2nk5WUdKzSCSafp+UjUARs
# WxHKS63rJhFC/zSabFumTBuaJ0QNrmqevub5Db7fSj5qtwwKnjIO92+HXF67192f
# ujL7DFot5WEj/AtEZ/XrzFHimKlN1h6gEQwP5I67wizaPW5ZzSBNpaLBg5oHvASP
# OZtwdNUoZ+DQKF3hJl1KZuoIlVK+qi7cLjgak6s5oOZcRCMrKnuC3aoVa6wRDbYv
# KUuj7rkFx9KO0PsHJ/k+LnZMggRheh4AVdawyh+oOzKPjlQGUNfSeWUgym2U9CLa
# 8tt0mQX4DxDz6+ram50gj1oAfyQ6TQ7r96PADFOKBgaU7+cpHnaZG89dTegQ6ydB
# RGIycOw1dRX2eKDRRzziK3cn0WaIm/7OeGsyQKjIzEQuUTDv0Jj/9zQ7truLOOpJ
# D98BJVOK7je84Sz2hb3HvUST7j1j2N8peD6olkpFHR/1Z8Jz4F+mkrUF7MmPAirY
# HRzunbIg3HrDMNwFYN7yBkDA4/VMo9CY0y9oGUoq2yjbCwTibz9VYl93nB3QQiTC
# T9nW3M+TOWB+PMrZpExq1BSHmKPzIqehKqrUDoM33PK+dEKwpYLET6uXq4HuQRMX
# WT//sPubUnQAaaUMfQhAZSy23HtxwtN3eK9+T4wCav2wQFt57eUOwUW5/DCzMF9t
# ua5He1hNvgcAXaiG1wIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFNbAh89v29nPY9bw
# Qb1QYCzxVgeXMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMF8GA1Ud
# HwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3Js
# L01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNybDBsBggr
# BgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9zb2Z0LmNv
# bS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIw
# MTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgw
# DgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCHQwe7z5tp4NZwAf1c
# B+4c9J4svw3P6WqGBMxtqznS6DdzUzStXHCaPZhM41g1iKHNnmcnLjwLujOEaNjh
# SnUDiAZqQjW5ZapOBxgc7Egghh9k+r78qWAe3rJ4QohBbhSGdZtKivTRaeRqmnhy
# 8+ThrKhzCeEwaarXJimZwSpdQQUDbheWHeyAxASqultd5KO0m/UFvO03tfepqGXA
# 4tCg/WGECwKqOjJzpRAfPIB6y1HyVrk+vmL5rpEbTwwLOtX7WxFGG8+cYLk9HjaD
# kxraA/HYlKQRx1sdza+w/gulLwgOnByRJKF2rr8M7FNIlwoi6ywFpaNc8A7HewaG
# jgw/tfcE260I1XekGluANI9HnONOYWlI7BKBQbWE2teo6vsQ1Vg8B8rTZSePVdmX
# L1PPqqs3KVdFKM5kYocPCDM+6VL32IV96sESf2T7DjxanpCg2D2UYj4Z1i7cy8U1
# LLDGg55KWs4af2RRBjH2MulHgAmW5obKxiZCDQjRaroJ2XElXUhigE9BzvhCFbT/
# HDY2vpVpl5HnSpcCSxmL5i5lIT/xbAQMI7Luh75Xrm+IslfFWOGOGMlCp+24qEJE
# glXEP7xwsolNdBNndXihhyIefVGlI1DR7xGELiJrk8ifVWYo9XEbEXv/lbvp6F2R
# 2UsnweWckvq0y1HWnLHDqH6dPjCCB3EwggVZoAMCAQICEzMAAAAVxedrngKbSZkA
# AAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRpZmljYXRl
# IEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4MzIyNVow
# fDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1Jl
# ZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMd
# TWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qlsTnXIyjVX
# 9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLAEBjoYH1q
# UoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrEqv1yaa8d
# q6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyFVk3v3byN
# pOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1oO5pGve2k
# rnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg3viSkR4d
# Pf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2TPYrbqgS
# Uei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07BMzlMjgK8
# QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJNmSLW6Cm
# gyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6r1AFemzF
# ER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+auIurQID
# AQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3FQIEFgQU
# KqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl0mWnG1M1
# GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0
# bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMA
# QTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBTV9lbL
# j+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8vY3JsLm1p
# Y3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRfMjAxMC0w
# Ni0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEwLTA2LTIz
# LmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL/Klv6lwU
# tj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu6WZnOlNN
# 3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5tggz1bSNU
# 5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfgQJY4rPf5
# KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8sCXgU6ZGy
# qVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCrdTDFNLB6
# 2FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZc9d/HltE
# AY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2tVdUCbFp
# AUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8CwYKiexcd
# FYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9JZTmdHRb
# atGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDBcQZqELQd
# VTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2Eg
# T3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjkyMDAtMDVFMC1E
# OTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEw
# BwYFKw4DAhoDFQA4RWFs+kTiZnoZiAj1BtYj8zCNaqCBgzCBgKR+MHwxCzAJBgNV
# BAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29m
# dCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA7ppEijAiGA8y
# MDI2MTEwODAwNDQ1OFoYDzIwMjYxMTA5MDA0NDU4WjB0MDoGCisGAQQBhFkKBAEx
# LDAqMAoCBQDumkSKAgEAMAcCAQACAjSJMAcCAQACAhMBMAoCBQDum5YKAgEAMDYG
# CisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEA
# AgMBhqAwDQYJKoZIhvcNAQELBQADggEBACoxTtwLRMtgDCIIefQfj2WAduPF6hz2
# YWCdt+TWDNXgKl4KxW/uE89kC4Y0pfKd2ny7IUq1nDIC9ZKhfU7/J5/xjYE6zbWB
# bM2pzTIFl+VC/N0fcYXYjhHCOzCVO0izYIo0CCp3lXXYjS885jF6rI17MGwJrdmh
# 90yt91sgHkL2c0PbgGLaEsT62DLplFKBMzpS50+dIA0YUqUxvS6saMvGmin9mhX4
# +Bt3DRlpEVbV6K697ukuGLaul7TzDJqqKYHMaPShNmmW8on0+ZxMyb48DSIueDUI
# 2ZnJFd5bcw/JskFNdJWViHZEOeUTmjDu30ghoHp7TVBRuYtj3sRu/oIxggQNMIIE
# CQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAiNP2WAk
# U8/+KwABAAACIzANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqG
# SIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBYqZPg3YHxcOQo1UdD9WZ9jYEZgVoC
# e1g32VJafFTSmzCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIJbwMywRbvcG
# iynjnwjAqcaD47yYvebKZRAvtEAR5u6zMIGYMIGApH4wfDELMAkGA1UEBhMCVVMx
# EzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoT
# FU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUt
# U3RhbXAgUENBIDIwMTACEzMAAAIjT9lgJFPP/isAAQAAAiMwIgQgWNKs+LpuR1yc
# q8bdR1RK6Gs0OK4xxWykzFZsqeW4TmkwDQYJKoZIhvcNAQELBQAEggIAdO/tf3mQ
# 5i2vM1Uq2Kq0e8SLP0cNRwKy047msoT9TicYCYBuQGjpiNsYexqNcoidIeFDAiov
# vveZta75R6Wdx5Y1XzoeA/scSWP+PhMxKg/HsPjJceuJAMBN+dt8tovRzYHuWI5w
# Th98r9R2o6z+OvK+SdALoB8Q+zR7SLTPyRx4UdLN70ZTJeoAWu+3mTqTVQoSTIAU
# 9+hiX8NNctBxYZDDfds45pbyI3+e1ej/8WTidzvxk4lSyC2dHmVX9kio+C3k6VEp
# 8izHr5FrgDkW9P4O7czl694QS517/ENSseQNhWqM5shYCh1iLZ/gwNoz3U8f5v7f
# CACyEj1Q8BcbjOOMVcfb1C9ff/nahldkwm3iAKDKJkHPP3xF4Mmnydmiqtp7r1TL
# 0D9rCf2FZ5xHCU3p5wuQ3f7vMSDcCf8ZFTM4bpMLQd7nRjkEraEEuAUhn7TiIGua
# gbSLaS2wBX6UMT4Kx4r/eCs/CPHH3SwXVStD2q34oeRcvkNff2Tp88EkFYRCqXgN
# Tq/9ITnhzajL+ocs3cNtLyVhWdDOsEp3i+lvOFFWm7Ep/KiGOxP2Yl2P9XftVUnw
# dLHLOFpMq5C9MBqoT6QZkvLVN2kWTSN2q2EYOMZRu0KTfGtBN5WN17KFPM34u+Rl
# WPl2JrBO1oGzF+/5oi0nZq/lQi7SbFpHcJo=
# SIG # End signature block
