# Apple Developer Q&A: Boost your app's speed and efficiency (Oct 29, 2026)
Scraped from the live event's public Q&A feed. Apple staff answers are marked 🍎.

## Q (9:49 AM, ▲3, discussed): Yup best tip in XCode for checking performance
- **🍎 Developer Tools Engineer** (10:03 AM): A great place to get started is to go to Product → Profile to do a release build and open Instruments. Then, choose the Time Profiler template. While running a recording of your app on a physical device, navigate through some common user flows. Then, check for hangs in the Hangs track and use right-click → Set Inspection Range to focus the Time Profiler instrument on those hangs. From there, you can explore the call tree and flame graph to identify which functions are responsible for the hangs.
- **dev** (10:05 AM): is there a way i can measure the memory and CPU work a specific screen is consuming?
- **🍎 Developer Tools Engineer** (10:12 AM): You can use the StateReporting API to identify the currently active screen, then use the Points of Interest instrument to visualize that information alongside Time Profiler. You can also add the Points of Interest instrument to the Allocations template. We don’t recommend using the Allocations and Time Profiler in the same recording, because Allocations adds some overhead to memory allocations that can make false CPU performance issues appear in Time Profiler.
- **dev** (10:17 AM): Do use AI with the XCode tools to find and fix performance issues.
- **🍎 Developer Tools Engineer** (10:20 AM): We’ll definitely be talking more about that in upcoming sessions today — stay tuned!
- **dev** (10:22 AM): Claude was able to use the old iPhone simulator but with the recent updates to the device hub it no longer can. Is that intentional? If so, is there a recommended way to allow Claude to check it's own work?
- **🍎 Developer Tools Engineer** (10:23 AM): I’m not a Device Hub expert but that sounds like a great thing to report in Feedback Assistant!
- **dev** (10:26 AM): Wishful thinking. A button on XCode that is "Find and fix performance issues"  🤣
- **dev** (10:37 AM): I hope this is being recorded, I'm going to want to watch this again.
- **dev** (2:32 PM): Thank you so much!

## Q (9:58 AM, ▲2, open): Each cell of a 7×7 (49) or 12×12 (144) is a small USDZ that should spin on its own Y axis. One SCNView per cell deadlocks macOS SceneKit (layout stuck on the shared irradiance lock). We cap live views at 12. How do we spin every cell efficiently with one shared scene instead of one view per cell?

## Q (10:04 AM, ▲3, dismissed): Welcome developers! Please submit your questions throughout the event today. We have a room full of Apple engineers ready to field your questions and we'll do our best to answer your questions. There will be a Live Q&A starting at 1:30 as well.

## Q (10:05 AM, ▲18, discussed): Can we expect some better MCP tools for Instruments so that we don't have to dig into thousands of frames ourself and AI can find issues in the recorded session?
- **🍎 Developer Tools Engineer** (10:20 AM): Hi! Stay tuned for our upcoming “Solve the tougher problems” talk later today. We’ll be happy to answer any additional questions you have in this area after that session :)

## Q (10:14 AM, ▲8, discussed): Some performance bottlenecks are behavioral in nature. Does Apple publish data around retention/engagement rates for, say, long/animated Splash animations, that delay app startup by 5-10 seconds? This sort of data can help bridge technical + business discussions and advocate for something better.
- **🍎 Developer Tools Engineer** (11:07 AM): Currently Apple doesn't provide engagement-related analytics. However, MetricKit in the 27 releases can report power and performance metrics and diagnostics that carry app states. Doing so, you can track your app's performance by specific app configurations. See documentation: https://developer.apple.com/documentation/metrickit/track-performance-by-app-state-using-metrickit

If you believe that what we currently provide is not sufficient to your use case, please feel free to file a feedback specifying your asks and post it here, thanks!

## Q (10:15 AM, ▲11, discussed): An app’s download size can be just 250 MB, yet its documents, user data, and cache can grow to several gigabytes over time. How can developers prevent this storage growth and let users reclaim space without losing personal data or having to delete the app?
- **🍎 DTS Engineer** (10:29 AM): A lot of the answers here depend on what's driving the data growth.   For example, having lots of data in Caches isn't really a problem on a device that's basically "empty.”   The main issue here is that the system will delete all of your data when it clears the folder, so there can be some value in limiting your growth so that the accumulation of old data doesn't end up getting useful data deleted.

However, for everything else, the basic answer is that you need to decide what the best way to manage it is.  For some apps, that could be as simple as storing the data in "Documents" and letting the user delete whatever data they want.  Other apps are better off managing the data on the user’s behalf, deleting it as needed.
- **🍎 Developer Tools Engineer** (10:38 AM): Placing files in the appropriate directories, such as the cachesDirectory and temporaryDirectory (see File System Basics: https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html), allows the system to intelligently manage and purge content when necessary, ensuring optimal disk space utilization and a better user experience.
You can gain insights into how the operating system manages your app’s cached content in the field, by inspecting MetricKit's storage-related MetricResults, such as MetricResult.totalFileSize(:). See MetricKit documentation: https://developer.apple.com/documentation/metrickit/metricresult

## Q (10:17 AM, ▲3, discussed): If we compile shared business logic into a framework from another language, what are the most common performance or efficiency pitfalls you see, and which Instruments templates would you use to catch them?
- **🍎 Developer Tools Engineer** (10:27 AM): If your language compiles directly to native code, you should be able to have the compiler export a dSYM file which will allow you to see function and method names in Time Profiler. For interpreted languages like Python or JavaScript, there is no way for Instruments to capture call stacks to show in Time Profiler, so you may be better off using a dedicated profiling tool for that language.

## Q (10:19 AM, ▲4, dismissed): Is it possible to view the organizer in a web tool instead so more of my team can see it as well without having Xcode or access to it?
- **🍎 Engineer** (10:27 AM): The metrics and diagnostics shown by Xcode Organizer are also available via the App Store Connect API: https://developer.apple.com/documentation/appstoreconnectapi/power-and-performance-metrics-and-logs

Using that API, you can build and customize your own views of the data to best fit your needs.

## Q (10:19 AM, ▲2, discussed): Our Mac app (RocketTrace) lets agents record and analyze xctrace traces efficiently. SwiftUI exports are either body-only or huge: 96% of rows in one hang were unlabeled generic updates. What's the recommended way to get lightweight, view-attributed SwiftUI update data?
- **🍎 Developer Tools Engineer** (10:40 AM): Unlabeled events sound like something that could be a bug. Please report this (ideally with an example trace) using Feedback Assistant so we can take a look.

There is no way to filter the recording to only view body updates. The goal of the SwiftUI instrument is to capture all the other kinds of updates besides view body updates, because the updates are ultimately a consequence of the views and modifiers you use in your view bodies. So even if your actual view body runs quickly, mistakes that cause it to update too frequently can cause substantial downstream work inside of SwiftUI.

## Q (10:20 AM, ▲0, open): Is there, or will there be, a supported export of shader profiler and counter results from a frame capture for AI analysis?

## Q (10:20 AM, ▲1, discussed): I'm working on an Endpoint Security extension in Swift, and I find that a lot of my extension's CPU time is spent in converting responses from the framework into Swift strings. 

Do you have any suggestions for working efficiently with C strings generally, or esstringtoken_t in particular?
- **🍎 Engineer** (10:22 AM): What approach are you currently using to convert between C and Swift strings?
- **dev** (10:26 AM): The original author used the obvious path here, adding an extension to esstringtoken_t that does String(cString: self.data). In the other direction, we're using implicit conversions from Swift Strings to UnsafePointer<CChar> when calling into ES APIs.
- **dev** (10:27 AM): argh. es  string  token _ t is getting italicized...
- **dev** (10:29 AM): Maybe if I "code" quote it? esstringtoken_t
- **dev** (10:33 AM): I could clearly just convert anything coming in from external sources directly to the ES string type, and then hand-roll comparison, prefix, and suffix operations. I may try that, if there's nothing obvious that would make this work better...
- **🍎 DTS Engineer** (10:42 AM): FYI, one of the reasons esstringtoken_t exists is to let you use C's safe string manipulation APIs like strncmp (instead of strcmp).   Leaning into that approach instead of using Swift strings isn't a terrible idea.  

Keep in mind that there are some very weird edge cases caused by things like the difference in how our string types handle Unicode normalization and how each file system does.  There's a lot to be said for treating file system paths as a "raw" data type that you try to avoid interacting with instead of converting in and out of our higher-level string types.
- **🍎 Engineer** (10:43 AM): Are the C strings you’re converting particularly long? init(cString:) ultimately has to do the equivalent of strlen, which can take up time for long strings.
- **dev** (10:51 AM): They're typically filesystem paths and wildcard patterns, so typically on the order of <100 characters. But we're storing them internally as Swift strings, then doing various matching and prefix/suffix checks there. So, thousands of times a second, we're getting events from Endpoint Security, converting 1 to 3 strings to Swift strings, then doing processing on them there. And yes - doing strlen on a token where we already have the length is just a waste of time. There isn't a "trust me, this C-style string buffer is N bytes long" API that I missed somewhere, is there? All paths coming from ES are in filesystem-canonical UTF-8, so it would be nice to have a fast path.
- **🍎 Developer Tools Engineer** (10:55 AM): You could consider using the FilePath type from the System framework — it might have different performance characteristics due to being focused on file paths specifically.
- **🍎 DTS Engineer** (10:57 AM): So, the problem here isn't actually the length, it's the validating the unicode format.    None of our initializer have a "this input is valid", so every conversion is going to look at every single byte.

I think you may want to think about this from the other direction, converting your Swift strings in to esstring's and then doing comparisons through the C APIs.
- **dev** (10:59 AM): Yeah, it's just going to be a LOT of work to undo all of the string handling :-)
- **🍎 DTS Engineer** (11:00 AM): And, no, I don't think FilePath will change much.  Again, the fundamental issue here is that all of our string methods are going to validate their input, but that validation is the one thing you don't need, since the kernel did a better job of that than you could.

## Q (10:22 AM, ▲1, discussed): My Organizer it does not show any information for any of my apps and versions.
- **🍎 Developer Tools Engineer** (10:27 AM): To view historical app data in Organizer, the app must have released a sufficient number of prior app versions and must have an adequate sample size. If your app is on its first or second version—or if the sample size is currently low—those could be reasons that Organizer has not shown information yet.
- **🍎 Developer Tools Engineer** (10:28 AM): From the docs: "In some cases, the pane shows “Insufficient usage data available” because there may not be enough anonymized data reported from participating user devices. When this happens, try checking back in a few days."

https://developer.apple.com/documentation/xcode/analyzing-the-performance-of-your-shipping-app
- **dev** (10:30 AM): Thanks 😉

## Q (10:23 AM, ▲1, open): What's your recommendation for uniquely identifying MetricKit payloads and reports? With the new MetricReport and DiagnosticReport one could wrap the type and add an identifier, but it would be great if it was built in for all.

FB23023840 (MetricKit: Add 'id' or 'identifier' to the Report types)

## Q (10:24 AM, ▲0, discussed): In Organizer, with the recommended metric (Recommended hang rate/hr, etc.) is that based on just the app history and other apps, or does it analyze the code as well?
- **🍎 Engineer** (10:28 AM): The code is not analyzed to produce the recommendation

## Q (10:25 AM, ▲0, discussed): xctrace export has no time-range option for .trace files, so we export whole tables for RocketTrace. One SwiftUI table was 2.6 GB. Is range-limited or streaming export planned for tooling?
- **🍎 Developer Tools Engineer** (10:59 AM): xctrace show supports filtering by time  for any of the detail views it allows exporting for. Note that it does not support the Object Graph, but it does support the other detail views.

## Q (10:25 AM, ▲4, open): I’m optimizing my Metal code and want an AI assistant to analyze my GPU counters and shader profiler results. What’s the best way today to get that data out of Instruments and Xcode so an assistant can read it? Is there a data export or an MCP interface?

## Q (10:25 AM, ▲2, discussed): Hitches isn't supported in Simulator, so the built-in SwiftUI template can't record there. Will Simulator or Device Hub get hitch support, or should developers always use a physical device for animation work?
- **🍎 Developer Tools Engineer** (10:49 AM): We always recommend using a physical device for profiling because the Simulator environment is very different from a real device in ways that can affect performance both positively and negatively.

You can remove the Hitches instrument from the template and record without it if you need to profile a simulated device.

## Q (10:26 AM, ▲0, discussed): do all devices emit these metrics/logs automatically (so they appear on Organizer) or does the user need to explicitly enable "send metrics to apple" ?
- **🍎 Engineer** (10:35 AM): Users must have 'Share with App Developers' analytics privacy setting enabled on their device in order for the metrics to be sent to Apple and shown in Xcode Organizer.

## Q (10:30 AM, ▲4, discussed): I want an AI assistant to help analyze my SwiftUI instrument traces. Today xctrace export gives me XML with undocumented schemas, and Xcode’s MCP server has no tool for traces. What’s the recommended way to get trace results to an assistant?
- **🍎 Developer Tools Engineer** (11:07 AM): Check out our new xctrace show command!
- **dev** (1:38 PM): I do that by simply saving the gpu trace from xcode, or the instruments trace and point an agent to it. Most know enough of the built in CLI tooling to extract pertinent information w/o MCP tools needed (in my experience) both claude and codex generally work with traces with no issue and can extract pertinent observations.

## Q (10:33 AM, ▲3, discussed): The Xcode organizer presents data from my users.
Can the organizer also present data from my own debugging sessions so that I am able to collect data before shipping the first version of my app?
- **dev** (10:42 AM): I am dealing with the same issue. I would prefer a way to collect data from my own debugging session, before I ship first version.
- **🍎 Developer Tools Engineer** (10:45 AM): At this time, Organizer supports anonymized field data. To collect local data from debugging sessions, check out the  Performance Tests API. With Performance Tests, you can measure for key metrics like XCTHitchMetric or XCTApplicationLaunchMetric, set baselines to compare multiple test runs, and more.

Docs: https://developer.apple.com/documentation/xcode/writing-and-running-performance-tests

## Q (10:34 AM, ▲1, discussed): does power trace work for watchOS also?
- **🍎 Developer Tools Engineer** (10:37 AM): Power Profiler only supports running on iOS and iPadOS. Please describe your use case in Feedback Assistant so that we can prioritize your request!

## Q (10:40 AM, ▲1, discussed): Hi Apple Engineers! My app uses Vision to extract text from photos of educational worksheets. I'm trying to optimize the processing time for high-resolution images. Which Instruments templates or metrics do you recommend to pinpoint bottlenecks specifically during Vision framework requests?
- **🍎 Developer Tools Engineer** (10:42 AM): There aren’t any instruments available for the Vision framework specifically (please use Feedback Assistant to request this so we can help the team prioritize adding one!), but you can always start by looking at Time Profiler to see if there is anything you can optimize on your side of the processing logic.

## Q (10:40 AM, ▲1, discussed): Hello! We generate and render complex PDFs in our app. What are the best practices using Instruments to track down memory spikes when rendering multiple PDF pages or large images, especially on older iOS devices?
- **🍎 Engineer** (10:48 AM): This document contains some good guidance to get started: https://developer.apple.com/documentation/xcode/gathering-information-about-memory-use
TLDR Use Xcode’s memory report, Debug memory graph, and the Allocations instrument. Are you looking for more specific advice?

## Q (10:42 AM, ▲4, open): I appreciate the privacy-preserving opt-in model for users to share their MetricKit and other diagnostics reports with Apple. Can Apple build on this foundation to figure out how to represent diagnostics of users who don't opt-in, for example as aggregate or less-granular data?
- **🍎 Developer Tools Engineer** (11:51 AM): Metrics and diagnostics in Xcode Organizer are gated behind the "Share with App Developers" privacy setting. MetricKit data however is not, as the data does not get processed by Apple. Therefore, you're in control deciding how and when you're collecting MetricKit data from your customers.
- **dev** (1:36 PM): Could you clarify on this. My understanding is that MetricKit metrics are aggregated and thus upsampled by Apple, but diagnostic payloads ARE sampled by Apple. Is that correct?
- **dev** (1:38 PM): "UN-sampled", not "UP-sampled"
- **dev** (2:02 PM): MetricKit is single value on device over a reporting period. Some values are averages, others are histograms. You need to handle with getting the payloads and new report types off device but you’re fully in control.
- **dev** (2:16 PM): I find these answers confusing because they seem to mix privacy controls, aggregation, and sampling, which are three different concerns. Can Apple clarify whether MetricKit diagnostic payloads are sampled, whether every eligible diagnostic is delivered to the application, and whether that behavior differs between diagnostic types? The distinction is important when using MetricKit data to assess application reliability.

## Q (10:44 AM, ▲3, open): Just wanted to confirm - Is the organizer performance data only available for App Store distributed apps?
- **dev** (11:10 AM): Users also get to opt-in when they setup a device, or MDM can disable it so keep that in mind. Public, unlisted, and custom apps should all produce data, including TestFlight builds as far as I know.
- **dev** (11:17 AM): Thanks @SwiftNativeDeveloper

## Q (10:50 AM, ▲2, discussed): What resources would you recommend for learning more on how to use the corpse port in CrashReporterExtension? If another off the shelf crash reporter is already used, what might be useful information to read from the port?
- **🍎 Engineer** (11:08 AM): Hello, thank you for your message. 

Crash Report Extension provides a great way for developers to reliably inspect and obtain more information about a crash. The corpse port is most useful for information an in process reporter can't collect reliably, such as the stacks of all threads, the memory around the crash address, and your app's own state at the time of the crash.

Our developer documentation on Crash Report Extension (https://developer.apple.com/documentation/CrashReportExtension) is the best place to get started and learn more.

## Q (10:53 AM, ▲0, open): I use an AI that analyzes raw video footage, cuts out anything not animal specific. It then titles the clipped moment and tags it for fast search and share whenever. As you can imagine, raw 4k footage passing through so many steps, is likely to have issues. Need to be able to really on device more.

## Q (10:57 AM, ▲2, discussed): For thew new show and triage methods:
- Is there a structured output format (like JSON)? 
- Is the text format stable?
- Do they work with traces from older Xcode versions?
- **🍎 Developer Tools Engineer** (11:04 AM): There is not a structured output format like JSON, but please let us know what you would need to support your workflow via Feedback!

xctrace show will work with traces from previous Instruments/Xcode versions. However, xctrace triage may want to extract data that is not available in older trace files, so some of the summaries it provides may be omitted.

## Q (10:58 AM, ▲1, discussed): What does the new triage command cover besides hangs, and which instruments does 'show' support?
- **🍎 Developer Tools Engineer** (11:02 AM): Hangs is the only supported triage mode at this time (but we’d appreciate receiving feedback on additional triage modes you think would be helpful!). 'show' supports all instruments except the Allocations, Leaks, and VM Tracker instruments.

## Q (11:04 AM, ▲0, open): So we can just add these xctrace commands in pipelines and can get the PRs created for the fixes to review?

## Q (11:07 AM, ▲1, open): Our app Picolate turns an iPad into a photo booth-style camera for events, running 4–6h unattended. Its front AVCaptureSession stays on between guests for instant countdowns. Keep it running or stop it while idle? And how best to catch thermal or memory degradation that only shows up after hours?
- **🍎 Engineer** (12:00 PM): The decision to keep the session running or pause it depends on a few factors. Is the device plugged into power? Do you have sufficient signals to start pre-warming the session before it is needed the next time, to meet your latency targets for starting the countdown? Have you observed thermal issues running for this long?

For detecting issues in long running sessions, you could poll for thermal issues such as via ProcessInfo.thermalState

Additionally, you can use Power Profiler to record long running Instruments traces when away from desk, which can surface energy and thermal issues over time. More information at https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler

Memory issues are often observable even in short sessions, at a much lower magnitude, and can be measured via XCTest. You can write a test that measures XCTMemoryMetric while your app goes through a workflow once or twice.
- **dev** (12:22 PM): Thank you for the detailed answer! No thermal issues so far: an event on an older iPad ran on power without problems, and on an iPad Pro 13" M1 on battery we measured about 5% drain per 20 minutes, so keeping the session running seems fine. We start the session only once, when the first countdown begins, and keep it running afterwards. What we occasionally notice is a short lag until the preview appears on that first start. Since guests tap the start screen and pick a mode before the countdown, we’ll try pre-warming the session there. Is there anything else that reduces the initial startup latency, e.g. configuring the session early and only calling startRunning() later?
- **dev** (12:25 PM): P.S. Our AI product owner Paula has already drafted a ticket for the measurements – your answer went straight into the backlog. :)

## Q (11:07 AM, ▲2, open): are there benchmarks/industry standards for hangs/scroll performance, crash rate, app launch times?
- **dev** (11:42 AM): I dunno about benchmarks, per-se. But having worked on a few MacOS and iOS applications with millions of active users: Your crash rate should be very close to zero crashes, per active user, per year. With a large-enough userbase, you can never hit zero, particularly on the Mac, where conflicts with other software, and devices with failing hard drives are...a thing.
- **🍎 Engineer** (11:44 AM): Some metrics in Xcode Organizer support similar-app goals. These goals provide actionable recommendations based on aggregate metrics of other apps that have functional and technical similarities to your own.

Additionally, certain metrics like hitches (for scrolling and other animations) have recommended ranges for good/warning/critical/etc performance. More information about these hitch specific recommendations at https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app
- **dev** (2:20 PM): whats best way to
 get real crash rates before release?

## Q (11:09 AM, ▲1, open): Apple recommends not using materials on top of moving content / videos. Does the same apply to sheets with Liquid Glass that go on top of videos?

## Q (11:12 AM, ▲0, discussed): Should automated performance tests be run on a real device to be accurate?
- **🍎 Developer Tools Engineer** (11:27 AM): Yes, it’s always best to run your test on a physical device to be sure that you’re matching the experience your end users will have.

## Q (11:27 AM, ▲0, open): bonjour
Je voulais savoir s’il était indispensable de maîtriser le langage de programmation Swift pour pouvoir créer des applications.

I wanted to know whether it is necessary to master the Swift programming language in order to develop applications.
- **dev** (12:20 PM): C'est mieux pour comprendre, mais en ce moment les agents IA ce sont tellement perfectionner que tu peut lancer ton projet sans t'y connaitre et te fier à ce que l'IA te dit.

It's better to understand, but right now AI agents are so perfecting that you can launch your project without knowing it and rely on what AI tells you.
- **dev** (12:35 PM): You still need to guide adequatly your agent, understand what's possible, what Apple offers, what / how to conceptualize your ideas. You may not need to know the technical language but the big picture is needed.
- **dev** (1:55 PM): Could we trust claude agent? it told me it fixed the memory issue of my DEXT driver, after running the test for 400 hours, its memory increased from 8MB to 140GB(certainly it is using the harddrive since it is 8GB M1 Mac mini), what is the good tool to investigate while Instruments(Xcode 27.1) says no memory leak on short period running?

## Q (11:30 AM, ▲0, discussed): Will this presentation be available to rewatch?
- **🍎 DTS Engineer** (11:35 AM): Yes, this event will be available as a video on demand (VOD).

You can find it on the Apple Developer website/app here: https://developer.apple.com/videos/play/meet-with-apple/284/

## Q (11:34 AM, ▲0, open): What are the proper steps to take when a performance investigation identifies the issue is an underlying issue in the OS and not our app? Follow up - if you've already submitted the issue in Feedback Assistant, and it has not been resolved for multiple years, what do you do?

## Q (11:34 AM, ▲0, open): I’m a Mac dev with both App Store and non-MAS distributed apps. Unfortunately, access to data, even for App Store apps, is heavily limited compared to iOS apps. What are my best options for gathering data without third-party solutions, relying only on Apple-provided mechanisms?
- **dev** (1:41 PM): MetricKit. Check it out. You can get diagnostics, but not metrics. Submit a feedback to ask for the MetricReport to materialize for macOS. 

Here is mine: 

FB9069616 (Make MetricKit available for other Apple platforms)

## Q (11:37 AM, ▲1, open): After distributing our iOS app, Xcode Organizer shows scroll hitch metrics only as an overall figure for the whole app. Is there a way to see which individual screens (e.g., 10 different screens) are contributing to poor scrolling performance, instead of one aggregate number? If Organizer and Metric

## Q (11:37 AM, ▲0, open): Is there a way to rewatch a part of the stream? Internet was not working when covering the agentic tools + organizer
- **🍎 Engineer** (11:41 AM): You can replay the event after it ends at https://developer.apple.com/videos/play/meet-with-apple/284/

## Q (11:38 AM, ▲0, open): Organizer shows scroll hitch rate only app-wide. Can we get it broken down per screen from production users? If not, what’s the recommended way to measure it per screen (MetricKit signposts, CADisplayLink)?

## Q (11:47 AM, ▲0, open): We generally can’t use Xcode for our IDE due to perf issues at the multi-million LOC scale. Are there any perf features we’re missing out on by only using the MCP and CLI tools?

## Q (11:50 AM, ▲0, open): Hello, how can we make sure MKHangDiagnostic payload data is not truncated? The payload we receive seems to be incomplete likely due to nested stack frames. 
Would appreciate if you can help us figure it out.

## Q (11:54 AM, ▲1, open): How can we isolate a main-thread hang in Instruments when ios 18 shifts background workloads to efficiency cores? Any tips to prevent SwiftUI frame drops during low-power transitions?

## Q (11:56 AM, ▲0, open): There are a lot of profiling tools in Xcode Instruments, is there a good place to learn the basics of each of the tools especially for apps on Mac
- **dev** (12:09 PM): Some quick start guides would be very helpful

## Q (11:58 AM, ▲0, open): What security and privacy guarantees do tools like xctrace triage provide when used on non-public code?
- **🍎 Developer Tools Engineer** (12:01 PM): xctrace triage runs entirely locally, and does not upload your data anywhere. Of course, when you have your coding agent of choice run the command, the outputs it provides will be sent to your coding agent!

## Q (12:04 PM, ▲0, open): Thanks for the new JSON project format, and open sourcing the specification. Diffs are way easier to review as a human. What can you share about how this boosts the agentic workflow productivity, including in updates within the Xcode Tools MCP?

## Q (12:10 PM, ▲0, open): Does the coding model run locally? There could be privacy issues related to working with client code and sending code to a third party (OpenAI / Claude / etc)

## Q (12:13 PM, ▲0, open): What was the shortcut to open the coding assistant next to a file?
- **🍎 Frameworks Engineer** (1:07 PM): It's ⌘⌥⌃⇧H

## Q (12:19 PM, ▲0, open): I'm looking for tips on how to apply what we've seen to visionOS development.

## Q (12:35 PM, ▲0, open): Which Instruments template and counter configuration would help distinguish GPU clock/power-state changes from resource waits, preemption, or memory-bandwidth stalls and preserve normal GPU power management during the capture?

## Q (12:37 PM, ▲0, open): We allow only one command buffer in flight and clear its busy gate through a MainActor task after completion. Could that scheduling pattern affect GPU power management or cause frame-rate cliffs, and what should we measure to establish that?

## Q (1:28 PM, ▲0, open): Media app, SwiftUI: home feed is one view with a 25-case switch over module types in an eager VStack in a ScrollView, driven by ObservableObject with ~350 @Published. Before migrating to @Observable, where would you put 3 signposts, and which Instruments track separates observation cost

## Q (1:30 PM, ▲0, open): My team recently moved away from SwiftUi in favour of UiKit for list cells because despite using instruments and following resources, we could not address the performance issues (hitches on scroll). Is that sometimes the case for lists with a lot of media (photos, video) or is SwiftUI suitable?

## Q (1:30 PM, ▲1, open): Shefali said profile on device, not simulator. For a coding agent that runs xctrace triage in a loop to verify its own fix, what's the practical way to get a repeatable device trace in CI? Is there any trace data you'd trust from the simulator?

## Q (1:32 PM, ▲0, open): Adenine's demo found a CADisplayLink pinned at 120 fps. Our video playback and ad SDKs are closed source. Can we detect from outside an SDK that it over-specifies preferredFrameRateRange, and can the host app clamp it?

## Q (1:37 PM, ▲0, open): Joel's fix was marking a function @concurrent. In a large project still on Swift 5 language mode with strict concurrency off, is that annotation safe to apply broadly, or does it only behave as intended under Swift 6 mode?

## Q (1:38 PM, ▲0, open): A lot of the performance gains and fixes have been attributed to fixing/touching up source code. What about recommended methods for binary optimizations to resolve similar performance issues, or reach similar gains? Such as compiler optimization flags, order files, etc.

## Q (1:39 PM, ▲1, open): Are there differences between using Apple specialist skills in Xcode compared to exported in a separate AI app like Claude or Codex?
- **dev** (2:04 PM): During the developer conference I asked something similar and the gist was that some of the tooling around localization was only available in the app and supported agent harness. Ask for the skills in Xcode compared against the exported ones. I am not remembering the second one that had less powerful behavior when exported.

## Q (1:41 PM, ▲0, open): Do you collect real-time performance analytics from your apps at Apple? How do you do that? MetricKit provides aggregated data. I need to be able to make a decision to stop a release if I see millions of our users experiencing a hang rate degradation. I must do this same day/hour when I get a signal

## Q (1:43 PM, ▲3, open): After migrating to UIScene APIs, we can’t know the app was launched in foreground or background by accessing applicationState property of UIApplication. Any possible way to get this information as early as possible? Thus we could schedule tasks at launch stage more reasonably.

## Q (1:44 PM, ▲0, open): With Xcode removing device support, what do you recommend developers do if they want to reproduce issues with breakpoints on earlier os versions? Minimum with Xcode 27 is iOS 17 now.

https://developer.apple.com/xcode/system-requirements

## Q (1:46 PM, ▲1, open): The event description mentions using coding agents. Since raw xctrace XML is too large for LLM context windows, what is Apple’s recommended workflow today for exporting and filtering trace data so an agent can successfully analyze a CPU bottleneck?

## Q (1:49 PM, ▲0, open): We ship Firebase Crashlytics and are considering Firebase Performance. Does MetricKit overlap or conflict with those SDKs (duplicate hang/crash capture, extra launch cost)? Would you run MetricKit alongside them or pick one?

## Q (1:52 PM, ▲0, open): Can we expect some better MCP tools for Instruments so that we don't have to dig into thousands of frames ourself and AI can find issues in the recorded session?

## Q (2:00 PM, ▲0, open): Roughly how many opted-in devices does the launch or hang metric need before Organizer shows anything, and does TestFlight usage count toward it?

## Q (2:02 PM, ▲0, open): Can you talk a bit more how to setup an automatic pipeline to measure a performance regression before a new version release? I would be interested in attending other sessions in depth for more advanced usages.

## Q (2:02 PM, ▲0, open): Is there a UIKit equivalent to the SwiftUI specialist skill?
- **dev** (2:03 PM): What other skills are there for app development?

## Q (2:07 PM, ▲0, open): How does the hitch data in the new MetricKit report map from the deprecated payloads?

FB24877286 (MetricKit: Add clarifing detail on mapping of MXAnimationMetric and HitchTimeMetric)

## Q (2:09 PM, ▲0, open): Aside from the metadata or environment being optional in MetricKit metrics types, what are some other edges of the APIs that might be worth knowing about or paying careful attention to? 

For example knowing and feeling confident to pitch unrealistic data (ex runtime greater than 24 hours).

## Q (2:14 PM, ▲0, open): When relying on pipelines for instrumentation / profiling, should we use physical devices with pipelines and if so, would using the oldest supported physical device in pipeline to profile the app be better? Will it be a good measurement of my app for the rest of the relatively new devices?
