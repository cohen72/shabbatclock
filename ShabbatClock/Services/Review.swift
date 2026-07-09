import DeliciousKit

/// Shared instance of DeliciousKit's gated review prompter, configured for
/// pure interval-based prompting (no positive-event requirement). ShabbatClock's
/// actual "it worked" moment — an alarm auto-stopping itself — happens while
/// the user isn't looking at the phone at all, often during Shabbat when it
/// sits untouched for 25 hours, so gating on that event would make the
/// prompt nearly unreachable in practice. Session count + spacing is the
/// right fit here instead.
let reviewPrompter = ReviewPrompter(config: ReviewPromptConfig(requiresPositiveEvent: false))
