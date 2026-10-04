#!/usr/bin/env python3
"""Check reminder eligibility using the production policy without requesting OS permission."""
import pathlib,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='nano-notification-policy-') as d:
 d=pathlib.Path(d);source=d/'main.swift'
 source.write_text((root/'Nanobeasts/Services/NanoNotifications.swift').read_text().split('/// The app preference')[0]+'\n'+(root/'Scripts/WorkoutRegression/NotificationPolicyChecks.swift').read_text())
 subprocess.run(['xcrun','swiftc','-module-cache-path',str(d/'ModuleCache'),str(source),'-o',str(d/'checks')],check=True)
 subprocess.run([str(d/'checks')],check=True)
