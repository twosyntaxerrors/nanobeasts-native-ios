# iPhone delivery

When the user requests an app update, completion includes building and signing
the updated app, installing it on their connected physical iPhone, and verifying
that it launches. A simulator build alone does not fulfill the request.

Discover the connected device instead of assuming a simulator destination. Use
the existing app bundle identifier and install in place to preserve user data;
do not uninstall the app as part of routine updates. If device access, signing,
or installation is blocked, state the exact blocker and the action needed.

# Physical-device-first testing

The user tests updates on their physical iPhone and reports issues. Do not build,
boot, or test with Simulator for routine updates; it slows their computer down.
Use Simulator only when absolutely necessary to resolve a specific blocker.
Prefer a signed device build, in-place installation, and launch verification.

# Development subscription testing

For routine installs on this user's test iPhone, use the Debug configuration.
Debug uses the same App Store products/paywall as Release, and honors an
Apple-verified sandbox purchase after its accelerated test expiration. This
access is explicitly marked development-only and rejected by Release builds.
Use Release for distribution or when the user explicitly asks to test real
subscription expiry. Never move the sandbox testing allowance into Release.
