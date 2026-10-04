#!/usr/bin/env python3
"""Exercise the shared iPhone/Watch subscription-expiry contract."""
from pathlib import Path
import subprocess, tempfile
root=Path(__file__).resolve().parents[1]
checks=r'''
let now = Date(timeIntervalSince1970: 1_800_000_000)
var checked = 0
for premium in [true, false] {
    for complete in [true, false] {
        for expiry: Date? in [nil, now.addingTimeInterval(-1), now, now.addingTimeInterval(1)] {
            let access = NanoSubscriptionAccess(premium: premium, onboardingCompleted: complete,
                expiresAt: expiry, updatedAt: now)
            let expected = premium && complete && (expiry.map { $0 > now } ?? true)
            precondition(access.allowsAccess(at: now) == expected)
            let restored = try JSONDecoder().decode(NanoSubscriptionAccess.self,
                from: JSONEncoder().encode(access))
            precondition(restored == access && restored.allowsAccess(at: now) == expected)
            checked += 1
        }
    }
}
let later = now.addingTimeInterval(3600)
precondition(NanoSubscriptionAccess.accessExpiration(paidThrough: nil, graceThrough: later) == nil)
precondition(NanoSubscriptionAccess.accessExpiration(paidThrough: now, graceThrough: nil) == now)
precondition(NanoSubscriptionAccess.accessExpiration(paidThrough: now, graceThrough: later) == later)
precondition(NanoSubscriptionAccess.accessExpiration(paidThrough: later, graceThrough: now) == later)
let graceAccess = NanoSubscriptionAccess(premium: true, onboardingCompleted: true,
    expiresAt: NanoSubscriptionAccess.accessExpiration(paidThrough: now, graceThrough: later), updatedAt: now)
precondition(graceAccess.allowsAccess(at: now))
precondition(!graceAccess.allowsAccess(at: later))
print("PASS: \(checked) shared access states and 6 grace-period checks, including exact expiration, non-expiring entitlements, incomplete onboarding, and paired-device round trips.")
'''
with tempfile.TemporaryDirectory(prefix='nano-access-checks-') as temp:
    temp=Path(temp)
    (temp/'main.swift').write_text((root/'NanobeastsShared/NanoSubscriptionAccess.swift').read_text()+'\n'+checks)
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(temp/'ModuleCache'),str(temp/'main.swift'),'-o',str(temp/'checks')],check=True)
    subprocess.run([str(temp/'checks')],check=True)
