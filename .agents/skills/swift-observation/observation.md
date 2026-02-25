# https://developer.apple.com/documentation/observation

Framework

# Observation

Make responsive apps that update the presentation when underlying data changes.

## Overview

Observation provides a robust, type-safe, and performant implementation of the observer design pattern in Swift. This pattern allows an observable object to maintain a list of observers and notify them of specific or general state changes. This has the advantages of not directly coupling objects together and allowing implicit distribution of updates across potential multiple observers.

The Observation frameworks provides the following capabilities:

- Marking a type as observable

- Tracking changes within an instance of an observable type

- Observing and utilizing those changes elsewhere, such as in an app’s user interface

To declare a type as observable, attach the `Observable()` macro to the type declaration. This macro declares and implements conformance to the `Observable` protocol to the type at compile time.

@Observable
class Car {
var name: String = ""
var needsRepairs: Bool = false

init(name: String, needsRepairs: Bool = false) {
self.name = name
self.needsRepairs = needsRepairs
}
}

To track changes, use the `withObservationTracking(_:onChange:)` function. For example, in the following code, the function calls the `onChange` closure when a car’s name changes. However, it doesn’t call the closure when a car’s `needsRepair` flag changes. That’s because the function only tracks properties read in its `apply` closure, and the closure doesn’t read the `needsRepair` property.

func render() {
withObservationTracking {
for car in cars {
print(car.name)
}
} onChange: {
print("Schedule renderer.")
}
}

## Topics

### Observable conformance

`macro Observable()`

Defines and implements conformance of the Observable protocol.

`protocol Observable`

A type that emits notifications to observers when underlying data changes.

### Change tracking

Tracks access to properties.

`struct ObservationRegistrar`

Provides storage for tracking and access to data changes.

### Observation in SwiftUI

Managing model data in your app

Create connections between your app’s data model and views.

Migrating from the Observable Object protocol to the Observable macro

Update your existing app to leverage the benefits of Observation in Swift.

### Structures

`struct Observations`

An asychronous sequence generated from a closure that tracks the transactional changes of `@Observable` types.

### Macros

`macro ObservationIgnored()`

Disables observation tracking of a property.

`macro ObservationTracked()`

Synthesizes a property for accessors.

---

# https://developer.apple.com/documentation/observation/observable()

#app-main)

- Observation
- Observable()

Macro

# Observable()

Defines and implements conformance of the Observable protocol.

@attached(member, names: named(_$observationRegistrar), named(access), named(withMutation), named(shouldNotifyObservers)) @attached(memberAttribute) @attached(extension, conformances: Observable) macro Observable()

## Mentioned in

Applying Macros

## Overview

This macro adds observation support to a custom type and conforms the type to the `Observable` protocol. For example, the following code applies the `Observable` macro to the type `Car` making it observable:

@Observable
class Car {
var name: String = ""
var needsRepairs: Bool = false

init(name: String, needsRepairs: Bool = false) {
self.name = name
self.needsRepairs = needsRepairs
}
}

## See Also

### Observable conformance

`protocol Observable`

A type that emits notifications to observers when underlying data changes.

---

# https://developer.apple.com/documentation/observation/observable

- Observation
- Observable

Protocol

# Observable

A type that emits notifications to observers when underlying data changes.

protocol Observable

## Mentioned in

Applying Macros

## Overview

Conforming to this protocol signals to other APIs that the type supports observation. However, applying the `Observable` protocol by itself to a type doesn’t add observation functionality to the type. Instead, always use the `Observable()` macro when adding observation support to a type.

## See Also

### Observable conformance

`macro Observable()`

Defines and implements conformance of the Observable protocol.

---

# https://developer.apple.com/documentation/observation/withobservationtracking(_:onchange:)

#app-main)

- Observation
- withObservationTracking(\_:onChange:)

Function

# withObservationTracking(\_:onChange:)

Tracks access to properties.

## Parameters

`apply`

A closure that contains properties to track.

`onChange`

The closure invoked when the value of a property changes.

## Return Value

The value that the `apply` closure returns if it has a return value; otherwise, there is no return value.

## Discussion

This method tracks access to any property within the `apply` closure, and informs the caller of value changes made to participating properties by way of the `onChange` closure. For example, the following code tracks changes to the name of cars, but it doesn’t track changes to any other property of `Car`:

func render() {
withObservationTracking {
for car in cars {
print(car.name)
}
} onChange: {
print("Schedule renderer.")
}
}

## See Also

### Change tracking

`struct ObservationRegistrar`

Provides storage for tracking and access to data changes.

---

# https://developer.apple.com/documentation/observation/observationregistrar

- Observation
- ObservationRegistrar

Structure

# ObservationRegistrar

Provides storage for tracking and access to data changes.

struct ObservationRegistrar

## Overview

You don’t need to create an instance of `ObservationRegistrar` when using the `Observable()` macro to indicate observability of a type.

## Topics

### Creating an observation registrar

`init()`

Creates an instance of the observation registrar.

### Receiving change notifications

A property observation called before setting the value of the subject.

A property observation called after setting the value of the subject.

### Identifying transactional access

Registers access to a specific property for observation.

Identifies mutations to the transactions registered for observers.

## Relationships

### Conforms To

- `Copyable`
- `Decodable`
- `Encodable`
- `Equatable`
- `Hashable`
- `Sendable`
- `SendableMetatype`

## See Also

### Change tracking

Tracks access to properties.

---

# https://developer.apple.com/documentation/observation/observations

- Observation
- Observations

Structure

# Observations

An asychronous sequence generated from a closure that tracks the transactional changes of `@Observable` types.

## Overview

`Observations` conforms to `AsyncSequence`, providing a intutive and safe mechanism to track changes to types that are marked as `@Observable` by using Swift Concurrency to indicate transactional boundaries starting from the willSet of the first mutation to the next suspension point of the safe access.

## Topics

### Structures

`struct Iterator`

### Initializers

Constructs an asynchronous sequence for a given closure by tracking changes of `@Observable` types.

### Type Methods

### Enumerations

`enum Iteration`

## Relationships

### Conforms To

- `AsyncSequence`
- `Sendable`
- `SendableMetatype`

---

# https://developer.apple.com/documentation/observation/observationignored()

#app-main)

- Observation
- ObservationIgnored()

Macro

# ObservationIgnored()

Disables observation tracking of a property.

@attached(accessor)
macro ObservationIgnored()

## Overview

By default, an object can observe any property of an observable type that is accessible to the observing object. To prevent observation of an accessible property, attach the `ObservationIgnored` macro to the property.

---

# https://developer.apple.com/documentation/observation/observationtracked()

#app-main)

- Observation
- ObservationTracked()

Macro

# ObservationTracked()

Synthesizes a property for accessors.

@attached(accessor, names: named(init), named(get), named(set), named(_modify)) @attached(peer, names: prefixed(`_`))
macro ObservationTracked()

## Overview

The Observation module uses this macro. Its use outside of the framework isn’t necessary.

---

# https://developer.apple.com/documentation/observation/observable())



---

# https://developer.apple.com/documentation/observation/observable)



---

# https://developer.apple.com/documentation/observation/withobservationtracking(_:onchange:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/observation/observationregistrar)



---

# https://developer.apple.com/documentation/observation/observations)



---

# https://developer.apple.com/documentation/observation/observationignored())



---

# https://developer.apple.com/documentation/observation/observationtracked())



---

# https://developer.apple.com/documentation/observation/observations/iterator

- Observation
- Observations
- Observations.Iterator

Structure

# Observations.Iterator

struct Iterator

## Relationships

### Conforms To

- `AsyncIteratorProtocol`

---

# https://developer.apple.com/documentation/observation/observations/init(_:)

#app-main)

- Observation
- Observations
- init(\_:)

Initializer

# init(\_:)

Constructs an asynchronous sequence for a given closure by tracking changes of `@Observable` types.

## Parameters

`emit`

A closure to generate an element for the sequence.

## Discussion

The emit closure is responsible for extracting a value out of a single or many `@Observable` types.

---

# https://developer.apple.com/documentation/observation/observations/untilfinished(_:)

#app-main)

- Observation
- Observations
- untilFinished(\_:)

Type Method

# untilFinished(\_:)

Constructs an asynchronous sequence for a given closure by tracking changes of `@Observable` types.

## Parameters

`emit`

A closure to generate an element for the sequence.

## Discussion

The emit closure is responsible for extracting a value out of a single or many `@Observable` types. This method continues to be invoked until the .finished option is returned or an error is thrown.

---

# https://developer.apple.com/documentation/observation/observations/iteration

- Observation
- Observations
- Observations.Iteration

Enumeration

# Observations.Iteration

enum Iteration

## Topics

### Enumeration Cases

`case finish`

`case next(Element)`

## Relationships

### Conforms To

- `Sendable`
- `SendableMetatype`

---

# https://developer.apple.com/documentation/observation/observations/iterator)



---

# https://developer.apple.com/documentation/observation/observations/init(_:))



---

# https://developer.apple.com/documentation/observation/observations/untilfinished(_:))



---

# https://developer.apple.com/documentation/observation/observations/iteration)



---

# https://developer.apple.com/documentation/observation/observationregistrar/init()

#app-main)

- Observation
- ObservationRegistrar
- init()

Initializer

# init()

Creates an instance of the observation registrar.

init()

## Discussion

You don’t need to create an instance of `ObservationRegistrar` when using the `Observable()` macro to indicate observably of a type.

---

# https://developer.apple.com/documentation/observation/observationregistrar/willset(_:keypath:)

#app-main)

- Observation
- ObservationRegistrar
- willSet(\_:keyPath:)

Instance Method

# willSet(\_:keyPath:)

A property observation called before setting the value of the subject.

_ subject: Subject,

## Parameters

`subject`

An instance of an observable type.

`keyPath`

The key path of an observed property.

## See Also

### Receiving change notifications

A property observation called after setting the value of the subject.

---

# https://developer.apple.com/documentation/observation/observationregistrar/didset(_:keypath:)

#app-main)

- Observation
- ObservationRegistrar
- didSet(\_:keyPath:)

Instance Method

# didSet(\_:keyPath:)

A property observation called after setting the value of the subject.

_ subject: Subject,

## Parameters

`subject`

An instance of an observable type.

`keyPath`

The key path of an observed property.

## See Also

### Receiving change notifications

A property observation called before setting the value of the subject.

---

# https://developer.apple.com/documentation/observation/observationregistrar/access(_:keypath:)

#app-main)

- Observation
- ObservationRegistrar
- access(\_:keyPath:)

Instance Method

# access(\_:keyPath:)

Registers access to a specific property for observation.

_ subject: Subject,

## Parameters

`subject`

An instance of an observable type.

`keyPath`

The key path of an observed property.

## See Also

### Identifying transactional access

Identifies mutations to the transactions registered for observers.

---

# https://developer.apple.com/documentation/observation/observationregistrar/withmutation(of:keypath:_:)

#app-main)

- Observation
- ObservationRegistrar
- withMutation(of:keyPath:\_:)

Instance Method

# withMutation(of:keyPath:\_:)

Identifies mutations to the transactions registered for observers.

of subject: Subject,

## Parameters

`subject`

An instance of an observable type.

`keyPath`

The key path of an observed property.

## Discussion

This method calls `willSet(_:keyPath:)` before the mutation. Then it calls `didSet(_:keyPath:)` after the mutation.

## See Also

### Identifying transactional access

Registers access to a specific property for observation.

---

# https://developer.apple.com/documentation/observation/observationregistrar/init())



---

# https://developer.apple.com/documentation/observation/observationregistrar/willset(_:keypath:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/observation/observationregistrar/didset(_:keypath:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/observation/observationregistrar/access(_:keypath:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/observation/observationregistrar/withmutation(of:keypath:_:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/observation/observations/iteration/finish

- Observation
- Observations
- Observations.Iteration
- Observations.Iteration.finish

Case

# Observations.Iteration.finish

case finish

---

# https://developer.apple.com/documentation/observation/observations/iteration/next(_:)

#app-main)

- Observation
- Observations
- Observations.Iteration
- Observations.Iteration.next(\_:)

Case

# Observations.Iteration.next(\_:)

case next(Element)

---

# https://developer.apple.com/documentation/observation/observations/iteration/finish)



---

# https://developer.apple.com/documentation/observation/observations/iteration/next(_:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

