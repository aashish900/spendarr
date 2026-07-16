# Privacy Policy — spendarr

**Effective date:** 2026-07-16
**App:** spendarr (Android, package `com.aashish.spendarr`)
**Developer:** Aashish Agarwal

## Summary

spendarr does not collect, transmit, sell, or share any of your data. Everything you enter — transactions, categories, recurring rules, and app preferences — is stored only in a local database on your device. There is no account, no sign-up, no analytics SDK, and no ad SDK in the app. Nothing you type into spendarr reaches the developer or any third party unless you personally choose to export and share it.

## What data the app stores, and where

| Data | Where it's stored | Leaves the device? |
|---|---|---|
| Transactions (amount, category, date/time, optional note) | Local SQLite database on your device | No, unless you use Export CSV |
| Categories and recurring-transaction rules | Local SQLite database on your device | No |
| Display name / monthly budget (if set) | Local app preferences on your device | No |
| CSV export file | Written to a temporary app cache folder, then handed to whichever app you pick from Android's share sheet (e.g. email, Drive, Files) | Only if and when you export and choose to share it |

The app requests no runtime permissions beyond what Android's share sheet needs to hand off a CSV file — spendarr does not request access to your contacts, location, camera, microphone, SMS, or call logs, and never has.

## Third parties

spendarr contains no third-party analytics, advertising, crash-reporting, or tracking libraries. The developer has no server that the app talks to, and receives no data from installs of this app.

## Android system backup

Android's built-in "Back up my data" feature (Auto Backup for Apps) is enabled at the OS level for this app, as it is by default for most Android apps. If you have this Android setting turned on, your device's operating system — not spendarr, and not the developer — may include spendarr's local data in your personal Google Account backup, the same way it would for your other apps' data. This is a standard Android platform feature that backs up to *your own* Google Account, not to the developer or any third party. You can disable this globally in your device's system settings if you'd prefer it not apply to any app.

## Data retention and deletion

Your data stays on your device for as long as the app is installed, or until you delete it yourself (there is currently no automatic time-based deletion). Uninstalling the app removes its local data from your device (subject to the Android system backup behavior described above, which is controlled by your device's OS settings, not the app).

## Children's privacy

spendarr is not directed at children and does not knowingly collect any data from anyone, including children, because it does not collect data from anyone at all.

## Changes to this policy

If spendarr's data practices change in a future release (for example, if an optional self-hosted sync feature is added), this policy will be updated first, and any new data transmission will be off by default and require you to explicitly configure it (e.g. entering your own server address).

## Contact

Questions about this policy or the app can be raised via GitHub Issues on this repository: https://github.com/aashish900/spendarr/issues
