Twitter Thread: Building Rive Graphics for FlipPhone

[THREAD START]

1/ I've been using @rive_app to create dynamic, data-driven animations for @FlipPhoneApp, and I wanted to share how I built the milestone badge system. Here's my approach:

----------

2/ The challenge:

I needed milestone badges that:
- Change shape based on session duration
- Match the user's selected category color

Rive's state machines + data binding made this possible.

----------

3/ Setup:

Each milestone has a "badgeShapeValue" that gets passed from Swift into Rive.

I created a Formula converter that maps ranges (e.g., 20-29min → badge-shape-5) to drive the visual state.

----------

4/ Data Binding: I'm binding three key inputs:

- themeColor: Matches the session category color
- arrowColor: Also matches category (for accent elements)
- badgeShapeValue: Numeric input that determines which badge shape to show

----------

5/ State Machine Magic:

The state machine switches between different badge shapes based on the badgeShapeValue.

Each state represents a different milestone tier:
- 10-15min
- 20-30min
- 40-50min
- 1-3hr
- etc.

----------

6/ The converter system:

I use Range Map converters to translate the numeric input into discrete states.

For example:
- 20-29.99 minutes → badge-shape-5 (20m milestone)
- 30-39.99 minutes → badge-shape-5 (30m milestone)
- 40-49.99 minutes → badge-shape-6 (40m milestone)

----------

7/ Color Dynamic:

Colors are bound at runtime from SwiftUI.

When a user selects a category (Work, Personal, Fitness, etc.), the entire animation updates instantly to match their theme.

No pre-rendering needed—it's all dynamic.

----------

8/ Multiple Timelines:

Each milestone tier has its own timeline with specific animations.

The state machine triggers the correct timeline based on the badgeShapeValue, ensuring smooth transitions between states.

----------

9/ Faux 3D Effect:

To make the badges feel more dimensional, I used a combination of clipping masks and layered elements.

The technique involves:
- Clipping masks to create depth contours
- Layered gradients that simulate lighting
- Overlapping shapes that create shadow/highlight effects

----------

10/ The 3D illusion works by:

Strategically placing clipped layers on top of each other, with slight offsets and gradient fills that suggest depth.

No actual 3D transforms needed—just clever 2D compositing tricks that create the illusion of depth.

----------

11/ Result:

Users get personalized, dynamic milestone badges that reflect:
- Their achievement level
- Their chosen category color

All rendered in real-time, no pre-rendered assets needed.

----------

12/ The best part?

Rive exports to multiple platforms.

I'm using the iOS runtime, but this same animation file could work on:
- Web
- Android
- Flutter

With minimal changes.

----------

13/ Key takeaway:

Rive's data binding + state machines let me create complex, personalized animations that would be impractical with traditional keyframe animation tools.

Highly recommend checking it out for dynamic UI animations.

----------

[END THREAD]

Tips for adding graphics:
- Screenshot 1: Rive editor showing the state machine setup
- Screenshot 2: The Formula converter configuration
- Screenshot 3: Data binding panel showing themeColor, arrowColor, badgeShapeValue
- Screenshot 4: Badge layers breakdown showing clipping masks and layering structure
- Screenshot 5: Final result showing different badge shapes in the app
- Screenshot 6: Side-by-side comparison of same badge with different category colors
- Video/GIF: Animation transitioning between different badge shapes
- Close-up: Before/after showing flat vs 3D effect

