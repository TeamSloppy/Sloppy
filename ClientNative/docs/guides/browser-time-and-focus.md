# Time & Focus

On macOS, select the timer icon at the bottom of the Browse sidebar or press **Cmd+2**. Time & Focus replaces the sidebar content and leaves the website visible alongside it. Press **Cmd+1** or select the globe to return to the tab list. On iPhone and iPad, open **Time & Focus** from the browser menu.

The screen shows today’s or this week’s active browsing time, a usage chart, time per domain, and recently visited pages with their latest visit date. Page links open in a new tab. Older browsing history is available from **History**.

## Pomodoro

Choose a focus duration (25 minutes by default) and a break duration (5 minutes by default). Add domains and enable **Pause during focus**, then choose **Start focus**. You can pause, resume or end the timer. A completed focus session starts its break automatically; the next focus session starts manually.

Timers and completed-session counts survive restarting Sloppy. A paused timer stays paused. A running timer uses its saved deadline, including time spent outside Sloppy. Reopening after both the focus and break have elapsed returns to the ready state. Timer settings can be changed between sessions.

## Daily limits

Set a daily limit for all browsing or for individual domains. Zero means off. Domain rules include subdomains and treat `www.example.com` as `example.com`; lookalike domains do not match. Limits reset at midnight in the device’s current calendar and time zone.

When a limit is reached, Sloppy replaces the page with a pause message and pauses media. Navigation to a blocked site is cancelled before loading, including links and reloads. Browser navigation and Time & Focus remain available so you can change limits or end focus. These are voluntary limits inside Sloppy, not operating-system restrictions on other apps or browsers.

## Counting and privacy

Only the selected website in the active Sloppy browser window counts. Other split panes and background tabs do not add time. Opening history, tab overview or the time screen pauses counting when they cover the browser. Background applications, suspended time and time spent in Work mode are excluded. Very short transitions can differ by up to one sampling interval (one second).

Time statistics and rules are saved locally and are not part of iCloud history sync. Statistics retain hourly domain totals for 35 days. Sloppy does not reconstruct time from older history, so recording starts after this feature is installed. **Clear time statistics** removes time totals while preserving history, limits and the timer. Clearing History separately removes the recently visited page information.
