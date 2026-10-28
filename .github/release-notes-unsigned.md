
### Opening an unsigned build

This build is ad-hoc signed and not notarized, because the project has no Apple Developer ID yet.
The first time you open it, macOS will say it can't verify the developer:

1. Click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to BotPeek.
3. Confirm with **Open**.

See [Apple's guide](https://support.apple.com/102445). Please don't disable Gatekeeper. After
updating, macOS treats the app as new: turn BotPeek's Accessibility permission off and on again.
