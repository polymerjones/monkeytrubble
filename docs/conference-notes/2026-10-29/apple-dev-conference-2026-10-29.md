# Apple Developer session: Boost your app's speed and efficiency (Oct 29, 2026)

- 10:39 AM · **Feature flags**
- 10:47 AM · **xctrace** (heard as "xetrace"): the command-line version of Instruments. `xcrun xctrace record --template "Time Profiler" --launch -- <app>` records a trace without opening Instruments; `xctrace export` pulls the data out as XML, so performance checks can run in scripts or CI.

## Recorded from the session audio

### 10:49 AM · Making traces a coding agent can analyze
- **Profile on real devices**, not the Simulator: its performance is different and misleading.
- **Signposts** mark periods of work you want to measure:
  - Create an `OSSignposter` with the **Points of Interest** category.
  - Call `beginInterval("name")` when the work starts.
  - Call `endInterval("name", state)` with the same name and the state `beginInterval` returned, so the pair matches.
  - The intervals appear in Instruments' **Points of Interest** track, for you and for an AI coding agent reading the trace.
- **State reporting framework** records what *mode* the app is in, not just timed tasks. Feature flags fit here:
  - Get a reporter for a feature with a reverse-DNS name (e.g. `com.wwg.slideshow`).
  - Report a transition with a descriptive label whenever the mode changes.
  - States are logged alongside signposts, so they show up in the trace.
- **Profile under a variety of conditions.**

### 10:51 AM · Capture lots of traces, then a live demo (hang hunting)
- **Don't stop at one trace.** More traces give you a better sample:
  - Do actions in different orders and with different sets of data.
  - Try different device conditions. **Network Link Conditioner** simulates a bad connection, so you find problems that hide when everything's fast.
- **Demo:** finding and fixing a hang in a Notes app with Instruments plus a coding agent.
  - **On-device hang detection:** Settings → Developer → Hang Detection. It shows a live alert at the top of the screen whenever the app freezes.
    - Threshold 500 ms, to catch even brief UI stalls.
  - **Start an Instruments capture first**, so any hang that happens is already in a trace.
  - **⌘I** in Xcode builds, installs and starts profiling the app on the device.

### 10:53 AM · Demo: catching the "save" hang
- **Re-create the problem on purpose:** the presenter remembered a hang when saving a note.
- **Time Profiler template:** already includes the **Hangs** instrument and the **Points of Interest** row, where their signposts show.
- **The steps:**
  - Press the red **Record** button. The app launches on the test iPad.
  - Open a note ("Dragon Curve"), make an edit, tap **Save**.
  - Hang Detection pops up instantly: a **~3 second hang**.
  - Press **Stop**, save the trace as `trace_save_hang`, and name the run **"baseline"**. That's the "before" measurement to compare the fix against.

### 10:55 AM · Demo: reading the trace to find the cause
- **Zoom in on the problem:** click the **"Severe hang"** bar (~3 s) in the Hangs row, then **Set Inspection Range and Zoom**. That cuts out everything else in the trace.
- **Points of Interest says when:** the hang lined up with their **"rendering preview"** signpost, where each note is turned into a PNG thumbnail for the notes list.
- **A hang means the main thread was blocked**, so next they check what code ran during it:
  - Open the hang's **Time Profiler** row and look at the **Call Tree** at the bottom of the window.
  - 95% of the hang time was in one thread's work.
  - **⌥-click** expands the full **call stack**, which shows `NotePreviewExporter.renderPNG` (making the thumbnail).
- **The suspect:** making the preview image. Next they hand the trace to a coding agent for a deeper dive.
- **Lesson for Señor Crabb:** the same pattern applies. Heavy work like making thumbnails or decoding big videos must never block the main thread, or the page freezes.

### 10:57 AM · Demo: handing the trace to a coding agent, and why hangs happen
- **The agent reads traces with xctrace**, the same way an engineer would.
- **Workflow in Xcode:**
  - Open Xcode's **coding assistant** and start a **New Conversation**.
  - **Drag the saved trace in from Finder.**
  - Ask it to "investigate the hangs and describe the solution". It uses the trace as context.
- **Why hangs happen:** non-UI work done on the main thread, or the main thread **waiting** on some other work to finish.
- **Common anti-patterns:**
  - **Priority inversion:** urgent work, like updating the screen, gets stuck waiting behind low-priority work. Avoid shared locks and set the right **QoS** level.
  - **Structured concurrency:** don't run heavy work on the **main actor**. Wrap long-running work in a **nonisolated async function** instead.
- **Señor Crabb tie-in:** you can do the same thing with me. Save a Safari Timelines recording, give it to me, and I'll read it and find the slow part.

### 10:59 AM · Demo: what the agent found, and checking the fix
- **What the agent did:**
  - Ran **`xctrace triage`** to spot the hang.
  - Analyzed the trace and found the **root cause**: a **priority inversion in the preview renderer**.
  - Suggested fixes. The presenter reviewed them ("sound reasonable") and told it to make the changes.
- **xctrace skills:** xctrace isn't just for hangs. It handles many kinds of performance problems, finding the "needle in the haystack" so you can decide on the fix.
- **Not Xcode-only:** the xctrace skills Xcode's agent uses **can be exported from the command line for any agent**, including Claude Code.
- **Always verify:** after the agent's fix, build and profile again with **⌘I** and record a new trace to confirm the hang is gone. That's the "after" to compare with the baseline.

### 11:01 AM · Demo: proving the fix
- **Next Recording** (top left) starts a new run **in the same trace file**, with the same settings, so the baseline run is one click away for comparing.
- Recorded again, edited a note, tapped Save: **no hang alert**.
- The timeline showed no hang during "rendering preview", and that step was **much faster**.
- Then they **committed the changes and opened a PR** for the team to review.
- **The big lesson:** agents make quick fixes easy, but **always verify** that the change fixed the problem *and* didn't break anything. Here the hang was gone and the app still worked.
- **The whole recipe:** Instruments + Points of Interest + an agent = quick to find and fix hangs.
- **Up next in the talk:** how performance data and agentic coding help as an app grows.

### 11:03 AM · Performance data from real use: MetricKit
- **The need:** as agents do more of your work, give them richer performance data with **context built in**, e.g. "hangs in this one screen" or "launch time when feature X is on". You also want it from different audiences: your team, beta testers, the public.
- **MetricKit** (an Apple framework) handles that:
  - A **daily report** of your app's performance numbers.
  - **Diagnostics** whenever something goes wrong: a hang, a crash, a memory problem.
  - Raw data you can turn into **your own dashboards and reports**, or feed to an agent so performance work becomes part of **every release**.
- **Works for every audience:** internal users, beta testers, App Store downloads.
- **Privacy:** once you send the data off the device, your own privacy and data-collection policies apply.
- **New in the "27" releases:** **state reporting works with MetricKit.** Instead of one total ("6.7 s of hangs yesterday across the whole app"), MetricKit breaks the numbers down **by state**. Feature flags come in here: you see hang time with a flag on vs. off.

### 11:05 AM · Agentic performance workflow, tests, and the wrap-up
- **MetricKit by state:** a separate hang time for each feature or mode in use, not one total.
- **MetricKit is the cornerstone of an agentic performance workflow** built on real users' data. Combine the data → find what hurts people most → the agent **proposes fixes as pull requests, release after release**.
- **Catch problems early with automated tests:**
  - Break code into small pieces and write **performance tests** with **XCTest**.
  - **`measure { }`** in XCTest times a block of code. Compare each run to the **baseline** to catch **regressions** (things getting slower).
  - Agents make writing tests easy: have yours give all new code **test coverage** so performance doesn't slip.
- **Where to go from here (the summary slide):**
  1. **Gather data from every source:** the **Xcode Organizer**, the **Xcode MCP Server**, **MetricKit** and your **tests**.
  2. **Put your agent to work** on the app's top performance issues.
  3. Use **Instruments** and the new **xctrace commands** so the agent can work through traces efficiently.
  4. Adopt **MetricKit + state reporting** for the richest insights.

### 11:07 AM · End of session
- The presenter closed on agents + performance data growing with your app. Next: a short break, then **live Q&A at 11:30 AM**.

## Session 2 (from about 11:30 AM): battery and power
_Recorded live; notes added every couple of minutes._

### 11:32 AM · Why power matters: heat vs. battery
- **Reasons to work on power:**
  - Reports show your app uses more battery than similar apps.
  - You want it to run well on the widest range of devices.
  - Users say it makes their device hot or drains the battery.
- **Two kinds of problems:**
  - **Thermals (heat):** a warm device feels wrong. If it gets too hot, the system **throttles** (slows the app down to cool off), and in extreme cases turns off non-essential features until it cools.
  - **Battery usage:** less time for people to use their device. They can see your app's share in **Settings → Battery** and may use it less if it's a hog.
- **Two sides of the same coin:** both come from not managing **power** well.
  - **Power** = the *rate* energy is used, how hard the device is working right now.
  - **Heat** comes from high power even for a short time, your app's **peak power draw**.
  - **Battery drain** comes from extra power over a long time, the **total energy** used.

### 11:34 AM · The two goals, and "what uses power? Everything"
- **Small extra power adds up** if it lasts a long time. Battery use is driven by your app's **average** and **floor** (idle) power.
- **Worst case:** high power for a long stretch, which causes both heat and battery drain.
- **The two goals:**
  1. **Reduce peak power**, which means less heat.
  2. **Reduce average power over time**, which means less battery drain.
- In practice this is **a balance between perfect quality and power**.
- **Nothing is free:** every capability (storage, audio, graphics) wakes up other system software, all running on hardware that draws power.
- **One line of code, many parts:** loading and showing one image from the internet uses the **radios** to download it, the CPU to **decode** it, the **GPU** (via Metal) and the **display**.
- **Even bigger:** a map (MapKit) also uses **location sensors** and heavy graphics.
- **Señor Crabb tie-in:** the slideshow decodes big photos and videos and the PixelFLEX wall draws through the GPU every frame. Showing smaller images and only redrawing the wall when something changes both cut power.

### 11:36 AM · The system bills your app, and think in subsystems
- **Your app pays for the system's work:** iOS tracks which app each piece of system work is for and **charges the power to that app**. The battery figure people see in Settings includes work the system did *on your behalf*.
- **Think in subsystems:**
  - **Hardware:** CPU, memory, GPU, display, storage, radios.
  - **Apple frameworks:** e.g. Core Location, SwiftUI.
  - Different features use different subsystems. Complex Metal effects hit the **GPU and display**, not storage.
- **Step one for a power problem:** figure out *which subsystems* the feature uses, then pick the matching Xcode/Instruments tool.
- **Key ones in this talk:** **CPU, GPU, display and location services.**
- **CPU first:** a huge share of an app's power, and a common cause of heat. It's easy to create **bursts** of expensive work, and the CPU then runs at **high frequency** (top speed), which costs extra.

### 11:38 AM · CPU: find it, then do less
- **Work that repeats often, like every frame, raises your app's power floor** and drains battery even when nothing much is happening.
- **Start in the Xcode Organizer:**
  - When an app uses too much CPU time in a short period, the system collects a **backtrace**.
  - These arrive as **energy reports** in the Organizer. They're spikes, so possible causes of heat, and battery drain if they happen often.
  - **This should be your first stop** for battery or heat work.
  - The same **MCP tools** from the first talk can read these energy logs, so an agent can too.
- **CPU fixes (general efficiency):**
  - **Does it need to happen at all?**
  - **Cache** (save a result instead of recomputing) or **defer** (do it later) expensive work.
  - Skip work that isn't relevant to what's on screen right now.
  - **Do it less often** if users can't tell the difference.
  - Use **more efficient algorithms**, or work on **smaller data**.
  - **Prefer Apple's high-level frameworks**, e.g. **AVKit** for video instead of building playback yourself in Metal.
- **The CPU is a window into everything:** it coordinates every other subsystem, so requests for GPU, network and so on show up in CPU **call stacks**.
- **Señor Crabb tie-in:**
  - The PixelFLEX emulator redraws every frame while a video plays: that's the "every frame raises the floor" case.
  - Using the browser's own `<video>` player (like AVKit) instead of custom decoding is already the right call.
  - Possible win: the wall already skips redrawing a still photo, but its loop still checks every frame. Letting it sleep would lower the floor.

### 11:40 AM · Time Profiler hints, the GPU, and the display
- **Time Profiler (CPU) gives hints** about what's really using power, even when the CPU isn't the main culprit.
- **GPU (Metal):**
  - Apps and games that use Metal directly have lots of room to optimize.
  - GPU work is different from CPU work: besides saving power, a game must **hit its frame deadlines** (draw each frame in time).
  - Usually **speed and power go together**: making it faster and able to run on more devices also uses less power.
  - Too much to cover in this talk. Apple points to its docs on **"Improving your game's graphics performance and settings"** and the **Metal debugger**.
- **Display:**
  - iPhone's **ProMotion** screen changes its frame rate to match the content, **up to 120 fps**.
  - When content changes less often, the phone drops to a lower frame rate, which **uses less power**.
  - It also lets your app **skip render work** on the CPU, GPU and other subsystems.
- **Games tie-in (Monkey Trubble, Poly Oracle):**
  - Don't redraw at 120 fps on menus or paused screens.
  - Let the frame rate drop when nothing's moving.
  - Check frame deadlines with the Metal debugger.

### 11:42 AM · Don't ask for more frames than you need
- With **UIKit, SwiftUI** or other Apple frameworks, the system handles frame rate for you.
- **The trap: over-specifying the frame rate.** Asking for more updates than needed redraws the screen more often with **no benefit** to the user.
- **Example:** an animation with haze, a pulse and particles, none of it moving fast. A lower frame rate looks the same and **saves a lot of power**.
  - It depends on the effect and where it's shown. On a huge screen it may genuinely need more, so **decide case by case**.
- **The API: `CAFrameRateRange`** sets a minimum, maximum and preferred rate for an effect. The system picks the real rate based on that and everything else going on.
- **Rules of thumb:**
  - Usually **don't set one at all** (`CAFrameRateRange.default`) and let the system choose.
  - For slow or small animations, try **24, 30 or 48 fps** if it still looks right.
  - **Reserve 120 fps for large, high-impact animations.** Even a cheap-to-draw animation saves a ton of power at a lower rate, because of all the system work it skips.
- **Games tie-in:** idle animations, background particles and menu effects in Monkey Trubble / Poly Oracle are prime candidates for 30 fps.
- **Señor Crabb tie-in:** the crab's idle loop and the slideshow's Ken Burns zoom are slow motion; they don't need 120 fps.

### 11:44 AM · Screen brightness, and location
- **Luminance (brightness) costs power:** darker pixels are cheaper to show than bright ones, especially with **HDR**.
- **Easy win: support Dark Mode.** It's an important accessibility option and, for some screens, uses slightly less power.
- **If you draw your own content:** only use **HDR surfaces** for content that's actually HDR.
- **Measure it:**
  - MetricKit's **average pixel luminance** metric estimates how bright your app keeps the screen.
  - Instruments' **Display** and **Frame Lifetimes** tracks show how often the app updates the screen.
- **Location (one of the biggest power costs):**
  - Using location can switch on many **sensors, radios and system services**. Starting them and keeping them running costs power.
  - The system *and* your app run to make and handle every location update, which raises the **power floor**.
  - **Continuously tracking location has a baseline cost** that well-written code can't remove, so it can mean a big battery hit.

### 11:46 AM · Location without the drain, and the Power Profiler
- **#1 location fix: avoid continuous tracking.** "The most critical thing you can do for power."
- **Use region monitoring instead** when you only need to know when someone enters or leaves a place. **`CLMonitor`** lets the system skip location updates while the device is far from the boundary.
- **When you truly need continuous tracking** (e.g. turn-by-turn navigation): **defer updates while the device is stationary**. With **`CLLocationUpdate`**, the **stationary** flag tells you the person isn't moving.
- **Background location deserves special attention:** it can use a ton of power very quickly.
- **Measure it:**
  - The **Location Energy Model** instrument loads automatically in the **Power Profiler**.
  - Use the **Power Profiler**, in Instruments or **on the device**, to measure power, including in the background.
- **On-device power trace (no Mac attached):**
  1. Turn on **Developer Mode**.
  2. Go to **Settings → Developer → Performance Trace**.
  3. Add your app to the **monitored apps** list.
  4. Choose the **Power Profiler** tracing mode.
  5. **Start and stop the recording from Control Center.** Power traces can run **for hours**, great for slow-to-show battery problems. Open the file in Instruments like any trace.

### 11:48 AM · Demo: a cat social-media app that drains battery
- **The app:** people post videos and photos of their cats, customize a cat avatar, and comment in character. It's National Cat Day, so long sessions, and **long sessions drain more battery than expected**.
- **Step 1, Xcode Organizer:** version 6.7 has **no energy reports**. That's a clue: the problem isn't short **bursts** (which would trigger reports) but **power that stays raised over a long time**.
- **Step 2, profile power directly:** start with the **Power Profiler** template in Instruments. It shows power plus a broad view of system activity.
- **Tailor the instruments** to the subsystems the scenario uses. The scenario here is **video playback**, which means UI work and the display.
- **Señor Crabb tie-in:** the slideshow plays videos for long stretches too. It's the same kind of long-session drain to check.

### 11:50 AM · Demo: reading the power trace, and a spooky 120 fps
- **Picked instruments to match the scenario:**
  - **Added:** **Display** (how often the screen updates) and **Network Connections** (the videos come from the internet).
  - **Removed:** **Metal Performance Overview** (they use **AVKit**, no custom Metal) and **Location Energy Model** (no location in the app).
- **Baseline numbers** from the Power Profiler overview: **CPU impact 2.2, GPU 1, Display 4**. Meaningless alone, but essential for **comparing after a fix**.
- **Ruling out subsystems one by one:**
  - **CPU** (Time Profiler) is reasonable, 10–30%, so it's not the CPU.
  - **Network** shows little activity, so it's not networking.
  - **Display:** "swapped surfaces" duration hovers around **8.3 ms**, which means the screen is updating at **120 fps**. "That's a bit spooky": the videos are only **30 fps**!
- **Next, find what's updating the screen:** Xcode's **Flash Updated Regions** colors any part of the screen that redraws **yellow**. Find it under **Debug → View Debugging → Rendering**.
- **Señor Crabb tie-in:** the same check would work here. Safari's Web Inspector has **Paint Flashing**, which highlights repainted areas, to catch anything redrawing more than it needs to (like the clock or PixelFLEX loop).

### 11:52 AM · Demo solved: the cat's tail was running at 120 fps
- **Flash Updated Regions showed yellow around the cat avatar's tail.** The video was paused, and **Liquid Glass** only redraws when what's under it changes, so the **tail animation** was the culprit.
- **Root cause:** the code set **`CADisplayLink.preferredFrameRateRange`** to ask for **120 fps** for a small tail wag.
- **The fix:** match the animation's frame rate to the video's:
  - A new helper, **`getVideoFrameRateRange`**, reads the video's frame rate and returns a matching **`CAFrameRateRange`**.
  - It's **future-proof**: if the video frame rate changes, the animation follows.
- **Verified with a new trace:** the display now runs at about **30 fps** instead of 120.

| Power Profiler impact | Before | After |
|---|---|---|
| CPU | 2.2 | **1.3** |
| GPU | 1.0 | **0.1** |
| Display | 4.0 | **2.0** |

- **Takeaways:**
  1. **Breaking the problem into subsystems** picked the right tools, narrowed it down, and found an important win.
  2. **The balance between quality and power:** for some animations a lower frame rate would look bad, but a small animation on top of 30 fps video looks just as good at 30.
- **Games and Señor Crabb tie-in:**
  - Check for any small looping animation (a crab idle, a monkey tail, a menu sparkle) that asks for 120 fps.
  - Matching it to the content around it can **halve display power and cut GPU power by 90%**, as here.

### 11:54 AM · Battery talk wrap-up
- **Done right, viewers can't tell** whether an animation runs at a high or low frame rate. Cuts that lower *theoretical* quality with **no real effect on the experience** are often the most valuable power wins.
- **The closing advice:**
  - Think about every workload in your app and **break it into the subsystems** it drives.
  - Ask which parts are core to the experience and which **aren't pulling their weight** power-wise.

## Session 3 (from about 11:55 AM): SwiftUI best practices with agent skills (Luca, SwiftUI team)
_Recorded live; notes added every couple of minutes._

### 11:55 AM · Xcode 27 ships with agent skills
- **Why it matters:** following SwiftUI's (and other UI frameworks') best practices is one of the best ways to get good performance, but those practices can be **hard to find**.
- **Xcode 27 ships with a set of agent skills.** A skill = instructions, reference material and examples that give an AI agent **specialized knowledge**.
  - Skills **load automatically** when they're relevant to your prompt, or you can **call one by name**.
- **This talk's focus: the SwiftUI specialist skill.**
- **Monkey Trubble tie-in:** you just updated Xcode. If it's Xcode 27, these skills are on your MacBook, so try asking the agent there to use the SwiftUI skill on the game's menus and screens.

### 11:56 AM · The demo setup: a pastry-rating app
- The SwiftUI skill extends SwiftUI's goal: **hide complexity so you can build great apps**.
- **The demo app:** Luca's team went on a San Francisco croissant tasting tour, and colleague Steven built an app to **track and rate the pastries**.
- **Steven's voicemail (he's on vacation, so Luca has to fix things):**
  1. **Performance:** profiling the pastry **list** showed the **cells update more often than they should**.
  2. **New feature:** a new tab with a **map of all the bakeries**. Built in a hurry, so it may **cut a few corners**.
- **Luca's plan, one step at a time:**
  1. Understand the codebase.
  2. Fix the update issue.
  3. Review the new map tab.

### 11:58 AM · Step 1: use the agent to learn an unfamiliar codebase
- **The app:** `PastryTrackerApp` is the entry point. The Xcode **preview** on the right shows the main screen: two tabs, a list of **tastings** (pastry, where, when, rating), and a **+** button in the navigation bar to add one.
- **Agents are great for exploring a new codebase.** Luca's routine:
  - Open the **coding assistant** (toolbar) → **New Conversation**.
  - Prompt: *"I want to understand this project. Make a table of the data layer, and add a very brief overview."*
- **Why start with the data layer:** picture the **data, its relationships and what you can do with it** first; the screens make sense after that.
- **Tip for you:** this works with Claude Code on any project, Señor Crabb or Monkey Trubble. Ask for "a table of the data layer plus a brief overview" before diving in.

### 12:00 PM · Why it matters in SwiftUI, and a live-demo hiccup
- Starting from the data layer lets you see **how the UI connects to the data**. In SwiftUI, understanding **a view's inputs and what makes it update** is fundamental to working with the framework.
- **Ask for a table:** Luca asks for output as a table because it's **easy to scan**.
- **Live demo glitch:** Xcode got stuck, so Luca quit and relaunched it and re-ran the prompt ("you know that this is live"). The audio went quiet while it reloaded.

### 12:02 PM · The data types, and following the data into the UI
- After the restart the agent wrote its table. Key data types (Whisper heard "testing"; it's **Tasting**):
  - **`Tasting`:** one tasting of a pastry at a location. It's the data behind **a single row** of the list, with nested types for **coordinate** and **rating**.
  - **`TastingStore`:** the **observable** type that holds the list of tastings and exposes it to the views. This is the interesting one.
- **Next:** learn how `TastingStore` is used and how data **flows through the UI**. That's the starting point for the view-update bug.
- **Xcode shortcuts from the demo:**
  - **⌘⇧O (Open Quickly):** type a name like `TastingStore` to jump to its file.
  - **⌘⌥⌃⇧H** ("keyboard yoga"): opens a **new agent conversation in a side pane** next to your code.
- **The question he asks the agent:** "How is this being used in a view, and which view is observing this data?"

### 12:04 PM · Step 2: find why the rows update too much
- **Work side by side:** code editor and agent next to each other, so you can glance at the source while the agent works and click around its answers.
- The agent's answer: **`TastingList` is the view that observes the store.** That's the next place to look.
- **`TastingList`** loops over the store's tastings and builds the list, **one row per tasting**. Steven said those rows update more than they should.
- **The prompt:** "The row is updating too frequently. Look into a fix."
  - It asks whether `Tasting` or `TastingStore` can be improved, because **a view updates when its inputs change**.
  - It explicitly asks the agent to **focus on view updates**.
- **First thing to check:** the **observable** should notify a view **only when something it uses actually changed**.
- The agent's transcript shows the **SwiftUI specialist skill** loading automatically for this view-update question.

### 12:06 PM · The fix: make `Tasting` Equatable
- Using the agent with this skill is "like sitting with a **UI framework engineer**", working together on modern practices.
- **The agent's diagnosis:** `Tasting` is **not `Equatable`**.
  - An `@Observable` type doesn't require its properties to be Equatable.
  - But if a property's type **is** Equatable, Observable **skips updating the view when the new value equals the old one**.
  - Without it, every assignment counts as a change, so the rows redraw even when nothing changed.
- **The fix:** all of `Tasting`'s properties are already Equatable, so just add **`Equatable` conformance**. Luca replied "Yes, add the conformance to Equatable".
- **Nice touches in Xcode's agent:**
  - The transcript shows each step: reading the file, editing, compiling.
  - Every edit appears as a **diff** in its own panel.
  - **Hover a line number to leave a line comment** asking for more changes or an explanation.
- **The skill also answers "why" questions**, e.g. "is there any benefit to making the model object Equatable?" (answer coming next).
- **Takeaway for Monkey Trubble / Poly Oracle (SwiftUI screens):** if a list or HUD redraws too much, check that its data types are **Equatable**. It's often a one-line fix.

### 12:08 PM · "Why" answers, then step 3: review the map tab
- **Question to the skill:** "Should I make `TastingStore` Equatable too? Would that reduce updates?"
  - **Answer: no.** Updates for an observable *store* aren't driven by an equality check but by the **change signals `@Observable` sends**. Equatable helps the **values inside** it (like `Tasting`), not the store itself.
- **The skill explains every recommendation**, so you can use it to **learn**, not just to get code.
  - "Even when most of the code is written by AI, **understanding is fundamental** to collaborating with the agent and **verifying its work**."
- **Targeted vs. broad:** the row fix was a targeted look at one type. The skill is also good for **broad code reviews**.
- **Step 3, the rushed map tab:**
  - Start a **new conversation** so the agent has **fresh context**.
  - Prompt: "Look at all the views related to the map view, and **review them for best practices and opportunities to modernize**."
- **Try this on Monkey Trubble:** "review [screen] for best practices and opportunities to modernize". It's a great way to find rushed or old code.

### 12:10 PM · How to run an agent review without drowning
- **The full prompt:** review the map views for best practices and modernizing, then **propose a list of all the improvements and work through them one by one**.
- **Keep reviews focused:** don't review the whole codebase in one prompt.
  - On big projects it **fills the agent's context window**, which makes it worse at the job.
  - It's also **overwhelming for you**.
- **Ask for one suggestion at a time:** a big wall of issues is intimidating. Get a **summary first**, then go through the fixes **in order of importance**.
  - That helps you **understand and trust** each change.
  - Making a change and checking it works is "a very fun and effective way to learn" a new part of the codebase.
- **The result:** improvements grouped into categories (**localization, best practices, accessibility** and more), so it's easy to see what matters most.
- **This is how you and I work together too:** one focused area, a summary, then fixes one by one with checks in between.

### 12:12 PM · First fix applied, and the other Xcode 27 skills
- The agent ranked the most important areas and highest-impact changes. Luca started with **localization** (working well in every language and region): "as you might guess from my accent…".
- **What the SwiftUI Specialist skill is good for:**
  1. **Targeted fixes** (like the Equatable rows).
  2. **Learning how SwiftUI works**, so you get more out of the agent.
  3. Acting as **your own SwiftUI engineer**, continuously reviewing and improving the app.
- **Other skills in Xcode 27:**
  - **App resizability:** gets your layout ready for **"iPhone Duo"** (confirmed in the panel), a new iPhone with a different screen setup. It also covers modern UIKit practices.
  - **What's new in SwiftUI 27:** new APIs and behavior. It **bridges the gap** between what the AI model was trained on and today's APIs, and it's also a good way for you to learn what's new.
  - **Document-based apps:** new APIs like `ReferenceFileDocument` and how to adopt them.
  - **Beyond UI:** skills for **App Intents**, **security** and **testing**.
- They all **come prepackaged** with Xcode's coding assistant.
- **For your games:** ask for the "What's new in SwiftUI 27" skill to modernize menus. The app-resizability skill will matter if the new iPhone has a different screen shape.

### 12:14 PM · Skills work in any agent, and the afternoon schedule
- **The skills aren't Xcode-only:** "we built them to be used with **any coding agent of your choice**". An **`xcrun` command exports all the available skills** so you can add them to your agent, e.g. **Claude Code**. The exact command was on a slide; `xcrun` with Xcode 27 should list it.
- **Go try it:** let the SwiftUI skill **review specific areas** for best practices, and keep it on while writing new code. Apple wants **feedback** to improve it.
- **Lunch, then the afternoon:**
  - **1:30–2:30 PM Pacific:** live **panel Q&A** with engineers on the performance questions from today (on the stream, and in person in Big Sur).
  - **In person:** **engineering labs** all afternoon with **40 Apple engineers** (power, performance and more) in three lab areas, including general performance labs on both floors.

## Session 4 (from about 1:30 PM): live panel Q&A on performance
_Recorded live; notes added every couple of minutes._

### 1:31 PM · Panel intros, and why the SwiftUI skill exists
- **Where to ask more:** the Apple Developer Forums; bugs and feature requests go to **Feedback Assistant** (feedbackassistant.apple.com).
- **The panel:**
  - **Steven:** UI Frameworks; the pastry app's "vacation" developer.
  - **Luca:** UI Frameworks; the SwiftUI skill talk.
  - **Abneen:** Power; the cat app talk.
  - **Shefali:** third-party performance tools; the first talk.
  - **Phil:** performance engineering.
- (Steven did bring Luca the promised magnet. 😄)
- **Why the SwiftUI team built the skill:** to give every developer the feeling of **a UI framework engineer sitting next to them**, writing new code, reviewing existing code and helping them write *correct* code.

### 1:33 PM · Skills as "bleeding-edge knowledge", and read them yourself
- **Skills close the training gap** between what the AI model learned and Apple's latest APIs and recommendations.
  - **Example:** in **iOS 27, `@State` became a macro instead of a property wrapper**, which causes small source-compatibility issues. The "What's new in SwiftUI 27" skill tells the agent which **compiler errors** to expect and how to fix them.
- **"Deep cuts":** the skills hold the hidden-gem tips Apple engineers usually share one-on-one in labs, very situation-specific performance advice. The aim is to feel like **sitting in a lab with the team**, even if you can't be there.
- **Recommendation: export the skills and READ them.** Every recommendation explains its motivation, so you can learn a lot from reading them directly.
- **Auto vs. asking:** skills should **activate on their own** for relevant tasks; you can also call them by name. More on this next.
- **For you:** once the skills are exported on the MacBook (the `xcrun` follow-up), open the SwiftUI and performance ones and skim them. It's a free crash course from Apple's engineers.

### 1:35 PM · Make sure the skill is actually used; performance and money
- **Skills activate from your prompt:** asking about best practices, code review, or "write modern SwiftUI" should trigger it. You can also **invoke it by name**.
- **Gotcha: some AI models are overconfident** and skip the skill ("I'm the new thing, I don't need it"). Xcode and most agent tools **show when a skill activates**, so watch for that.
  - **Tip:** to be sure, just say **"use the SwiftUI skill to check best practices"** on new code.
- **New topic (Phil and Shefali): does performance make money?** Phil quoted **Notion** and **Tinder** this morning: better performance isn't just nicer to use, it shows up in **business outcomes** they measure.
  - **The question:** does Apple provide anything to connect performance improvements to dollars, and if not, how would you build it? Answer coming next.
- **For you:** when Claude on the MacBook works on Monkey Trubble, say "use the SwiftUI skill" explicitly. Don't rely on it kicking in.

### 1:37 PM · Tying performance to business results (Phil)
- **Quality and retention go together:** Apple's data shows **app quality and retention are closely tied**.
- **To judge if a performance fix is "worth the squeeze"**, look at **retention**, **engagement** (time on screens and features) and **churn**.
- **Apple provides business metrics in App Store Connect:** revenue, churn and more, plus **peer group benchmarks** comparing you with similar apps.
  - They aren't tied to app versions, but you can still connect a big change to a shift in business numbers: "I shipped version X with a major rework, and retention jumped".
- **Phil's advice for the AI era:**
  - Use AI to get performance and quality as good as possible.
  - Then **focus on customer and product metrics** (retention, engagement, churn) as the real sign of quality, rather than staring only at hang rate or battery numbers.
- **MetricKit plus state reporting** can split performance data by **feature area or team** (whoever owns that part).
- **For Monkey Trubble / Poly Oracle:** after a performance update, check **App Store Connect → retention and engagement** for that version, and compare with the **peer group benchmarks** for similar games.

### 1:39 PM · Using MetricKit for business questions, and "realistic" goals
- **Getting started connecting data to outcomes (Shefali):**
  - The **peer group benchmarks** are also in the **App Store Connect API**, so you can pull them automatically.
  - Use **state reporting** to tag new features or how people use the app, then check whether that usage **correlates** with business metrics, especially after shipping something new.
  - MetricKit lets you **"slice and dice"** the data many ways for the whole picture: *did I move the needle?*
- **Xcode Organizer recommendations:** the Organizer shows your app's metrics next to **recommended targets** based on similar apps. If peers do better on a metric, that's your goal to strive for.
- **Why the goal isn't "zero hangs":** the Organizer suggests a hang rate based on similar apps rather than perfection, because so much else is happening on the device. The full answer is coming next.

### 1:41 PM · Strive for the norm, not perfection
- **Zero hangs is nearly impossible:** with everything else happening on the device, something will occasionally block the main thread.
- **Peer-based goals tell you what's achievable** for your app's features and category: how similar apps actually do on hangs.
  - **"You're not striving for perfect, you're striving for the norm."**
- Help your team and agents get performance to **"good enough"**, then **shift focus** to other things (the sentence continued into the next chunk).
- **For your games:** compare Monkey Trubble's hang rate with similar **games** in the Organizer, not with zero.

### 1:43 PM · Good enough frees you up; the tools work outside Xcode too
- Once performance is good enough, spend the time on **the next feature that brings people in**, or on **re-architecting** things that weren't built right to begin with.
- **The real danger:** hangs so bad that people **stop using the app**, which hits retention directly. The goal is an app that feels smooth.
- **Big question: do you miss out using other agents (like Claude Code) instead of Xcode's?** Panel answer: **"Practically, no."**
  - The **skill bundles can be exported** to any agent.
  - The tools and recommendations are available through **MCP**.
  - **xctrace is a command-line tool**, usable by any agent.
  - Apple "would love" you to use Xcode, but built the tools to work **outside Xcode on purpose**.
  - Nice extra inside Xcode's coding assistant: **inline line comments** on the agent's edits, which even the panelists didn't know about until rehearsal.
- **For you:** confirmed. Claude Code on your MacBook can get the same skills and tools (export the skills, connect the Xcode MCP Server, use xctrace).

### 1:45 PM · Xcode's agent extras, xctrace beyond hangs, automated perf testing
- **Xcode coding-assistant niceties:**
  - A color-coded transcript of everything the agent does (how much you see varies between agent tools).
  - **Easy switching between AI models from different providers** in the same tool, handy for comparing results.
- **Does xctrace work for more than hangs? Yes.**
  - `xctrace triage` was shown on hangs.
  - **`xctrace show` works for everything else.** Throw any trace with a performance issue at it, and it should explain what's happening performance-wise.
- **Next question: automated performance testing.** If an agent verifies its own fix in a loop, you don't want that in the Simulator, so what are the best practices? Answer coming.
- **For you:** `xctrace show` is the one to try on a Monkey Trubble trace that isn't a hang (slow level load, stutter).

### 1:47 PM · Automated performance testing: real devices, and when the Simulator is OK
- **Key: a physical device.** Set up the heavy parts of your code so you can write and run **performance tests** around them. An agent can help write them.
- **Test away from ideal conditions:** not just at your desk next to the router where the network's fastest.
- **Simulators are fine for direction, not accuracy:**
  - Most people can't run a **device farm** (racks of real phones with cables and staff).
  - A Simulator won't tell you real battery drain or storage, but it **will** tell you "version B did objectively more work than version A".
  - That's a good starting point for **agent loops**: the agent finds things to optimize on its own and keeps iterating until the feature is good enough.
- **Recommendation:**
  - Use the Simulator **with xctrace and Instruments** (built for measuring on Apple platforms).
  - Treat its numbers as **"better or worse?"** signals, never as real-world truth.
  - Confirm on a real device.
- **For Monkey Trubble:** let Claude loop on the Simulator to find big wins (e.g. "did this make the level load do less work?"), then confirm on your real iPhone.

### 1:49 PM · Can agents debug the GPU too? (Abneen)
- **The question:** agents can read CPU traces for hangs; what about **GPU** problems?
- **Starting points in a normal trace:** the **Metal Performance Overview** instrument and the Power Profiler's **average GPU impact**. Often **not enough detail** to really pin down GPU issues, especially for an agent missing the context you have.
- **Humans use the GPU debugger:** extremely powerful, it **plays back frames** and gives a ton of information.
- **New: agents can inspect GPU debugger capture files** (part of Whisper's transcript was garbled here), so they understand the same things you'd see in the GPU debugger's interface.
- A panelist used it on their own **visionOS** project (Compositor Services).
- **Big one for your games:** Monkey Trubble and Poly Oracle are GPU-heavy. Capture a frame in Xcode's **Metal/GPU debugger** during a heavy scene and hand the capture to Claude to analyze, like the hang demo but for graphics.

### 1:51 PM · GPU capture worked great; is xctrace triage private?
- **A real result:** a panelist captured a Metal frame with the debugger, handed it to their agent, and it found "great stuff" a GPU expert would find.
- **Privacy of `xctrace triage`:**
  - It **runs locally** on your Mac with your local trace. Nothing is uploaded to an Apple server.
  - **What matters is the agent:** whatever trace details you give the AI model are subject to *that model provider's* data retention (your API or subscription terms).
  - The distinction: triage extracts features from the trace **on-device**; only what you pass to the model leaves the machine.
- **For you:** when you hand a Monkey Trubble trace to Claude, the trace itself is processed locally; only what Claude reads goes to Anthropic, under your account's terms.

### 1:53 PM · MetricKit vs. Crashlytics/Sentry: use both
- **The question:** if you already use **Firebase Crashlytics** or **Sentry**, does MetricKit overlap or conflict? Pick one, or run both?
- **Phil's answer:** they work together.
  - **MetricKit is a data source**; tools like Sentry and Crashlytics are full products that can **use** MetricKit's data and add much more on top.
  - His (self-admittedly terrible, he's hungry) analogy: **MetricKit is the maple tree; Sentry makes the syrup.**
  - MetricKit gives an app **one shared set of data** that any number of **subscribers** (your code, Sentry, etc.) can read.
  - It's not duplicate work: MetricKit saves those tools from doing heavy **in-process** monitoring (crashes, animation hitches, errors) themselves, which also keeps your app faster.
- **For Monkey Trubble:** if you add Crashlytics or Sentry, keep MetricKit too; they complement each other.

### 1:55 PM · When do speed and power NOT go together? (Abneen)
- **Wrap-up on Sentry/Crashlytics:** doing everything in-process adds **observability overhead** and surprise problems; MetricKit avoids that. Use them together, since many of those frameworks already read MetricKit.
- **The question:** Abneen said speed and power are "**usually**" aligned. When aren't they?
- **Usually aligned, on every subsystem:** taking less time typically means doing **less work**, which means burning less power (power = the rate work is done).
- **But there are case-by-case exceptions** for each subsystem. Example starting with **two threads** (continued in the next chunk).

### 1:57 PM · Where speed and power disagree
- **Two-threads example:**
  - If one thread waits on another by **spinning** (constantly checking "done yet?"), it reacts instantly, which is good for speed, but the spinning **burns power**.
  - A **messaging** approach (be notified when it's done) is about as fast and **better for power**, because nothing spins.
- **On the GPU,** speed and power mostly agree, since it's "go do the compute" with low-level control. The big exception is **frame rate**: more frames means more work and more power, even if each frame is fast.
- **For your games:** never busy-wait (spin) for things like assets loading; use completion callbacks or async/await. And remember frame rate is the biggest GPU power dial.
- **Next question:** back to Luca, on using the SwiftUI specialist to understand an inherited codebase.

### 1:59 PM · Existing project vs. brand-new app (Luca and Steven)
- **When just exploring a codebase,** the SwiftUI specialist usually *won't* activate; that's normal "understanding" work.
- **With an existing project,** use the skill to **question decisions**: "Is this a good decision, and why?" It explains its reasoning.
  - Build a **mental model** by asking questions, then ask the agent to make a small change and **check it does what you expected** (e.g. "if this call happens later, is that what I expect?").
- **With new code:** you mostly just want it written with the right design and best practices.
- **Remember models are a snapshot in time:** they don't know everything about current SwiftUI, which is why the skill tells the agent how to write good, modern code.
- **For Monkey Trubble (an existing codebase):** ask "is this a good decision and why?" about parts you're unsure of, and test small changes to confirm your understanding.

### 2:01 PM · Build the skill into new projects from the start; skills keep evolving
- **For new apps, make the specialist part of the process from day one,** so the agent doesn't skip Apple's guidance just because its training thinks something is fine.
  - **Example:** putting a **closure in the SwiftUI environment** looks OK to a model, but the skill explains *why* not to, and models are convinced by the reasoning.
- **Skills are how Apple shares expert knowledge as it evolves** (Phil):
  - Over time, models will absorb today's skill content and do these things **by default**, like how Control Center went from a big new feature to second nature.
  - Skills keep **iterating** to pass on what only a UI performance engineer or power engineer at Apple would know.

### 2:03 PM · Always pull the latest skills; "What's new" matters; SwiftUI's environment trap
- **"There's never not a good reason to pull in the latest skills"**: they're basically **free context**.
- **Don't sleep on the "What's new" skill.** Before WWDC they tested whether an agent could answer questions about brand-new APIs (e.g. **reorderable** lists, new **swipe actions**). It couldn't, so the skill steers it right from day one.
- **A pattern the skill handles well: the SwiftUI environment** (Steven's talk last year, "closures are spooky"):
  - Putting **frequently changing geometry** (sizes and positions) into the environment makes view bodies **re-run far more than needed**.
  - Closures in the environment cause the same.

### 2:05 PM · The skill offers options, pairs with the SwiftUI instrument, and the automatic-fix pipeline
- **These fixes are often architectural,** not a two-line change: how model objects are structured, where a closure should live, how often it updates. The skill presents **A/B options** to choose from.
- **Pair it with the SwiftUI instrument:**
  - If Instruments shows a view updating too often, tell the agent "this view updates frequently".
  - It uses the skill to read the code and triage why.
  - It also nudges away from big **`onChange`** blocks that re-read every property and trigger massive updates.
- **Next, Shefali on the "pipeline":** grab data from MetricKit and the performance MCP tools, let the agent propose fixes, and you just review and merge. Three data sources: **MetricKit, the Organizer/performance MCP tools, and tests**.
- **For your games:** run the **SwiftUI instrument** on Monkey Trubble's menus and HUD; for any view updating too much, give its name to Claude with "use the SwiftUI skill".

### 2:07 PM · The data-to-fix pipeline, step by step (Shefali)
- **Three data sources** from your real users:
  1. **MetricKit.**
  2. The **performance MCP tools**, which fetch data from the **Xcode Organizer**.
  3. The **App Store Connect APIs**, a programmatic way to get power and performance data.
- **The loop:**
  1. The performance MCP tools **analyze the data in the context of your codebase** and tell you exactly **why** each regression happened, with recommendations.
  2. An agent **assesses the impact** of each recommendation (or picks the best) and **builds an implementation** of each.
  3. **You test it,** or a model stages it for you to view and try.
  4. **Measure with XCTest:** test before vs. after to confirm the improvement.
  5. If behavior is unchanged and you're happy, **merge it.** Data to fix, faster than ever.
- **Phil:** "a lot of **anecdotal** success" (his emphasis: no hard numbers yet) with using simulations… (continues next chunk).

### 2:09 PM · "Reproduction gates": make the agent prove the bug before fixing it (Phil)
- **What works:**
  - Take a real-world signature of a problem (e.g. a hang pattern from production data).
  - Spin up a Simulator and reproduce it with a **UI test with `measure` blocks**, Instruments running in the background.
  - Tell the agent: **"Reproduce this issue first, and don't pass until you can. Then write the fix and prove the reproduction no longer happens before you open a PR."**
- **Why repro gates are key:** they tell the agent **when it's done**, and they **keep it on track**. Without them agents wander off ("I found three other bugs too!"), and you end up with a huge PR to review.
- **For you (and how we work):** same principle as our timeline work. Measure first, fix, then re-measure to prove it, one problem at a time.

### 2:11 PM · How do you know when good is good enough?
- **Phil:** hand your app to someone who's never used it. **Does it feel magical?** If people (like his mom, who texts him daily about other companies' apps) notice problems that pull them out of the experience, it's not good enough yet. The best apps feel smooth in your hands, and that isn't one number on a graph.

### 2:13 PM · Don't chase every number; hitches by area
- **Ask yourself:** what made *you* swipe up and force-quit an app before? If your app does that, optimize it first.
- **Don't get hyper-fixated on metrics:**
  - Instruments shows **hitches**, but the real question is whether people **notice** them while scrolling.
  - Chasing invisible ones can waste your time.
- **Hitches per part of the app:** the Xcode Organizer shows one app-wide hitch number; **MetricKit** (with state reporting) can break it down by area.
- **For your games:** after each play-test, ask "did anything make me want to quit?" That's your priority list, more than raw numbers.

### 2:15 PM · Breaking down hitches by app area (MetricKit 27 + state reporting)
- **The Organizer can't split hitches by screen today.** File it as a **feature request** in Feedback Assistant ("all of those come to me").
- **MetricKit can,** and then you trace and profile to find the cause and fix.
- **Old way:** OS signposts for animation begin and end, which are interval-based. But people think about UI as **states** with things loading in parallel, not intervals.
- **New in MetricKit 27:** with **state reporting**, you label product states like **"buy page"** or **"save action"**, and MetricKit does the **intersection** for you:
  - e.g. "hitch rate on the view page during this time range"
  - also crossed with other states like "syncing" or "online content"
  - so you understand hitches **in the context of what the app was doing**.
- **For your games:** report states like "menu", "level loading", "boss fight", "paused", and MetricKit will show which state stutters for real players.
- **Next:** Steven on the tools he uses to debug SwiftUI hitches.

### 2:17 PM · How Steven debugs SwiftUI hitches
- **Why a plain Time Profiler isn't enough:** in SwiftUI it mostly shows SwiftUI's own code running, which doesn't map back to *your* code.
- **His recipe:**
  - Use the **SwiftUI instrument template**, which includes the **Hitches** instrument automatically.
  - Profile the part of the app with the **most animation**, usually **scrolling**.
  - **The hitch shows up slightly after the work that caused it,** so expand the Hitches instrument, find the **update interval**, and line it up with the SwiftUI instrument's work.
  - **Look for two culprits:**
    - **slow updates**, e.g. something **synchronous** (blocking) accidentally done in a view body
    - **too-frequent updates**, "churning" faster than expected
  - **Goal:** shorten the hitch until it's unnoticeable, even if it can't disappear in a stressed situation.
- **Don't over-fixate:** a hitch rate of 1 ms per second is **imperceptible**.
- **Profile in Release mode, not Debug:** Debug builds are "guaranteed to get worse results". Fine for rough counting, like the Simulator, but to see what users experience, use **a real device in Release mode**.
- **For your games:** when profiling Monkey Trubble, set the scheme to **Release** (⌘I usually does this by default), on a real phone, and profile the most animated screen first.

### 2:19 PM · More on Release mode; a third-party SDK stuck at 120 fps
- **Debug can mislead you:** a debug `print` in a view body might show "5 updates" in Debug, but in Release the compiler **optimizes some of those updates away**. Keep checking the Release configuration for the real picture.
- **Release profiling also gives proper symbols** (your function names) in call stacks.
- **⌘I (Profile) uses Release for you** automatically.
- **Can you override a third-party SDK that locks the screen to 120 fps?** Not really. You have to "own" it:
  - Send the SDK maker a feedback request.
  - Check whether **your usage** is triggering it, and do less of that.
- **For your games:** if Monkey Trubble uses any ad or analytics SDK, check with the Display instrument that it isn't forcing 120 fps on menus.

### 2:21 PM · When third-party code hurts your performance
- **The device can't know your intent:** if an SDK asks for 120 fps, it runs at 120 fps.
- **SDKs can hurt launch time** (e.g. lots of static initializers), and you usually can't switch that off without breaking things.
- **Why it's hard:** many of these problems only appear in edge cases (the very first launch, right after an update, after a phone restart), so even the SDK makers may never see them.
- **What works (Phil):** a rigorous routine of **testing core metrics on every new version**, especially **app launch**, because everybody launches the app.
  - **XCTest performance tests** can measure launch; add one whenever you bring in a big new framework or SDK.
- **For Monkey Trubble:** add a launch-time XCTest and run it before each release, especially after adding any SDK.

### 2:23 PM · Baselines for SDKs, and the UIKit / app-resizability skill
- **For big, core SDKs:** create **baselines** and run tests. Static initializers (the **`load`** methods) are visible in traces, so watch for them.
- **Collect the data and work with the framework's maker:** most SDK owners **care** and want the feedback, just as Apple does for its own frameworks.
- **Skills for UIKit (Luca):** the **app resizability** skill covers UIKit too.
  - Its main purpose is getting apps **ready for "iPhone Duo"** (heard twice now, so the name seems right).
  - It's a big collection of **modern UIKit practices**: follow them and your app is ready for iPhone Duo.
- **For Monkey Trubble:** if any screens use UIKit, run the app-resizability skill so the game adapts to iPhone Duo's screen.

### 2:25 PM · Other skills worth reading; agents and trace "token bloat"
- **Read all the skills,** the panel says. Notable ones:
  - **App Intents** (Siri, Shortcuts, Spotlight), "a really important part of the platform".
  - A **security** skill on **bounds checking in C** for very low-level code.
- **Send Apple feedback** about skills you'd like to see or that are missing.
- **New question:** people report agents dumping traces to **XML** and burning "a bajillion **tokens**". Do the new xctrace tools help? (Shefali: agents tend to convert data into formats they're comfortable with… answer continues.)

### 2:27 PM · xctrace is built to save tokens; triage first, then show
- **Tokens are "the most precious commodity right now".** Agents turning raw data into formats they like (big XML dumps) eats them.
- **xctrace converts trace data into an easy-to-parse format,** so the agent reads only the pieces it needs. Apple designed its tools to be **as token-efficient as possible**, leaving more of your budget for actual building.
- **Why the demo agent ran `triage` first:**
  - **Triage** answers "is there anything meaningful here, what should I do, and which time period matters?" **If nothing's there, it stops**, which is cheap.
  - **Show** then expands on what triage found, instead of crawling the whole timeline.
- **For you:** when Claude works on a Monkey Trubble trace, tell it **"run `xctrace triage` first, then `show` only on what it flags."** Don't let it export the whole trace to XML.

### 2:29 PM · The panel's favorite under-used tools
- **Steven: the (new) SwiftUI instrument.** Many people only know the *old* one. If it's been a while, look at Instruments again; there have been big advances in the last couple of years.
- **Abneen: Xcode's debug rendering options** (Debug → View Debugging → Rendering):
  - **Flash Updated Regions** (redrawn areas flash yellow).
  - **Compositor Fast Path:** with color flashing, "invaluable" if **video** is a main part of your app.
  - **What the compositor is:** the system part that combines your app with everything else on screen (clock, battery, and on **iPhone Duo** potentially *another app*) into the final picture. Staying on its "fast path" saves power.
- **For you:** if Monkey Trubble has video cutscenes, check them with Compositor Fast Path.

### 2:31 PM · Compositor colors, and wrap-up
- **Compositor Fast Path debug colors** (Abneen, "don't quote me on the colors"): **blue = on the fast path** (much less energy, much faster); **red = missing it**. Figure out why and fix it for big power and speed wins. It applies to video and Metal rendering.
- **End of the day:** keep asking on the **Apple Developer Forums**, and send feedback through **Feedback Assistant**.

## The afternoon in one breath (panel takeaways for Paul)
- **Export Apple's skills into Claude Code and read them.** You lose "practically nothing" by not using Xcode's agent. Say "use the SwiftUI skill" explicitly.
- **Agents with traces:**
  - `xctrace triage` first, then `show` on what it flags (saves tokens).
  - Agents can now read **GPU frame captures** too.
  - Triage runs **locally**.
- **Repro gates:** the agent must reproduce the bug before fixing, and prove it's gone after. Keeps it focused.
- **Measure right:** a real device, in **Release** mode. The Simulator is fine for "better or worse" only.
- **Good enough = feels magical to a newcomer.** Fix what would make *you* force-quit; don't chase invisible numbers.
- **MetricKit 27 + state reporting:** hitches and hangs per game state. Pairs with (doesn't replace) Sentry or Crashlytics.
- **Speed ≠ power sometimes:** no spin-waiting; frame rate is the GPU's biggest power dial.
- **Third-party SDKs:** launch-time tests every release; report problems to the SDK maker.
- **New iPhone "Duo":** run the app-resizability skill.

## From the written Q&A thread (71 questions, 29 answered by Apple)
_Full thread: `apple-dev-conference-2026-10-29-QA-thread.md`. **The event replay:** https://developer.apple.com/videos/play/meet-with-apple/284/_
- **Best way to start profiling:**
  - **Product → Profile** (Release build) → **Time Profiler**, on a **physical device**.
  - Walk through common user flows, then check the **Hangs** track.
  - Right-click a hang → **Set Inspection Range** to focus the Time Profiler on it.
- **Showing the current screen in a trace:** use **StateReporting** to mark the active screen, then view it in the **Points of Interest** instrument next to Time Profiler.
  - You can add Points of Interest to the **Allocations** template too, but **don't** record Allocations and Time Profiler together (Allocations adds overhead).
- **`xctrace` details:**
  - **`triage` only covers hangs** today.
  - **`show` works with every instrument except Allocations, Leaks and VM Tracker.**
  - `show` can **filter by time range** (avoids giant exports, e.g. one SwiftUI table was 2.6 GB).
  - There's **no JSON output** yet (request it via Feedback).
  - `triage` runs **entirely locally**; only what the agent reads goes to the agent.
- **Organizer data:**
  - Needs users to have **"Share with App Developers"** turned on.
  - Needs **enough versions and users**; new apps may show "Insufficient usage data", so check back in a few days.
  - The **recommended targets don't analyze your code**, only your history plus similar apps.
- **MetricKit isn't gated by that setting** (Apple doesn't process it), so you decide how and when to collect it.
- **Share Organizer data with your team without Xcode:** it's all in the **App Store Connect API** (Power and Performance Metrics and Logs).
- **Local performance numbers:** use **XCTest performance tests** with **XCTHitchMetric** and **XCTApplicationLaunchMetric**, plus **baselines** to compare runs.
- **Always use real devices:** the **Simulator can't record hitches** at all and differs from devices "both positively and negatively". Automated performance tests should run on a real device too.
- **Power Profiler is iOS and iPadOS only** (no watchOS).
- **Storage bloat:** put re-creatable files in the **Caches** or **tmp** directories so the system can purge them safely.
- **Code from other languages:** native-compiled code needs a **dSYM** for readable names in Time Profiler. Interpreted languages (Python, JS) can't show call stacks in Instruments, so use their own profilers.
- **Memory spikes** (big PDFs or images): Apple's guide, "Gathering information about memory use".
- **Shortcut to open the coding assistant beside a file:** **⌘⌥⌃⇧H**.
- **For your games:** start with the Product → Profile recipe above on a real phone, add StateReporting for game screens, and put **XCTApplicationLaunchMetric** and **XCTHitchMetric** tests in place with baselines.

## What actually matters for Paul (morning summary)
**For the games (Monkey Trubble, Poly Oracle):**
1. **Measure first, on a real iPhone:** ⌘I → Time Profiler with Hang Detection on, plus an on-device **Power Profiler** trace (Settings → Developer → Performance Trace) during a normal play session. Save it as the **baseline**.
2. **Frame rate is the biggest power lever:** don't run menus, paused screens or idle animations at 120 fps. Cap small effects to 30 fps with `CAFrameRateRange` (the cat-tail fix cut GPU power 90%).
3. **SwiftUI screens that redraw too much:** make the data they show `Equatable`.
4. **Use the agent like Apple does:**
   - Hand it the trace and ask it to find the cause.
   - Review **one screen at a time** in a fresh conversation, fixing **one thing at a time**.
   - Always re-record to **verify** each fix.
5. **Give Claude Code Apple's skills:** export Xcode 27's skills with the `xcrun` command, and try the Xcode MCP Server.

**For Señor Crabb:**
1. **Signposts are in**, so record a baseline of the slideshow in Safari's Timelines.
2. **PixelFLEX power floor:** let the wall's loop sleep while a still photo is showing.
3. **Check for needless repaints** with Safari's Paint Flashing (the web version of Flash Updated Regions).

### How this maps to Señor Crabb (a web page, not an iPhone app)
Apple's demo runs Xcode + Instruments on the Mac, with the app on a connected iPhone/iPad. Señor Crabb runs in Safari, which has the same tools built in:

| Apple talk (iPhone app) | Señor Crabb (web page in Safari) |
|---|---|
| Instruments | Safari **Web Inspector → Timelines** (⌥⌘I) |
| Trace | a Timelines recording |
| Signposts / Points of Interest | `performance.mark` / `performance.measure` |
| Hangs instrument | long tasks (the page couldn't respond) |

## Glossary (plain English)
- **Instruments:** Apple's app for watching an app while it runs, like a heart monitor for software. It records what the app is doing every moment so you can see what's slow.
- **Trace:** one Instruments recording. Like a video of what the app did, but of its activity instead of its picture.
- **Time Profiler:** the Instruments recording type that shows where time is being spent (which code is busy).
- **xctrace:** Instruments without the window. You start recordings by typing a command, so a script or AI agent can do it.
- **Profiling:** recording and measuring an app's performance, as opposed to just running it.
- **Signpost:** a "start here / stop here" marker you put in your own code, so a trace shows exactly how long that step took.
- **Points of Interest:** the row in Instruments where your signposts show up as labelled bars.
- **OSSignposter:** the Swift tool you use to drop signposts.
- **State reporting:** like a signpost, but it records which *mode* the app is in (e.g. "editing", or a feature flag being on) instead of how long a task took.
- **Feature flag:** an on/off switch in your code that turns a new feature on or off without shipping a new version, handy for testing a change safely.
- **Reverse-DNS name:** a naming style that starts with your web address backwards, e.g. `com.wwg.slideshow`, so names never clash with anyone else's.
- **Simulator:** a fake iPhone/iPad on your Mac. Fine for checking layouts, but its speed doesn't match a real device.
- **Hang:** the app freezes and stops responding to taps, even for half a second.
- **Hang Detection:** a developer setting on iPhone/iPad that pops up an alert the moment the app hangs.
- **Network Link Conditioner:** a tool that deliberately slows down or breaks the internet connection, so you can see how the app behaves on bad Wi-Fi.
- **⌘I (Profile):** Xcode's shortcut to build the app and open it straight in Instruments.
- **Coding agent:** an AI (like me) that reads code or traces and makes changes. Apple is designing traces so agents can read them too.
- **CI (continuous integration):** an automatic setup that builds and tests your app every time code changes.
- **Template (Instruments):** a ready-made set of instruments for a job, e.g. Time Profiler for slowness. Pick one instead of building your own.
- **Instrument (lowercase):** one measuring tool inside Instruments, e.g. "Hangs" or "Points of Interest". Each shows up as its own row in the trace.
- **Baseline:** the "before" measurement. You fix something, record again, and compare to the baseline to prove it got faster.
- **Main thread:** the one lane of work that draws the screen and handles taps. If something slow runs there, everything freezes: that's a hang. Heavy work belongs on a **background thread** (another lane).
- **Call Tree:** Instruments' list of which code was running and how much time each part took, nested like folders.
- **Call stack:** the chain of "this code called that code" at one moment. Reading it top to bottom shows how you got to the slow part.
- **Inspection range:** the slice of the trace you've zoomed into, so the numbers only cover that moment.
- **Render / PNG preview:** drawing something into an image file (here a note's thumbnail). It's often slow when done on the main thread.
- **Coding assistant (Xcode):** the AI chat built into Xcode. You can drag files like traces into it.
- **Anti-pattern:** a common way of writing code that seems fine but causes problems, a known "don't do this".
- **Priority inversion:** urgent work stuck waiting behind unimportant work, like an ambulance stuck behind a garbage truck in a one-lane road.
- **Lock (shared lock):** a "one at a time" rule so two parts of the app don't change the same thing at once. If the main thread waits for a lock, it hangs.
- **QoS (Quality of Service):** a priority label you give work (e.g. user-interactive, background) so the system knows what to do first.
- **Structured concurrency:** Swift's built-in way (async/await, tasks) to run several things at once safely.
- **Main actor:** Swift's name for "this code must run on the main thread". Keep heavy work off it.
- **nonisolated async function:** Swift code marked so it doesn't have to run on the main actor. It runs elsewhere and doesn't block the screen.
- **xctrace triage:** an xctrace command that scans a trace and flags the problems in it, a first-pass checkup.
- **Root cause:** the real underlying reason for a problem, as opposed to the symptom (the freeze).
- **Skills (agent skills):** packaged know-how an AI agent loads to do a specific job, like "read Instruments traces". Claude Code uses skills too.
- **Run (Instruments):** one recording session inside a trace file. One file can hold several runs, e.g. "baseline" and "after fix", side by side.
- **Commit:** saving a set of code changes into the project's history (git), with a note about what changed.
- **PR (pull request):** asking teammates to review your committed changes before they go into the main version.
- **Agentic coding:** letting an AI agent do multi-step coding work, like investigating, editing and testing, rather than just answering questions.
- **MetricKit:** an Apple framework that quietly collects your app's performance numbers on real users' devices and hands you a daily report, plus details when something breaks.
- **Metrics vs. diagnostics:** metrics are the regular numbers (launch time, hang time); diagnostics are the detailed reports sent when something goes wrong (a crash or hang, with a call stack).
- **Aggregate:** combine many measurements into totals or averages, e.g. hang time across all users yesterday.
- **Dashboard:** a page of charts showing those numbers at a glance.
- **Beta testers:** people who try the app before public release (often through TestFlight).
- **"27" releases:** Apple's 2027 versions of its operating systems (iOS 27, macOS 27).
- **XCTest:** Apple's testing framework, code that checks your code works (and, with `measure`, how fast it is).
- **Performance test:** a test that times a piece of code and fails if it got slower than allowed.
- **Regression:** something that used to work (or be fast) and got worse after a change.
- **Test coverage:** how much of your code is checked by tests. More coverage means fewer surprises.
- **Xcode Organizer:** a window in Xcode showing performance and crash data Apple collects from your App Store users (launch time, hangs, battery, crashes).
- **MCP Server (Model Context Protocol):** a plug-in that gives an AI agent access to a tool. The **Xcode MCP Server** lets agents like Claude Code use Xcode's data and actions.
- **Pipeline:** an automatic sequence of steps, e.g. collect data → agent finds issue → agent opens a PR → you review.
- **Thermals:** how hot the device gets.
- **Throttling:** the system deliberately slowing the device to cool it down, so your app suddenly runs slower.
- **Power vs. energy:** power is how fast energy is being used right now (like speed); energy is the total used over time (like distance). Heat follows power; battery drain follows energy.
- **Peak power draw:** the most power your app pulls at once. High peaks mean heat.
- **Average vs. floor power:** average is the typical draw while in use; floor is the minimum, what the app draws even when "idle". A high floor quietly drains battery.
- **Decode:** turning a compressed file (JPEG, MP4) into raw pixels the screen can show. It's real work for the CPU.
- **GPU:** the graphics chip that draws everything on screen. Powerful but power-hungry.
- **Metal:** Apple's way for apps to talk to the GPU (WebGL is the browser's version).
- **Radios:** the Wi-Fi, cellular and Bluetooth hardware. Waking them to fetch data costs a lot of power.
- **Subsystem:** one part of the device or software stack a feature relies on, like the CPU, GPU, display, Wi-Fi, Core Location or SwiftUI. Power problems are found one subsystem at a time.
- **Attribution (power):** the system tracking which app each bit of work was for, so the battery bill lands on the right app.
- **CPU frequency:** how fast the processor is running. Bursts of heavy work push it to top speed, which costs disproportionately more power and heat.
- **Core Location:** Apple's framework for GPS and location. One of the most power-hungry things an app can use.
- **Power floor:** see "Average vs. floor power". Small work that runs constantly (every frame, every second) keeps it high.
- **Backtrace:** the same as a call stack, captured at the moment of a problem so you can see what code was running.
- **Energy report (Xcode Organizer):** a report Apple collects from real users' devices when your app burns too much CPU in a short time.
- **Cache:** keep a result you already worked out, so you don't redo it next time.
- **Defer:** postpone work until it's actually needed (or until the device is idle or charging).
- **Algorithm:** the step-by-step method code uses to do something. A smarter one does the same job with less work.
- **AVKit:** Apple's ready-made, highly optimized video player. The web equivalent is the browser's built-in `<video>` element.
- **Frame deadline:** the time limit to draw each frame (8.3 ms at 120 fps, 16.7 ms at 60 fps). Miss it and the picture stutters.
- **fps (frames per second):** how many times a second the screen is redrawn.
- **ProMotion:** Apple's adaptive-refresh display that slides between slow and fast frame rates (up to 120 fps) to save power.
- **Metal debugger:** an Xcode tool for inspecting exactly what the GPU draws each frame and how long it takes.
- **GPU compute:** using the graphics chip for non-drawing number-crunching (e.g. effects, physics).
- **Over-specifying (frame rate):** asking the system for a higher frame rate than an effect needs, which wastes power for no visible gain.
- **CAFrameRateRange:** the Apple setting where you tell the system "this animation wants between X and Y fps, ideally Z".
- **UIKit:** Apple's older framework for building iPhone app screens; SwiftUI is the newer one. Both manage frame rate automatically.
- **Luminance:** how bright the pixels are. Brighter screens draw more power.
- **HDR (High Dynamic Range):** extra-bright, extra-contrasty video and images. Looks great, costs more power to display.
- **HDR backing surface:** an HDR-capable canvas an app draws into. Using one for normal content wastes power.
- **Dark Mode:** the system-wide dark color scheme. Apps that support it save a little power on some screens and help people who need it.
- **Average pixel luminance (APL):** a MetricKit number estimating how bright your app keeps the screen on average.
- **Frame Lifetimes (Instruments):** a track showing each frame from when it's drawn to when it leaves the screen, so you can see how often your app updates the display.
- **Continuous location tracking:** the app keeps asking "where am I?" all the time. The most expensive way to use location.
- **Region monitoring / geofence:** "tell me when the device enters or leaves this area". The system watches cheaply for you.
- **CLMonitor:** Apple's modern API for region monitoring.
- **CLLocationUpdate (stationary flag):** Apple's location-updates API. Its *stationary* flag says the person has stopped moving, so you can pause updates.
- **Power Profiler:** the Instruments template, also available as an on-device trace mode, that measures how much power your app uses, broken down by subsystem.
- **Location Energy Model:** an instrument inside the Power Profiler that estimates the power cost of your location use.
- **Developer Mode:** an iPhone/iPad setting that unlocks developer tools (needed to run your own builds and on-device traces).
- **Performance Trace (on-device):** recording a trace on the iPhone itself, no Mac attached, from Settings → Developer.
- **Control Center (recording a trace):** once Performance Trace is set up, a Control Center button starts and stops the recording, with no Mac or Xcode needed.
- **Sustained (elevated) power:** power that's a bit too high for a long time. It won't trigger energy reports (no spikes) but still drains battery.
- **Impact score (Power Profiler):** a relative number for how much power a subsystem (CPU, GPU, display) used. Only meaningful compared to another trace.
- **Swapped surfaces:** each time a finished frame is sent to the screen. 8.3 ms between swaps = 120 fps; 33 ms = 30 fps.
- **Flash Updated Regions:** an Xcode debug option that flashes yellow wherever the screen is redrawing, so you can spot unnecessary updates.
- **Paint Flashing (Safari):** the web version: Web Inspector highlights areas of the page as they repaint.
- **CADisplayLink:** an Apple timer that fires once per screen refresh, used to drive custom animations. Its `preferredFrameRateRange` sets how often.
- **Liquid Glass:** Apple's translucent, glassy UI material. It only redraws when the content behind it changes.
- **Forward compatible / future-proof:** written so it keeps working correctly if things change later (e.g. a new video frame rate).
- **Agent skill:** a packaged bundle of instructions, reference docs and examples an AI agent loads to become a specialist at one thing (e.g. SwiftUI). Xcode 27 ships with several; Claude Code uses the same idea.
- **SwiftUI:** Apple's modern framework for building app screens by describing what they should look like; the system handles the drawing.
- **Cell:** one row in a list (e.g. one pastry in the pastry list). Cells redrawing more than needed wastes work.
- **Scope creep:** a project slowly growing beyond what was planned, like a surprise map tab.
- **Data layer:** the part of an app that defines and stores its information (e.g. Tasting: pastry, place, date, rating) and how pieces relate. The screens sit on top of it.
- **Preview (Xcode):** a live mini version of a SwiftUI screen shown beside the code, updating as you type.
- **Entry point:** where an app starts running (e.g. `PastryTrackerApp`).
- **Navigation bar:** the strip across the top of an iPhone screen with the title and buttons like +.
- **View (SwiftUI):** one piece of the screen (a row, a button, a whole page) described in code. Its **inputs** (data passed in, state) decide what it shows, and a change to an input makes it **update**.
- **Observable (@Observable):** a SwiftUI data type that views can watch. When its data changes, the views using that data update automatically.
- **Store:** a common name for the object that holds an app's main data and hands it to the screens (here `TastingStore`).
- **Data flow:** the path data takes from where it's stored, through the views, to what's on screen, and back when you edit something.
- **Open Quickly (⌘⇧O):** Xcode's jump-to-anything search for files and code symbols.
- **Symbol:** a named thing in code, like a type, function or variable.
- **Iterate (ForEach):** go through a list of items one by one, e.g. making one row per tasting.
- **Unnecessary view update:** SwiftUI redrawing a view even though nothing it shows changed. Wasted work, and a common cause of sluggish lists.
- **Equatable:** a Swift label meaning "two of these can be compared with ==". It lets SwiftUI notice "same as before" and skip a redraw.
- **Conformance (protocol conformance):** declaring that a type follows a protocol (a set of rules) such as Equatable, e.g. `struct Tasting: Equatable`.
- **Diff:** a side-by-side or red/green view of exactly what lines changed in the code.
- **Compile / build:** turning the code into a runnable app; the agent does this to check its edit works.
- **Fresh context (new conversation):** starting a new agent chat so earlier topics don't distract it. Good when switching to a different task.
- **Modernize:** update older code to current recommended APIs and patterns (often shorter, faster and safer).
- **Code review:** reading code to spot bugs, risky shortcuts and better ways to do things. Agents can do a first pass.
- **Context window:** how much text an AI agent can hold in mind at once. Stuffing it with a whole codebase crowds out the details and makes it less sharp.
- **Localization:** making an app work in other languages and regions (translations, date and number formats).
- **Accessibility:** making an app usable for everyone, e.g. VoiceOver for blind users, larger text, enough color contrast.
- **Locale:** a person's language and region settings (e.g. Italian in Italy), which affect text, dates, numbers and currency.
- **App resizability:** making an app's layout adapt to any screen size or shape instead of assuming one iPhone size.
- **Model training gap:** an AI model learned from code written before its cutoff, so it may not know the newest APIs. A "what's new" skill fills that gap.
- **Document-based app:** an app built around opening and saving files (like Pages or a level editor).
- **App Intents:** Apple's way to expose app actions to Siri, Shortcuts, Spotlight and widgets.
- **Feedback Assistant:** Apple's official place to report bugs and request features (feedbackassistant.apple.com, also an app on Mac/iPhone).
- **Developer Forums:** Apple's public Q&A boards where Apple engineers answer developer questions.
- **Property wrapper vs. macro:** two Swift features for adding behavior to code with an @ label (like `@State`). In iOS 27 `@State` switched from one to the other, so some old code needs small fixes.
- **Compiler error:** a message Xcode shows when code can't be built, e.g. after an API changes.
- **Source compatibility:** whether old code still builds unchanged with the new tools.
- **Invoke (a skill):** call it by name on purpose, instead of waiting for the agent to decide to use it.
- **Agent harness:** the app around an AI model that gives it tools and skills (Xcode's coding assistant, Claude Code, etc.).
- **Business outcome:** a result the business cares about, like more sign-ups, longer sessions, purchases, or fewer people quitting the app.
- **Retention:** how many people keep coming back to your app over days and weeks.
- **Engagement:** how much people use the app (time spent, screens visited, features used).
- **Churn:** people who stop using the app (or cancel a subscription), the opposite of retention.
- **App Store Connect:** Apple's website for managing apps you publish: releases, sales, reviews and analytics.
- **Peer group benchmarks:** App Store Connect comparisons of your app's numbers against similar apps.
- **"Worth the squeeze":** worth the effort, i.e. does the result justify the work.
- **App Store Connect API:** a way for scripts (or an AI agent) to download your App Store Connect data automatically instead of clicking through the website.
- **Correlate:** two things tending to move together (e.g. players using a new feature and retention rising). Not proof one caused the other, but a strong hint.
- **Slice and dice:** break the same data down different ways (by feature, device, version, country…).
- **Hang rate:** how much hanging your app does, measured as seconds of hangs per hour of use.
- **Re-architect:** rebuild how a part of the app is structured inside, usually to fix deep problems (like performance) that small tweaks can't.
- **CLI (command-line interface):** a tool you run by typing commands in Terminal; agents can run these too.
- **xctrace show:** the xctrace command that reads any trace and explains the performance picture (vs. `triage`, which spots specific problems like hangs).
- **Agent in a loop:** letting an AI fix something, test it, see the result, and try again on its own until it passes.
- **Device farm:** a big setup of many real phones and tablets connected for automated testing, usually run by a team.
- **Directional (vs. absolute):** tells you which way something moved (better or worse) without exact real-world values.
- **Converge:** the agent's repeated tries settle on a result that's good enough.
- **Throughput:** how much data a connection moves per second; it's highest right next to your router.
- **GPU debugger (Metal debugger / frame capture):** Xcode tool that records every step the GPU takes to draw one frame, so you can see exactly what's slow or wrong.
- **Metal Performance Overview:** an Instruments instrument summarizing how hard the GPU is working.
- **visionOS / Compositor Services:** Apple Vision Pro's OS, and its API for drawing full 3D scenes with Metal.
- **Inference:** the AI model actually reading your input and producing an answer. Whatever goes into inference is sent to the model provider.
- **Data retention:** how long a provider keeps the data you send it, set by its terms and your plan.
- **On-device:** processed on your own computer, never sent anywhere.
- **Firebase Crashlytics / Sentry:** popular third-party services that collect crashes and performance problems from your users and show them on a dashboard.
- **SDK:** a ready-made code package from a company that you add to your app (e.g. Sentry's SDK).
- **Subscriber (MetricKit):** any part of your app that signs up to receive MetricKit's reports; several can share the same data.
- **In-process:** work done inside your app while it runs, which competes with the app itself for speed and battery.
- **Observability overhead:** the extra work (and slowdown) an app does just to monitor itself.
- **Thread:** one lane of work an app runs; apps use several at once (main thread for the screen, others for background work).
- **Spinning / busy-waiting:** a thread repeatedly checking "is it done yet?" instead of sleeping until told. Fast to react, wasteful of power.
- **Messaging / callbacks:** the waiting code is woken up when the other work finishes. Same speed, far less power.
- **Mental model:** your own picture in your head of how the code works, which you build up by asking questions and testing small changes.
- **Snapshot in time:** an AI model only knows what existed when it was trained, so newer APIs and practices may be missing.
- **Closure:** a small block of code you can pass around and run later (like an instruction card). Storing one in SwiftUI's environment causes hidden performance problems.
- **Environment (SwiftUI):** shared settings or data that flow down to every view in a screen.
- **Frontier (AI):** the newest, most capable AI models.
- **SwiftUI instrument:** an Instruments tool that shows which SwiftUI views update, how often, and what caused each update.
- **View body:** the code describing what a SwiftUI view shows; it re-runs on every update, so needless re-runs waste work.
- **Geometry:** sizes and positions of things on screen; it changes constantly during scrolling and animation.
- **onChange:** a SwiftUI hook that runs code when a value changes. Overusing it can trigger chains of big updates.
- **Swipe actions / reorderable:** list features (swipe a row for buttons, drag rows to reorder); new APIs for them shipped this year.
- **Regression (performance):** something that got slower or more power-hungry in a newer version.
- **Programmatic access:** getting data by code or script (an API) instead of clicking through a website.
- **Anecdotal:** based on individual stories and experiences rather than measured statistics.
- **Reproduction gate (repro gate):** a rule that the agent must first reliably reproduce a bug before it's allowed to fix it, and must show the bug is gone afterwards.
- **UI test:** an automated test that taps through your app like a person would (XCUITest).
- **Hitch:** a dropped or late frame while scrolling or animating, a visible stutter.
- **App switcher:** the screen where you swipe up to see open apps and can force-quit them.
- **Intersection (MetricKit):** combining two things, like "hitches" and "which screen was showing", to see hitches *per screen*.
- **Payload (MetricKit):** one batch of performance data MetricKit delivers (usually covering a day).
- **Synchronous (blocking):** work that makes everything wait until it finishes. Doing it inside a view body freezes the screen.
- **Debug vs. Release mode:** Debug builds include extra checking and run slower; Release is what customers get. Always measure performance in Release.
- **Scheme (Xcode):** the settings for how Xcode builds and runs your app (including Debug vs. Release).
- **Churn:** updating the same thing over and over, more often than needed.
- **Compiler optimization:** in Release builds the compiler rewrites code to run faster, sometimes skipping work that Debug would do. That's why Debug numbers can be misleading.
- **Symbols:** the readable function names in a trace or crash log (instead of raw memory addresses).
- **Third-party SDK:** code from another company built into your app (ads, analytics, login…). Its performance becomes your app's performance.
- **Static initializers:** code that runs automatically when an app (or SDK) loads, before your app even starts. Lots of it slows launch.
- **Launch time:** how long from tapping the icon until the app is usable.
- **iPhone Duo:** a new iPhone model mentioned throughout; apps need adaptable (resizable) layouts to look right on it.
- **Baseline (testing):** the "before" measurement every new version is compared against.
- **Tokens:** the chunks of text an AI model reads and writes; more tokens means more cost and slower answers. Huge XML trace dumps eat lots of them.
- **XML:** a verbose text format for data; big traces exported as XML get enormous.
- **Bounds checking:** making sure code never reads or writes past the end of a block of memory, a common source of crashes and security holes in C.
- **Compositor:** the system component that layers your app with the status bar, other apps and system UI into the final screen image.
- **Compositor Fast Path:** a debug view showing whether your content takes the cheap, efficient route through the compositor (great for video).
- **dSYM:** a file that maps compiled code back to function names, so traces and crash logs are readable.
- **Allocations / Leaks / VM Tracker:** Instruments tools for memory use, leaked memory and virtual memory.
- **XCTHitchMetric / XCTApplicationLaunchMetric:** XCTest measurements for animation stutters and launch time in automated performance tests.
- **Caches / tmp directory:** folders for files the system may delete when space is low; use them for anything you can re-download or rebuild.

## Follow-ups for Señor Crabb
- [ ] **Signposts in the Slideshow** (asked 10:52 AM): time slide loads, the PixelFLEX drawing and video start with `performance.mark`/`measure` (the browser's signposts), so Safari's Web Inspector timeline shows where the time goes.
- [ ] **Try Apple's exported xctrace skills in Claude Code** (from the 10:59 segment): they'd let me read Instruments traces directly. They need Xcode installed, and they're for Mac/iPhone apps rather than Safari pages.
- [ ] **PixelFLEX power floor:** the wall already redraws only when the picture changes, but its loop still wakes **every frame** to check (and reads the page's styles each time). Let it **sleep while a still photo is up** and wake on the next change, and redraw a playing video at the video's own frame rate rather than the screen's.

## Follow-ups for the games (Monkey Trubble, Poly Oracle, and more)
- [ ] **Monkey Trubble iOS** (on the games machine): profile on a real iPhone with **⌘I → Time Profiler**, with **Hang Detection** on (Settings → Developer). Record a **baseline** of gameplay, level loads and menus.
- [ ] Add **signposts** (OSSignposter, Points of Interest) around level loading, asset/sound loading and any big per-frame work.
- [ ] Use **state reporting** for game modes (menu, playing, paused, cutscene) and feature flags, so traces and MetricKit show which mode was slow.
- [ ] Add **MetricKit** to get daily hang/launch/memory reports from TestFlight testers and players.
- [ ] **Poly Oracle** (on the games machine): same checklist.
- [ ] Android version: Android has its own tools for the same jobs (Android Studio Profiler, Perfetto traces).
- [ ] Write **XCTest `measure` performance tests** for slow game code (level load, save), and connect the **Xcode MCP Server** so Claude Code can use Xcode's performance data.
- [ ] **Frame rate:** let the frame rate drop on menus and paused screens (don't hold 120 fps when nothing moves), and use the **Metal debugger** to check frame deadlines in busy scenes.
- [ ] **Power trace on a real phone:** Settings → Developer → Performance Trace → add the game → **Power Profiler** mode. Then play a normal session and check which subsystem (CPU, GPU, display) burns the most.
- [ ] **Hunt for 120 fps idle animations** (monkey/character idles, menu sparkles) with **Flash Updated Regions** (Debug → View Debugging → Rendering). Cap them to the content's rate with `CAFrameRateRange`, like the cat-tail fix (GPU impact 1.0 → 0.1).
- [ ] **Equatable check:** for any SwiftUI list or HUD that redraws too often, make sure the data types it shows are `Equatable` so `@Observable` skips no-change updates (the pastry-list fix).
- [ ] **Agent code review:** in a fresh conversation, ask "review [screen/feature] for best practices and opportunities to modernize" (with the SwiftUI skill), starting with anything built in a hurry.
- [ ] **Export Xcode 27's skills to Claude Code** with the `xcrun` command from the SwiftUI talk (ask Claude on the MacBook to find it in `xcrun` help), so Claude Code gets the SwiftUI specialist, what's-new-in-SwiftUI-27 and testing skills too.
- [ ] **After each performance update, check App Store Connect** (retention, engagement, churn for that version) and the **peer group benchmarks** for similar games, to see if players noticed.
- [ ] **GPU capture for Claude:** in a heavy scene, capture a frame with Xcode's **Metal/GPU debugger** and give the capture file to Claude Code to analyze (Apple says agents can now read these).
- [ ] **SwiftUI instrument pass:** profile Monkey Trubble's menus and HUD with the SwiftUI instrument; for any view updating too often, ask Claude (with the SwiftUI skill) why, and watch for geometry or closures in the environment and heavy onChange blocks.
- [ ] **Launch-time test:** add an XCTest that measures app launch, and run it before every release (especially after adding an SDK).
- [ ] **iPhone Duo readiness:** run the **app resizability** skill on Monkey Trubble and Poly Oracle (covers SwiftUI and UIKit layouts).
- [ ] **Token-wise trace reading:** tell Claude to run `xctrace triage` first and `xctrace show` only on what it flags; never dump whole traces to XML.
