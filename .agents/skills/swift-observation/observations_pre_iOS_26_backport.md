Title: iOS 18 support for the Observations struct is being dropped before release? - Using Swift - Swift Forums

URL Source: https://forums.swift.org/t/ios-18-support-for-the-observations-struct-is-being-dropped-before-release

Published Time: 2025-09-03T08:27:54+00:00

Markdown Content:
post by LucasVanDongen on Sep 3, 2025
-------------------------------------

[![Image 1: Lucas van Dongen](https://sea2.discourse-cdn.com/swift/user_avatar/forums.swift.org/lucasvandongen/48/32387_2.png)](https://forums.swift.org/t/ios-18-support-for-the-observations-struct-is-being-dropped-before-release)

When I started looking into this new addition I was sure as hell it was back ported to iOS 18. Now the documentation claims it’s v26 only. For me that’s a pretty big blow as this is kind of the missing piece of the puzzle before going full in to Swift Concurrency.

post by Philippe_Hausler on Sep 3, 2025
---------------------------------------

[![Image 2](https://sea2.discourse-cdn.com/swift/user_avatar/forums.swift.org/philippe_hausler/48/22569_2.png)](https://forums.swift.org/t/ios-18-support-for-the-observations-struct-is-being-dropped-before-release)

This wasn't really able to be back ported since it is a type - there are fundamentals that are kinda missing that would allow it to be available to before the '26 releases.

post by Jon_Shier on Sep 3, 2025
--------------------------------

[![Image 3](https://sea2.discourse-cdn.com/swift/user_avatar/forums.swift.org/jon_shier/48/921_2.png)](https://forums.swift.org/t/ios-18-support-for-the-observations-struct-is-being-dropped-before-release)

[`swift-perception`](https://github.com/pointfreeco/swift-perception) is a full backport of the `Observable` machinery, including `Observations`, as various `Perception` types. This includes OSes that predate Observable altogether, as well as SwiftUI and UIKit integration.

post by joshw on Sep 3, 2025
----------------------------

[![Image 4](https://sea2.discourse-cdn.com/swift/user_avatar/forums.swift.org/joshw/48/34626_2.png)](https://forums.swift.org/t/ios-18-support-for-the-observations-struct-is-being-dropped-before-release)

[@Philippe_Hausler](https://forums.swift.org/u/philippe_hausler) is back porting this something that could be reconsidered? It’s a pretty huge unblock for a lot of teams switching to concurrency and replacing older streaming libraries in their code - would be a big win for a lot of teams (ours included ![Image 5: :smiley:](https://emoji.discourse-cdn.com/apple/smiley.png?v=14) ) if we could adopt a year earlier!

post by vanvoorden on Sep 3, 2025
---------------------------------

[![Image 6](https://sea2.discourse-cdn.com/swift/user_avatar/forums.swift.org/vanvoorden/48/33619_2.png)](https://forums.swift.org/t/ios-18-support-for-the-observations-struct-is-being-dropped-before-release)

From just a quick experiment on my local machine… if I copy `Observations.swift` and `Locking.swift` from the `Observation` directory in `swift` I can import that code in a new package that deploys back to macOS 15. I can then build and run the `Person` example from [SE-0475](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0475-observed.md) and I don't see any crashes so far… but maybe there is something else lurking there that makes this unstable on macOS 15?

post by Philippe_Hausler on Sep 3, 2025
---------------------------------------

[![Image 7](https://sea2.discourse-cdn.com/swift/user_avatar/forums.swift.org/philippe_hausler/48/22569_2.png)](https://forums.swift.org/t/ios-18-support-for-the-observations-struct-is-being-dropped-before-release)

The problem is not about the implementation but instead about the back porting of types themselves w.r.t. to ABI stability. Normally back deployed things are available to just be functions. Since this is a full type layout that metadata does not currently have any direct affordances in the language to make it available to anything beyond the newest release.

Personally I agree that the utility for folks to be able to use this before `26 aligned releases of swift is pretty impactful, however there are a lot of moving parts logistically that would need to be solved to back deploy the type itself.

Since it is open source you can copy the implementations as listed; so at least there is a caveat emptor version of a work-around... That is likely workable till I have done some feasibility research on how we could even approach this.

post by Kyle-Ye on Sep 4, 2025
------------------------------

[![Image 8](https://sea2.discourse-cdn.com/swift/user_avatar/forums.swift.org/kyle-ye/48/19686_2.png)](https://forums.swift.org/t/ios-18-support-for-the-observations-struct-is-being-dropped-before-release)

You can also give a try for [`OpenObservation`](https://github.com/OpenSwiftUIProject/OpenObservation) in general usage of `Observable` feature if you are not care about SwiftUI.

Both `OpenObservation` and `swift-perception` provide full backport of the `Observable` machinery and the macros.

The key differentiator is OpenObservation's SPI access is to OpenSwiftUI. And when building with toolchain path set, OpenObservation will share the same thread local storage with Observation providing mix use or debugging Observation possibility. (See [OpenObservation/Sources/OpenObservationCxx/ThreadLocal.cpp at 1dd8b16a539e3563e05b77749acf334a4857a6a7 · OpenSwiftUIProject/OpenObservation · GitHub](https://github.com/OpenSwiftUIProject/OpenObservation/blob/1dd8b16a539e3563e05b77749acf334a4857a6a7/Sources/OpenObservationCxx/ThreadLocal.cpp#L13-L31))

While IMO swift-perception is more focus on developer ergonomics and provide more SwiftUI integrations. (eg. Perception.Bindable and WithPerceptionTracking in SwiftUI's body.)

> OpenObservation does not provide such ability since those part is already included in OpenSwiftUI.

post by LucasVanDongen on Sep 4, 2025
-------------------------------------

post by Philippe_Hausler on Sep 4, 2025
---------------------------------------

post by vanvoorden on Sep 4, 2025
---------------------------------

