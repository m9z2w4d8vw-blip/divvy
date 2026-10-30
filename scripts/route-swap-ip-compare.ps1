# divvy: hotspot route-swap + public IPv4 comparison (iOS 17 rootless).
# Run while Personal Hotspot is ON and a second device is connected.
# WARNING: modifies only the phone's live default route; SSH or Internet may drop.
$ErrorActionPreference = 'Stop'
$target = 'mobile@10.5.5.187'

Write-Host 'DIVVY: route swap + phone-side public-IP comparison' -ForegroundColor Cyan
Write-Host 'Before starting: connect iPhone to Wi-Fi, enable Personal Hotspot, and connect the second device.'
Write-Warning 'The route change is temporary and may interrupt network/SSH connectivity.'
Read-Host 'Press Enter to attempt route swap and run both IP checks' | Out-Null

$remote = @'
set -u
ROUTE=/var/jb/sbin/route
IFCONFIG=/var/jb/sbin/ifconfig
NETSTAT=/var/jb/usr/sbin/netstat
CURL=""
for candidate in /var/jb/usr/bin/curl /var/jb/bin/curl; do
    if [ -x "$candidate" ]; then
        CURL="$candidate"
        break
    fi
done
if [ -z "$CURL" ]; then
    echo 'ABORT: curl unavailable at the two expected rootless paths.'
    exit 11
fi

echo '=== Before swap: selected default route ==='
"$ROUTE" -n get default || exit 12
if ! "$IFCONFIG" en0 2>&1 | grep -q 'status: active'; then
    echo 'ABORT: en0 is not active; no routes changed.'
    exit 13
fi
if ! "$IFCONFIG" ap1 2>&1 | grep -q 'status: active'; then
    echo 'ABORT: ap1 is not active; enable hotspot first.'
    exit 14
fi
if ! "$IFCONFIG" bridge100 2>&1 | grep -q 'inet 172.20.10.1'; then
    echo 'ABORT: hotspot bridge100 gateway missing.'
    exit 15
fi
if "$ROUTE" -n get default | grep -Eq 'interface:[[:space:]]+en0'; then
    echo 'Selected default is already en0; no route change needed.'
else
    if ! "$ROUTE" -n get default | grep -Eq 'interface:[[:space:]]+pdp_ip0'; then
        echo 'ABORT: selected default is neither en0 nor pdp_ip0.'
        exit 16
    fi
    if ! "$NETSTAT" -rn -f inet | grep -Eq '^default[[:space:]]+10[.]5[.]0[.]1[[:space:]].*[[:space:]]en0([[:space:]]|$)'; then
        echo 'ABORT: expected scoped Wi-Fi default (10.5.0.1 / en0) not found.'
        exit 17
    fi
    echo '=== Obtaining sudo permission ==='
    sudo -v || exit 18
    echo '=== Removing global cellular default ==='
    sudo "$ROUTE" delete default || exit 19
    echo '=== Installing global Wi-Fi default ==='
    if ! sudo "$ROUTE" add default 10.5.0.1; then
        echo 'ERROR: unable to install Wi-Fi default; trying to restore cellular default.'
        sudo "$ROUTE" add default 192.0.0.1 || true
        exit 20
    fi
fi

echo '=== After swap: selected default route ==='
"$ROUTE" -n get default || exit 21
if ! "$ROUTE" -n get default | grep -Eq 'interface:[[:space:]]+en0'; then
    echo 'STOP: en0 is not the selected default. Results would be misleading.'
    exit 22
fi

echo '=== Fetching public IPv4 addresses (10 second timeout each) ==='
en0_ip=$("$CURL" -4 -fsS --max-time 10 --interface en0 https://api.ipify.org)
en0_rc=$?
default_ip=$("$CURL" -4 -fsS --max-time 10 https://api.ipify.org)
default_rc=$?

printf '\n%-20s | %s\n' 'Connection' 'Public IPv4'
printf '%-20s-+-%s\n' '--------------------' '--------------------'
if [ "$en0_rc" -eq 0 ] && [ -n "$en0_ip" ]; then
    printf '%-20s | %s\n' 'Forced via en0' "$en0_ip"
else
    printf '%-20s | FAILED (curl exit %s)\n' 'Forced via en0' "$en0_rc"
fi
if [ "$default_rc" -eq 0 ] && [ -n "$default_ip" ]; then
    printf '%-20s | %s\n' 'Default route' "$default_ip"
else
    printf '%-20s | FAILED (curl exit %s)\n' 'Default route' "$default_rc"
fi

echo ''
if [ "$en0_rc" -ne 0 ] || [ "$default_rc" -ne 0 ] || [ -z "$en0_ip" ] || [ -z "$default_ip" ]; then
    echo 'CONCLUSION: One or both phone-side connections failed; no upstream equivalence established.'
elif [ "$en0_ip" = "$default_ip" ]; then
    echo 'CONCLUSION: The phone shows the SAME public IPv4 for forced en0 and its default route.'
    echo 'This is consistent with both phone-side requests exiting through the same public gateway.'
    echo 'It does NOT show which upstream a hotspot client uses. Compare the second device separately.'
else
    echo 'CONCLUSION: The phone shows DIFFERENT public IPv4 addresses.'
    echo 'Interface binding and default traffic are taking different apparent egress paths.'
    echo 'Compare the hotspot client separately; do not assume its NAT matches either phone-side test.'
fi

echo ''
echo '=== Final route check (iOS may reinstate cellular automatically) ==='
"$ROUTE" -n get default
'@

Write-Host 'Connecting via SSH; the phone may ask for SSH and sudo passwords...' -ForegroundColor Cyan
# -tt provides an interactive terminal for sudo, and uses the phone's default zsh.
& ssh.exe -tt -o ConnectTimeout=10 $target $remote
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    Write-Warning "Remote test returned $exitCode. It may have been interrupted by a route change."
    exit $exitCode
}
Write-Host 'Phone-side test complete. Compare the connected hotspot device separately.' -ForegroundColor Green
