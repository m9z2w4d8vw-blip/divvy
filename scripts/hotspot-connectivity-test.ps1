# Read-only connectivity check on a jailbroken iPhone.
# Run AFTER enabling Personal Hotspot and attempting the default-route swap.
# This script does not change routing, NAT, interfaces, or system files.

$ErrorActionPreference = 'Stop'
$target = 'mobile@10.5.5.187'

Write-Host 'divvy: iPhone connectivity test' -ForegroundColor Cyan
Write-Host 'First enable Personal Hotspot and run the route-swap experiment.'
Read-Host 'When ready, press Enter to test en0 and the selected default route' | Out-Null

$remote = @'
set +e
echo "=== Current selected default route ==="
/var/jb/sbin/route -n get default 2>&1
echo ""
echo "=== Finding curl ==="
CURL=""
for candidate in /var/jb/usr/bin/curl /var/jb/bin/curl; do
    if [ -x "$candidate" ]; then
        CURL="$candidate"
        echo "curl: $CURL"
        break
    fi
done
if [ -z "$CURL" ]; then
    echo "ERROR: curl was not found at either requested location."
    exit 127
fi
echo ""
echo "=== Test 1: force outgoing connection over en0 ==="
"$CURL" -s --max-time 10 --interface en0 https://1.1.1.1 -o /dev/null -w "%{http_code} via en0"
curl_rc=$?
printf '\nCurl exit status: %s\n' "$curl_rc"
echo ""
echo "=== Test 2: use the selected default route ==="
"$CURL" -s --max-time 10 https://1.1.1.1 -o /dev/null -w "%{http_code} default route"
curl_rc=$?
printf '\nCurl exit status: %s\n' "$curl_rc"
echo ""
echo "Note: these tests measure the phone's own connectivity, not hotspot-client NAT."
'@

# Without an explicit remote command, SSH launches the mobile user's
# default shell (zsh on this device). This avoids the missing /bin/sh.
# Transmit LF-only text so shell input works from Windows PowerShell.
($remote -replace "`r`n", "`n") | & ssh.exe -T -o ConnectTimeout=10 $target
if ($LASTEXITCODE -ne 0) {
    throw "SSH or the remote test exited with code $LASTEXITCODE."
}
