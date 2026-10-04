import Foundation

var checks = 0
func check(_ result: Bool, _ message: String) {
    precondition(result, message)
    checks += 1
}
check(!NanoReminderPolicy.shouldRemind(enabled: false, authorized: true, remaining: 1, target: 100), "An app-level opt-out suppresses eligible reminders")
check(!NanoReminderPolicy.shouldRemind(enabled: true, authorized: false, remaining: 1, target: 100), "iOS denial suppresses reminders")
check(NanoReminderPolicy.shouldRemind(enabled: true, authorized: true, remaining: 20, target: 100), "80 percent progress qualifies")
check(!NanoReminderPolicy.shouldRemind(enabled: true, authorized: true, remaining: 21, target: 100), "Earlier progress does not nag the user")
check(!NanoReminderPolicy.shouldRemind(enabled: true, authorized: true, remaining: 0, target: 100), "An already completed evolution is not described as upcoming")
check(!NanoReminderPolicy.shouldRemind(enabled: true, authorized: true, remaining: -1, target: 100), "Over-goal values do not create stale reminders")
check(!NanoReminderPolicy.shouldRemind(enabled: true, authorized: true, remaining: 1, target: 0), "A missing target does not create a reminder")
check(!NanoReminderPolicy.shouldRemind(enabled: true, authorized: true, remaining: 1, target: -100), "Invalid targets are rejected")
print("Passed \(checks) notification policy checks")
